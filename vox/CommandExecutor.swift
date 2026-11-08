//
//  CommandExecutor.swift
//  vox
//
//  Created by Pedro Planel on 04/11/26.
//

import AppKit
import Combine
import os

private let log = Logger(subsystem: "dev.pplanel.vox", category: "VoiceCommands")

/// The one place where speech turns into effects: the transcript, typing into the focused app,
/// built-in commands, templates (shell, tmux, app focus, keys), confirmations and the silence
/// action. `SpeechService` only recognizes; `VoiceCommandRouter` only interprets.
@MainActor
final class CommandExecutor: ObservableObject, SpeechServiceDelegate {
    /// Finalized dictation. Editable by the UI.
    @Published var transcript: String = ""

    /// After "vox" focuses a text area, dictation is typed into the focused app.
    /// Lasts until recording stops.
    @Published private(set) var isTypingIntoApp = false

    /// Short status shown in the island after a command ("Digitando em Notas", errors…).
    @Published private(set) var feedback: String?
    private var feedbackTask: Task<Void, Never>?

    private weak var speech: SpeechService?
    private var router = VoiceCommandRouter(wakeWord: "vox", aliases: [], isEnabled: true)

    /// Whether a segment was already typed in this session, so the next one gets a separating space.
    private var hasTypedSegment = false
    /// Text already typed into the app for the phrase still being recognized. Volatile results
    /// are typed as they arrive and corrected in place, so the app shows speech as it happens.
    private var liveTypedText = ""
    /// Waits for the app picked by "vox <app>" to come forward before typing into it.
    private var switchTask: Task<Void, Never>?

    /// A template ("vox abre o <agente>…") waiting for "vox sim" / "vox não".
    private var pendingLaunch: PreparedCommand?
    /// Identifies `pendingLaunch`'s confirmation notification, so a click on an old one
    /// can't run a newer command.
    private var pendingLaunchID: UUID?
    /// Picking the template and its values with the model takes a second or two.
    private var launchTask: Task<Void, Never>?

    /// Restarted by every result; fires the silence action when it runs out.
    private var silenceTask: Task<Void, Never>?
    /// Dictation since the last command or silence action, so silence acts once per stretch
    /// and not right after "vox enviar" already sent the message.
    private var dictatedSinceSilence = false

    init(speech: SpeechService) {
        self.speech = speech
        speech.delegate = self
    }

    // MARK: Settings

    // Default must match @AppStorage in SpeechRecognitionSettingsView (true).
    private var enableVoiceCommands: Bool {
        UserDefaults.standard.object(forKey: "enableVoiceCommands") as? Bool ?? true
    }

    private var commandPrefix: String {
        UserDefaults.standard.string(forKey: "commandPrefix") ?? "vox"
    }

    private var config: VoiceCommandConfig { VoiceCommandStore.shared.config }

    /// Settings can change between segments.
    private func refreshRouter() {
        router.wakeWord = commandPrefix
        router.aliases = SpeechSettings.commandAliases
        router.isEnabled = enableVoiceCommands
    }

    // MARK: - SpeechServiceDelegate

    func speechServiceWillStart(_ service: SpeechService) {
        // Apps opened since launch join `<app>`, whose names help "vox gemini" come out as "Gemini".
        VoiceCommandStore.shared.addWindowedApps()
    }

    func speechService(_ service: SpeechService, didRecognize text: String, isFinal: Bool) {
        restartSilenceTimer()
        refreshRouter()
        guard isFinal else {
            streamVolatile(text)
            return
        }
        log.debug("Final segment: \(text, privacy: .public)")
        for action in router.route(text, isTyping: isTypingIntoApp, config: config) {
            execute(action)
        }
    }

    func speechService(_ service: SpeechService, notice: String) {
        showFeedback(notice)
    }

    func speechServiceDidStop(_ service: SpeechService) {
        isTypingIntoApp = false
        hasTypedSegment = false
        liveTypedText = ""
        dictatedSinceSilence = false
        router.reset()
        silenceTask?.cancel()
        silenceTask = nil
        switchTask?.cancel()
        switchTask = nil
        launchTask?.cancel()
        launchTask = nil
        // A command waiting for confirmation survives the end of recording: its notification
        // buttons still work without the microphone.
        feedbackTask?.cancel()
        feedback = nil

        // Default must match @AppStorage in GeneralSettingsView (true).
        let autoCopy = UserDefaults.standard.object(forKey: "autoCopyToClipboard") as? Bool ?? true
        if autoCopy && !transcript.isEmpty {
            copyToClipboard()
        }
    }

