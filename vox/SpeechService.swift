//
//  SpeechService.swift
//  vox
//
//  Created by Pedro Planel on 01/11/26.
//

@preconcurrency import AVFoundation
import Foundation
import Speech
import Combine
import os

private let log = Logger(subsystem: "dev.pplanel.vox", category: "Speech")

/// Receives what `SpeechService` recognizes; `CommandExecutor` decides what to do with it.
@MainActor
protocol SpeechServiceDelegate: AnyObject {
    /// Before recognition is set up, so entities can be refreshed for its vocabulary.
    func speechServiceWillStart(_ service: SpeechService)
    func speechService(_ service: SpeechService, didRecognize text: String, isFinal: Bool)
    /// A message for the island ("Microfone reconectado").
    func speechService(_ service: SpeechService, notice: String)
    /// Recording ended (stopped or gave up). Not called while recognition restarts after a drop.
    func speechServiceDidStop(_ service: SpeechService)
}

/// Captures microphone audio with AVAudioEngine and transcribes it live
/// using SpeechAnalyzer/SpeechTranscriber (on-device). Only recognizes: every effect of what
/// was said happens in `CommandExecutor`.
@MainActor
final class SpeechService: ObservableObject {
    enum Status: Equatable {
        case idle
        case preparing
        case downloadingModel
        case recording
        case error(String)
    }

    @Published private(set) var status: Status = .idle {
        didSet {
            NotificationCenter.default.post(name: .speechServiceStatusChanged, object: nil)
        }
    }

    /// Tentative text for the phrase currently being spoken.
    @Published private(set) var volatileText: String = ""

    var isRecording: Bool { status == .recording }

    weak var delegate: SpeechServiceDelegate?

    /// The wake word, to bias recognition toward it.
    private var commandPrefix: String {
        UserDefaults.standard.string(forKey: "commandPrefix") ?? "vox"
    }

    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: (any SpeechModule)?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    /// The transcriber's format, kept to rebuild the microphone tap when the input device changes.
    private var analyzerFormat: AVAudioFormat?
    private var configurationObserver: NSObjectProtocol?
    /// Set while `stop()` drains the analyzer, so the results ending isn't taken for a drop.
    private var isStopping = false
    /// When recognition was restarted after dropping; more than a few a minute means it's broken.
    private var recoveries: [ContinuousClock.Instant] = []

    func toggle() async {
        if isRecording {
            await stop(reason: "atalho ou menu")
        } else {
            await start()
        }
    }

    func start() async {
        guard status == .idle || isErrored else { return }
        status = .preparing
        do {
            try await beginTranscription()
            status = .recording
            log.info("Recording started")
        } catch {
            log.error("Recording failed to start: \(error.localizedDescription, privacy: .public)")
            tearDown()
            status = .error(error.localizedDescription)
        }
    }

    func stop(reason: String = "pedido do usuário") async {
        guard isRecording else { return }
        log.info("Recording stopped: \(reason, privacy: .public)")
        isStopping = true
        defer { isStopping = false }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        inputBuilder?.finish()
        // Waits for the remaining audio to be consumed and finalized,
        // so the last phrase still lands in `transcript`.
        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        tearDown()
        status = .idle
        delegate?.speechServiceDidStop(self)
    }

    private var isErrored: Bool {
        if case .error = status { return true }
        return false
    }

