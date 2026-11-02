//
//  SpeechService.swift
//  vox
//
//  Created by Pedro Planel on 01/11/26.
//

@preconcurrency import AVFoundation
import Foundation
import Speech
import AppKit
import Combine

/// Captures microphone audio with AVAudioEngine and transcribes it live
/// using SpeechAnalyzer/SpeechTranscriber (on-device).
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

    /// Finalized text. Editable by the UI.
    @Published var transcript: String = ""

    /// Tentative text for the phrase currently being spoken.
    @Published private(set) var volatileText: String = ""

    var isRecording: Bool { status == .recording }
    
    // Settings
    private var enableVoiceCommands: Bool {
        UserDefaults.standard.bool(forKey: "enableVoiceCommands")
    }
    
    private var commandPrefix: String {
        UserDefaults.standard.string(forKey: "commandPrefix") ?? "vox"
    }

    private let audioEngine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputBuilder: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    func toggle() async {
        if isRecording {
            await stop()
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
        } catch {
            tearDown()
            status = .error(error.localizedDescription)
        }
    }

    func stop() async {
        guard isRecording else { return }
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
        
        // Copiar para clipboard se ativado
        if UserDefaults.standard.bool(forKey: "autoCopyToClipboard") && !transcript.isEmpty {
            copyToClipboard()
        }
    }

    private var isErrored: Bool {
        if case .error = status { return true }
        return false
    }

    private func beginTranscription() async throws {
        // Solicitar permissão de microfone
        let permission = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
        
        guard permission else {
            throw VoxSpeechError.microphoneDenied
        }
        
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
            throw VoxSpeechError.unsupportedLocale
        }

        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
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

        resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        // Processar comandos de voz se ativado
                        if enableVoiceCommands, processVoiceCommand(text) {
                            // Comando processado, não adicionar ao transcript
                            volatileText = ""
                        } else {
                            transcript += text
                            volatileText = ""
                        }
                    } else {
                        volatileText = text
                    }
                }
            } catch {
                status = .error(error.localizedDescription)
            }
        }

        let inputNode = audioEngine.inputNode
        let tapFormat = inputNode.outputFormat(forBus: 0)
        guard tapFormat.sampleRate > 0 else {
            throw VoxSpeechError.noMicrophone
        }
        guard let converter = AVAudioConverter(from: tapFormat, to: analyzerFormat) else {
            throw VoxSpeechError.audioConversionFailed
        }

        // The tap runs on an audio thread; it only touches the converter,
        // the analyzer format and the stream continuation — never `self`.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { buffer, _ in
            guard let converted = Self.convert(buffer, using: converter, to: analyzerFormat) else { return }
            inputBuilder.yield(AnalyzerInput(buffer: converted))
        }

        audioEngine.prepare()
        try audioEngine.start()
        try await analyzer.start(inputSequence: inputSequence)
    }

    private func tearDown() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
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
    
    // MARK: - Voice Commands
    
    private func processVoiceCommand(_ text: String) -> Bool {
        let lowercased = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = commandPrefix.lowercased()
        
        guard lowercased.hasPrefix(prefix) else { return false }
        
        let command = lowercased.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        
        switch command {
        case "copiar":
            copyToClipboard()
            return true
            
        case "limpar":
            transcript = ""
            return true
            
        case "parar":
            Task { await stop() }
            return true
            
        case "novo parágrafo", "nova linha":
            transcript += "\n\n"
            return true
            
        case "apagar última frase":
            removeLastSentence()
            return true
            
        default:
            return false
        }
    }
    
    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcript, forType: .string)
    }
    
    private func removeLastSentence() {
        // Remove a última frase (termina com . ! ? ou última linha)
        let sentences = transcript.components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
        if sentences.count > 1 {
            let remainingSentences = sentences.dropLast()
            transcript = remainingSentences.joined(separator: ". ")
            if !transcript.isEmpty && !transcript.hasSuffix(".") {
                transcript += "."
            }
        }
    }
}

enum VoxSpeechError: LocalizedError {
    case microphoneDenied
    case unsupportedLocale
    case modelUnavailable
    case noMicrophone
    case audioConversionFailed

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
        }
    }
}