    // MARK: - Actions

    func execute(_ action: VoiceAction) {
        switch action {
        case .dictate(let text):
            dictate(text)
        case .command(let command):
            discardLiveText()
            perform(command)
        case .template(let request):
            discardLiveText()
            prepareTemplate(request)
        case .focusAndDictate(let text):
            discardLiveText()
            startTypingIntoApp()
            dictate(text)
        case .awaitCommand:
            discardLiveText()
            showFeedback("\(commandPrefix)…", for: VoiceCommandRouter.awaitCommandTimeout)
        case .unknownCommand(let text):
            discardLiveText()
            log.info("Unknown command: \(text, privacy: .public)")
            showFeedback("Comando não reconhecido: \(text)")
        }
        if case .dictate = action { return }
        dictatedSinceSilence = false
    }

    func perform(_ command: BuiltInCommand) {
        switch command {
        case .focus:
            // "vox" sozinho: pula para a área de texto principal do app em foco
            startTypingIntoApp()
        case .copy:
            copyToClipboard()
        case .clear:
            transcript = ""
        case .stop:
            Task { await speech?.stop(reason: "comando de voz") }
        case .newParagraph:
            transcript += "\n\n"
        case .deleteLastSentence:
            removeLastSentence()
        case .send:
            TextTyper.pressReturn()
            hasTypedSegment = false
            if !transcript.isEmpty && !transcript.hasSuffix("\n") { transcript += "\n" }
            showFeedback("Enviado")
        case .next:
            // Also enters typing mode, like "vox" alone.
            handleFocusResult(TextAreaNavigator.focusNextTextArea())
        case .confirm:
            confirmPendingLaunch()
        case .cancel:
            guard pendingLaunch != nil || launchTask != nil else { return }
            launchTask?.cancel()
            launchTask = nil
            clearPendingLaunch()
            showFeedback("Cancelado")
        }
    }

    // MARK: - Dictation

    /// Adds finalized speech to the transcript and, in typing mode, types it into the focused app.
    private func dictate(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if isTypingIntoApp {
            // Corrects the streamed volatile text into the final one (dropping a trailing "enviar").
            replaceLiveText(with: trimmed.isEmpty ? "" : (hasTypedSegment ? " " + trimmed : trimmed))
            if !trimmed.isEmpty { hasTypedSegment = true }
        }
        liveTypedText = ""
        if !trimmed.isEmpty { dictatedSinceSilence = true }
        transcript += text
    }

    /// Types the phrase being recognized into the app while it's still volatile.
    private func streamVolatile(_ text: String) {
        guard isTypingIntoApp else { return }
        let trimmed = router.liveDictation(text).trimmingCharacters(in: .whitespacesAndNewlines)
        replaceLiveText(with: trimmed.isEmpty ? "" : (hasTypedSegment ? " " + trimmed : trimmed))
    }

    /// Edits the live text in the app into `text`, erasing only what changed after the common prefix.
    private func replaceLiveText(with text: String) {
        guard text != liveTypedText else { return }
        // Counted in Characters: one Delete erases one visible character.
        let common = zip(liveTypedText, text).prefix { $0 == $1 }.count
        TextTyper.deleteBackward(liveTypedText.count - common)
        TextTyper.type(String(text.dropFirst(common)))
        liveTypedText = text
    }