    private func beginTranscription() async throws {
        delegate?.speechServiceWillStart(self)
        // Solicitar permissão de microfone
        let permission = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        
        guard permission else {
            throw VoxSpeechError.microphoneDenied
        }
        
        // Idioma escolhido em Ajustes → Reconhecimento (vazio = idioma do sistema)
        let requestedLocale = SpeechSettings.localeIdentifier.isEmpty
            ? Locale.current
            : Locale(identifier: SpeechSettings.localeIdentifier)
        let dictation = SpeechSettings.customVocabularyEnabled
            ? await makeDictationTranscriber(for: requestedLocale)
            : nil
        let speech: SpeechTranscriber?
        if dictation == nil {
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
                throw VoxSpeechError.unsupportedLocale
            }
            speech = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: SpeechSettings.transcriptionOptions,
                reportingOptions: SpeechSettings.reportingOptions,
                attributeOptions: []
            )
        } else {
            speech = nil
        }
        guard let transcriber: any SpeechModule = dictation ?? speech else {
            throw VoxSpeechError.unsupportedLocale
        }
        self.transcriber = transcriber

        if let installationRequest = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            status = .downloadingModel
            try await installationRequest.downloadAndInstall()
        }

        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw VoxSpeechError.modelUnavailable
        }

        let (inputSequence, inputBuilder) = AsyncStream.makeStream(of: AnalyzerInput.self)
        self.inputBuilder = inputBuilder

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        // Bias recognition toward the wake word and the names from Settings → Comandos de voz;
        // non-English models rarely know "vox" and tend to hear "Claude" as "Cláudio".
        let context = AnalysisContext()
        let labels = VoiceCommandStore.shared.config.entities.flatMap(\.values).map(\.label).filter { !$0.isEmpty }
        context.contextualStrings[.general] = [commandPrefix] + labels
        try? await analyzer.setContext(context)

        // The two transcribers have distinct result types, hence two loops.
        resultsTask = Task {
            do {
                if let dictation {
                    for try await result in dictation.results {
                        recognized(String(result.text.characters), isFinal: result.isFinal)
                    }
                } else if let speech {
                    for try await result in speech.results {
                        recognized(String(result.text.characters), isFinal: result.isFinal)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                recognitionDropped("erro: \(error.localizedDescription)")
                return
            }
            guard !Task.isCancelled else { return }
            recognitionDropped("o reconhecimento terminou sozinho")
        }

        self.analyzerFormat = analyzerFormat
        try Self.startMicrophone(audioEngine, to: analyzerFormat, feeding: inputBuilder)
        // Connecting AirPods or changing the input device stops the engine; it's restarted
        // with the new device's format instead of leaving recording silently deaf.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: audioEngine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.audioConfigurationChanged() }
        }
        try await analyzer.start(inputSequence: inputSequence)
    }

    /// Installs the microphone tap and starts the engine. Static and nonisolated because the tap
    /// runs on an audio thread; it only touches the converter, the format and the continuation.
    nonisolated private static func startMicrophone(
        _ engine: AVAudioEngine,
        to analyzerFormat: AVAudioFormat,
        feeding inputBuilder: AsyncStream<AnalyzerInput>.Continuation
    ) throws {
        let inputNode = engine.inputNode
        let tapFormat = inputNode.outputFormat(forBus: 0)
        guard tapFormat.sampleRate > 0 else {
            throw VoxSpeechError.noMicrophone
        }
        guard let converter = AVAudioConverter(from: tapFormat, to: analyzerFormat) else {
            throw VoxSpeechError.audioConversionFailed
        }
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { buffer, _ in
            guard let converted = convert(buffer, using: converter, to: analyzerFormat) else { return }
            inputBuilder.yield(AnalyzerInput(buffer: converted))
        }
        engine.prepare()
        try engine.start()
    }

    private func audioConfigurationChanged() {
        guard isRecording, !isStopping, let analyzerFormat, let inputBuilder else { return }
        log.info("Audio input changed; restarting the microphone")
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        do {
            try Self.startMicrophone(audioEngine, to: analyzerFormat, feeding: inputBuilder)
            delegate?.speechService(self, notice: "Microfone reconectado")
        } catch {
            recognitionDropped("microfone: \(error.localizedDescription)")
        }
    }

    /// The results stream ended or failed while recording: restarts recognition without telling
    /// the delegate it stopped (so typing mode survives), unless it already dropped three times in a minute.
    private func recognitionDropped(_ reason: String) {
        guard isRecording, !isStopping else { return }
        log.error("Recognition dropped: \(reason, privacy: .public)")
        let now = ContinuousClock.now
        recoveries = recoveries.filter { now - $0 < .seconds(60) }
        guard recoveries.count < 3 else {
            log.error("Recording stopped: recognition keeps dropping")
            tearDown()
            status = .error("O reconhecimento parou (\(reason))")
            delegate?.speechServiceDidStop(self)
            return
        }
        recoveries.append(now)
        tearDown()
        status = .idle
        // A new task: this may run inside the results task, which `tearDown` just cancelled.
        Task {
            await start()
            guard isRecording else {
                delegate?.speechServiceDidStop(self)
                return
            }
            log.info("Recognition restarted")
            delegate?.speechService(self, notice: "Reconhecimento reiniciado")
        }
    }

    private func recognized(_ text: String, isFinal: Bool) {
        volatileText = isFinal ? "" : text
        delegate?.speechService(self, didRecognize: text, isFinal: isFinal)
    }

    /// Dictation model with the custom vocabulary from `CustomVocabulary`. Returns nil when the
    /// locale or the model isn't available, so recording falls back to `SpeechTranscriber`.
    private func makeDictationTranscriber(for requestedLocale: Locale) async -> DictationTranscriber? {
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            log.info("Custom vocabulary: dictation doesn't support \(requestedLocale.identifier, privacy: .public)")
            return nil
        }
        do {
            let configuration = try await CustomVocabulary.configuration(for: locale, wakeWord: commandPrefix,
                                                                         config: VoiceCommandStore.shared.config)
            return DictationTranscriber(
                locale: locale,
                contentHints: [.customizedLanguage(modelConfiguration: configuration)],
                transcriptionOptions: SpeechSettings.dictationTranscriptionOptions,
                reportingOptions: SpeechSettings.dictationReportingOptions,
                attributeOptions: []
            )
        } catch {
            log.error("Custom vocabulary unavailable: \(error.localizedDescription, privacy: .public)")
            delegate?.speechService(self, notice: "Vocabulário personalizado indisponível")
            return nil
        }
    }

    private func tearDown() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        // The tap stays installed when the engine stopped on its own (device change).
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        analyzerFormat = nil
        inputBuilder?.finish()
        inputBuilder = nil
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        transcriber = nil
        volatileText = ""
    }

    nonisolated private static func convert(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter,
        to format: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }

        var consumed = false
        var conversionError: NSError?
        let conversionStatus = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        return conversionStatus == .error ? nil : output
    }
}