    /// Erases the live text before a command runs; commands never stay typed.
    private func discardLiveText() {
        replaceLiveText(with: "")
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

    // MARK: - Templates

    /// "vox abre o claude no cognia e pede pra Liet resolver o HGR-217": the aliases or the
    /// model pick a template and its values, then `run` carries it out.
    private func prepareTemplate(_ request: String) {
        log.info("Template request: \(request, privacy: .public)")
        launchTask?.cancel()
        clearPendingLaunch()
        let config = config
        let transcript = request.trimmingCharacters(in: .whitespacesAndNewlines)
        showFeedback("Entendendo o pedido…", for: nil)
        launchTask = Task {
            // A cancelled task was already replaced or cleared; don't clear its successor.
            defer { if !Task.isCancelled { launchTask = nil } }
            do {
                let resolution: CommandResolver.Resolution
                if let match = CommandResolver.resolveWithAliases(transcript, config: config) {
                    resolution = match
                } else {
                    resolution = try await CommandResolver.resolveWithModel(transcript, config: config)
                }
                try Task.checkCancellation()
                let prepared = PreparedCommand(template: resolution.template, values: resolution.values,
                                               transcript: transcript, entities: config.entities)
                log.info("Template command: \(prepared.command, privacy: .public)")
                if prepared.template.target.asksConfirmation {
                    await askConfirmation(for: prepared)
                } else {
                    feedback = nil
                    await run(prepared)
                }
            } catch is CancellationError {
                return
            } catch {
                log.error("Template request failed: \(error.localizedDescription, privacy: .public)")
                showFeedback(error.localizedDescription)
            }
        }
    }

    /// Carries out a prepared template on its target. Shell targets only get here once confirmed.
    private func run(_ prepared: PreparedCommand) async {
        switch prepared.template.target {
        case .tmuxWindow:
            report(await TmuxNavigator.openWindow(named: prepared.title, running: prepared.command),
                   success: "\(prepared.title) aberto")
        case .background:
            report(await TmuxNavigator.runInBackground(prepared.command), success: "Rodando em segundo plano")
        case .tmuxPane:
            await focusTmuxPane(running: TmuxNavigator.Program(displayName: prepared.title, command: prepared.command))
        case .appWindow:
            await focusApp(bundleID: prepared.command, named: prepared.title)
        case .keys:
            await press(prepared.command)
        }
    }

    private func report(_ result: Result<Void, TmuxNavigator.Failure>, success: String) {
        switch result {
        case .success:
            showFeedback(success)
        case .failure(let failure):
            log.info("Command failed: \(failure.message, privacy: .public)")
            showFeedback(failure.message)
        }
    }

    // MARK: - Confirmation

    private func askConfirmation(for prepared: PreparedCommand) async {
        let id = UUID()
        pendingLaunch = prepared
        pendingLaunchID = id
        // The notification has Executar / Cancelar; the voice answer stays as an alternative.
        let notified = await CommandConfirmation.shared.ask(prepared, id: id)
        guard pendingLaunchID == id else { return }
        let answer = "\(commandPrefix) sim / \(commandPrefix) não"
        showFeedback(notified ? "\(prepared.confirmation) (confirme na notificação ou \(answer))"
                              : "\(prepared.confirmation) (\(answer))", for: nil)
    }

    private func confirmPendingLaunch() {
        guard let launch = pendingLaunch else {
            showFeedback(launchTask == nil ? "Nada para confirmar" : "Ainda entendendo o pedido…")
            return
        }
        clearPendingLaunch()
        Task { await run(launch) }
    }

    /// Executar / Cancelar on the confirmation notification.
    func answerConfirmation(_ id: UUID, _ decision: CommandConfirmation.Decision) {
        guard id == pendingLaunchID else {
            CommandConfirmation.shared.dismiss(id)
            return
        }
        switch decision {
        case .accept: confirmPendingLaunch()
        case .deny: perform(.cancel)
        }
    }

    /// Forgets the waiting command and takes its notification down.
    private func clearPendingLaunch() {
        if let pendingLaunchID { CommandConfirmation.shared.dismiss(pendingLaunchID) }
        pendingLaunch = nil
        pendingLaunchID = nil
    }

    // MARK: - Keys

    /// "cmd+a delete", "option+delete*3" in the focused app.
    private func press(_ keys: String) async {
        guard let sequence = KeySequence(keys) else {
            log.info("Invalid keys: \(keys, privacy: .public)")
            showFeedback("Tecla inválida: \(keys)")
            return
        }
        await sequence.press()
        if sequence.endsSegment { hasTypedSegment = false }
    }

    // MARK: - Focus

    /// Jumps to the tmux pane running `program` in Ghostty; the terminal takes keystrokes
    /// directly, so no AX text-area lookup is needed before typing.
    private func focusTmuxPane(running program: TmuxNavigator.Program) async {
        switch await TmuxNavigator.focus(program) {
        case .success:
            log.info("Focused \(program.displayName, privacy: .public)")
            showFeedback("Digitando no \(program.displayName)")
            isTypingIntoApp = true
            hasTypedSegment = false
        case .failure(let failure):
            log.info("\(program.displayName, privacy: .public) focus failed: \(failure.message, privacy: .public)")
            showFeedback(failure.message)
        }
    }

    /// The `<app>` template: the app with `bundleID`, opened first if it isn't running.
    private func focusApp(bundleID: String, named name: String) async {
        guard let app = await AppSwitcher.app(bundleID: bundleID) else {
            log.info("App not found: \(bundleID, privacy: .public)")
            showFeedback("\(name) não está instalado")
            return
        }
        switchTo(app)
    }

    /// Brings the app's window forward, switching Spaces if it lives elsewhere, then types into it.
    private func switchTo(_ app: NSRunningApplication) {
        let name = app.localizedName ?? "app"
        log.info("Switching to \(name, privacy: .public)")
        guard TextAreaNavigator.isTrusted else {
            showFeedback(TextAreaNavigator.FocusResult.notTrusted.message)
            return
        }
        // Nothing is typed until the new app is in front, or it would land in the old one.
        isTypingIntoApp = false
        AppSwitcher.bringToFront(app)
        showFeedback("Indo para \(name)")
        switchTask?.cancel()
        switchTask = Task {
            // Activation (and a Space switch) takes a moment. Asked again halfway, since macOS
            // can ignore the first request while Vox isn't active; gives up after ~3 s.
            var waited = 0
            while !AppSwitcher.isFrontmost(app), waited < 30 {
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
                waited += 1
                if waited == 10 { AppSwitcher.bringToFront(app) }
            }
            guard AppSwitcher.isFrontmost(app) else {
                log.info("\(name, privacy: .public) didn't come to the front")
                showFeedback("\(name) não veio para a frente")
                switchTask = nil
                return
            }
            let result = TextAreaNavigator.focusMainTextArea(in: app)
            log.info("Focus after switch: \(result.message, privacy: .public)")
            // Many apps (Gemini, chats) already put the cursor in their input when activated,
            // so speech is typed even when no text area could be focused through Accessibility.
            showFeedback(result.succeeded ? result.message : "Digitando em \(name)")
            isTypingIntoApp = true
            hasTypedSegment = false
            switchTask = nil
        }
    }

    private func startTypingIntoApp() {
        handleFocusResult(TextAreaNavigator.focusMainTextArea())
    }

    private func handleFocusResult(_ result: TextAreaNavigator.FocusResult) {
        log.info("Focus result: \(result.message, privacy: .public)")
        showFeedback(result.message)
        guard result.succeeded else { return }
        isTypingIntoApp = true
        hasTypedSegment = false
    }

    // MARK: - Silence

    private func restartSilenceTimer() {
        silenceTask?.cancel()
        guard SpeechSettings.silenceAction != .none else { return }
        let seconds = SpeechSettings.silenceSeconds
        silenceTask = Task {
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            silenceTask = nil
            runSilenceAction()
        }
    }

    private func runSilenceAction() {
        guard speech?.isRecording == true, dictatedSinceSilence else { return }
        let action = SpeechSettings.silenceAction
        let value = SpeechSettings.silenceActionValue
        guard action != .none, !value.isEmpty else { return }
        log.info("Silence action \(action.rawValue, privacy: .public): \(value, privacy: .public)")
        // Nothing half-recognized stays typed when the action sends or switches.
        discardLiveText()
        dictatedSinceSilence = false
        switch action {
        case .none:
            return
        case .keys:
            Task { await press(value) }
        case .voxCommand:
            refreshRouter()
            execute(router.routeCommand(value, isTyping: isTypingIntoApp, allowsDictation: false, config: config))
        case .shell:
            Task { report(await TmuxNavigator.runInBackground(value), success: "Comando de silêncio rodando") }
        }
    }

    // MARK: - Feedback

    /// A nil `duration` keeps the message until the next one (questions waiting for an answer).
    private func showFeedback(_ message: String, for duration: Duration? = .seconds(3)) {
        feedback = message
        feedbackTask?.cancel()
        guard let duration else { return }
        feedbackTask = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            feedback = nil
        }
    }
}