/// Keys and defaults for the Apple Speech options shown in Settings → Reconhecimento.
/// Defaults match the previous `.progressiveTranscription` preset.
enum SpeechSettings {
    static let localeKey = "speechLocale"
    static let volatileResultsKey = "speechVolatileResults"
    static let fastResultsKey = "speechFastResults"
    static let etiquetteReplacementsKey = "speechEtiquetteReplacements"
    static let commandAliasesKey = "commandAliases"
    static let customVocabularyKey = "speechCustomVocabulary"
    static let silenceActionKey = "silenceAction"
    static let silenceActionValueKey = "silenceActionValue"
    static let silenceSecondsKey = "silenceSeconds"
    /// Default must match @AppStorage in GeneralSettingsView.
    static let defaultSilenceSeconds = 5.0

    /// What happens after the given seconds without speech, once per dictated stretch.
    enum SilenceAction: String, CaseIterable {
        case none
        /// A key or shortcut in the focused app ("return", "cmd+enter"), see `KeyCombo`.
        case keys
        /// What would follow the wake word: a `<comando>`, a `<tecla>` or a template ("enviar").
        case voxCommand
        /// A shell command, run in the background like the "Segundo plano" templates.
        case shell

        var displayName: String {
            switch self {
            case .none: "Nada"
            case .keys: "Tecla ou atalho"
            case .voxCommand: "Comando do Vox"
            case .shell: "Comando de shell"
            }
        }
    }

    static var silenceAction: SilenceAction {
        UserDefaults.standard.string(forKey: silenceActionKey).flatMap(SilenceAction.init(rawValue:)) ?? .none
    }

    static var silenceActionValue: String {
        (UserDefaults.standard.string(forKey: silenceActionValueKey) ?? "").trimmingCharacters(in: .whitespaces)
    }

    static var silenceSeconds: Double {
        let seconds = UserDefaults.standard.object(forKey: silenceSecondsKey) as? Double ?? defaultSilenceSeconds
        return max(1, seconds)
    }
    /// Default must match @AppStorage in SpeechRecognitionSettingsView.
    static let defaultCommandAliases = "voz, vós, box, boxe, fox"

    /// Comma-separated alternatives accepted for the wake word.
    static var commandAliases: [String] {
        (UserDefaults.standard.string(forKey: commandAliasesKey) ?? defaultCommandAliases)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static var localeIdentifier: String {
        UserDefaults.standard.string(forKey: localeKey) ?? ""
    }

    static var transcriptionOptions: Set<SpeechTranscriber.TranscriptionOption> {
        bool(etiquetteReplacementsKey, default: false) ? [.etiquetteReplacements] : []
    }

    /// Default must match @AppStorage in SpeechRecognitionSettingsView (false): on macOS the
    /// Speech service refuses to compile the model for this unsandboxed app
    /// ("Caller lacks write access to outDirectory"), so it's opt-in for now.
    static var customVocabularyEnabled: Bool {
        bool(customVocabularyKey, default: false)
    }

    /// Unlike `SpeechTranscriber`, dictation only punctuates when asked to.
    static var dictationTranscriptionOptions: Set<DictationTranscriber.TranscriptionOption> {
        var options: Set<DictationTranscriber.TranscriptionOption> = [.punctuation]
        if bool(etiquetteReplacementsKey, default: false) { options.insert(.etiquetteReplacements) }
        return options
    }

    /// `frequentFinalization` is dictation's counterpart to `fastResults`.
    static var dictationReportingOptions: Set<DictationTranscriber.ReportingOption> {
        var options: Set<DictationTranscriber.ReportingOption> = []
        if bool(volatileResultsKey, default: true) { options.insert(.volatileResults) }
        if bool(fastResultsKey, default: true) { options.insert(.frequentFinalization) }
        return options
    }

    static var reportingOptions: Set<SpeechTranscriber.ReportingOption> {
        var options: Set<SpeechTranscriber.ReportingOption> = []
        if bool(volatileResultsKey, default: true) { options.insert(.volatileResults) }
        if bool(fastResultsKey, default: true) { options.insert(.fastResults) }
        return options
    }

    /// `UserDefaults.bool(forKey:)` returns false for unset keys, which would ignore the defaults.
    private static func bool(_ key: String, default defaultValue: Bool) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? defaultValue
    }
}

enum VoxSpeechError: LocalizedError {
    case microphoneDenied
    case unsupportedLocale
    case modelUnavailable
    case noMicrophone
    case audioConversionFailed
    case speechRecognitionDenied

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Permissão de microfone negada. Libere em Ajustes do Sistema → Privacidade → Microfone."
        case .unsupportedLocale:
            return "O idioma atual do sistema não é suportado pela transcrição."
        case .modelUnavailable:
            return "O modelo de transcrição não está disponível neste Mac."
        case .noMicrophone:
            return "Nenhum microfone disponível."
        case .audioConversionFailed:
            return "Não foi possível converter o áudio do microfone para o formato do transcritor."
        case .speechRecognitionDenied:
            return "Permissão de reconhecimento de fala negada. Libere em Ajustes do Sistema → Privacidade → Reconhecimento de Fala."
        }
    }
}
