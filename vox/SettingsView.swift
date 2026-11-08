//
//  SettingsView.swift
//  vox
//
//  Created by Pedro Planel on 02/11/26.
//

import SwiftUI
import AVFoundation
import Speech

struct SettingsView: View {
    @EnvironmentObject var speechService: SpeechService

    var body: some View {
        TabView {
            Tab("Geral", systemImage: "gearshape") {
                GeneralSettingsView()
            }

            Tab("Reconhecimento", systemImage: "waveform") {
                SpeechRecognitionSettingsView()
            }

            Tab("Comandos de voz", systemImage: "terminal") {
                VoiceTemplatesSettingsView()
            }

            Tab("Sobre", systemImage: "info.circle") {
                AboutSettingsView()
            }
        }
        .frame(width: 760, height: 600)
    }
}

// MARK: - Geral

struct GeneralSettingsView: View {
    @AppStorage("autoStartRecording") private var autoStartRecording = false
    @AppStorage("autoCopyToClipboard") private var autoCopyToClipboard = true
    @AppStorage("showDockModal") private var showDockModal = false
    @AppStorage("showIsland") private var showIsland = false
    @AppStorage(SpeechSettings.silenceActionKey) private var silenceAction = SpeechSettings.SilenceAction.none
    @AppStorage(SpeechSettings.silenceActionValueKey) private var silenceActionValue = ""
    @AppStorage(SpeechSettings.silenceSecondsKey) private var silenceSeconds = SpeechSettings.defaultSilenceSeconds

    var body: some View {
        Form {
            Section("Gravação") {
                Toggle("Iniciar gravação ao abrir", isOn: $autoStartRecording)

                Toggle(isOn: $autoCopyToClipboard) {
                    Text("Copiar para o clipboard ao parar")
                    Text("O texto transcrito é copiado automaticamente quando a gravação termina.")
                }

                Toggle(isOn: $showIsland) {
                    Text("Mostrar ilha")
                    Text("Mostra junto ao notch se está ouvindo ou digitando, e os avisos dos comandos.")
                }

                Toggle(isOn: $showDockModal) {
                    Text("Mostrar janela de transcrição (debug)")
                    Text("Exibe o texto sendo transcrito em tempo real durante a gravação.")
                }

                LabeledContent("Atalho global") {
                    Text(GlobalHotKey.displayString)
                        .font(.body.monospaced())
                }
            }

            Section {
                Picker("Ao ficar em silêncio", selection: $silenceAction) {
                    ForEach(SpeechSettings.SilenceAction.allCases, id: \.self) { action in
                        Text(action.displayName).tag(action)
                    }
                }

                if silenceAction != .none {
                    TextField(silenceValueLabel, text: $silenceActionValue, prompt: Text(silenceValuePrompt))
                        .font(.body.monospaced())
                    if silenceAction == .keys, !silenceActionValue.isEmpty, KeySequence(silenceActionValue) == nil {
                        Label("Tecla desconhecida; use por exemplo \(KeySequence.examples)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                    Stepper(value: $silenceSeconds, in: 1...60, step: 1) {
                        LabeledContent("Depois de", value: "\(Int(silenceSeconds)) s")
                    }
                }
            } header: {
                Text("Silêncio")
            } footer: {
                Text("Age uma vez depois que você para de falar, só se algo foi ditado desde o último comando. Por exemplo, a tecla return envia a mensagem.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Privacidade") {
                MicrophonePermissionRow()
                AccessibilityPermissionRow()
            }
        }
        .formStyle(.grouped)
    }
}

extension GeneralSettingsView {
    private var silenceValueLabel: String {
        switch silenceAction {
        case .none: ""
        case .keys: "Tecla"
        case .voxCommand: "Comando (sem “vox”)"
        case .shell: "Comando de shell"
        }
    }

    private var silenceValuePrompt: String {
        switch silenceAction {
        case .none: ""
        case .keys: "return"
        case .voxCommand: "enviar"
        case .shell: "say pronto"
        }
    }
}

/// Shows the current microphone authorization and a shortcut to System Settings.
struct MicrophonePermissionRow: View {
    @State private var status = AVCaptureDevice.authorizationStatus(for: .audio)

    var body: some View {
        LabeledContent {
            Button("Abrir Ajustes…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            }
        } label: {
            Text("Microfone")
            Label(statusText, systemImage: statusIcon)
                .foregroundStyle(statusColor)
        }
        // Refresh when the user comes back from System Settings.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            status = AVCaptureDevice.authorizationStatus(for: .audio)
        }
    }

    private var statusText: String {
        switch status {
        case .authorized: "Acesso permitido"
        case .denied, .restricted: "Acesso negado"
        case .notDetermined: "Ainda não solicitado"
        @unknown default: "Desconhecido"
        }
    }

    private var statusIcon: String {
        switch status {
        case .authorized: "checkmark.circle.fill"
        case .denied, .restricted: "xmark.circle.fill"
        default: "questionmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch status {
        case .authorized: .green
        case .denied, .restricted: .red
        default: .secondary
        }
    }
}

/// Accessibility is needed for the "vox" command to focus text areas in other apps.
struct AccessibilityPermissionRow: View {
    @State private var isTrusted = TextAreaNavigator.isTrusted

    var body: some View {
        LabeledContent {
            Button("Abrir Ajustes…") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                    NSWorkspace.shared.open(url)
                }
            }
        } label: {
            Text("Acessibilidade")
            Label(isTrusted ? "Acesso permitido" : "Acesso negado",
                  systemImage: isTrusted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(isTrusted ? .green : .red)
        }
        // Refresh when the user comes back from System Settings.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isTrusted = TextAreaNavigator.isTrusted
        }
    }
}

// MARK: - Reconhecimento (Apple Speech)

struct SpeechRecognitionSettingsView: View {
    @AppStorage(SpeechSettings.localeKey) private var localeIdentifier = ""
    @AppStorage(SpeechSettings.volatileResultsKey) private var volatileResults = true
    @AppStorage(SpeechSettings.fastResultsKey) private var fastResults = true
    @AppStorage(SpeechSettings.etiquetteReplacementsKey) private var etiquetteReplacements = false
    @AppStorage(SpeechSettings.customVocabularyKey) private var customVocabulary = false
    @AppStorage("enableVoiceCommands") private var enableVoiceCommands = true
    @AppStorage("commandPrefix") private var commandPrefix = "vox"
    @AppStorage(SpeechSettings.commandAliasesKey) private var commandAliases = SpeechSettings.defaultCommandAliases

    @State private var supportedLocales: [Locale] = []
    @State private var installedLocales: [Locale] = []
    @State private var isLoading = true

    var body: some View {
        Form {
            Section {
                Picker("Idioma", selection: $localeIdentifier) {
                    Text("Automático (\(displayName(for: .current)))").tag("")
                    if !supportedLocales.isEmpty {
                        Divider()
                    }
                    ForEach(supportedLocales, id: \.identifier) { locale in
                        Text(displayName(for: locale)).tag(locale.identifier)
                    }
                }
                .disabled(isLoading)

                LabeledContent("Modelo") {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else if isSelectedModelInstalled {
                        Label("Instalado", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Será baixado na próxima gravação", systemImage: "arrow.down.circle")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Idioma")
            } footer: {
                Text("A transcrição usa os modelos da Apple e roda inteiramente no dispositivo.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: $volatileResults) {
                    Text("Resultados parciais")
                    Text("Mostra o texto enquanto você fala, antes de a frase ser finalizada.")
                }

                Toggle(isOn: $fastResults) {
                    Text("Priorizar velocidade")
                    Text("Reduz a latência usando menos contexto, com alguma perda de precisão.")
                }

                Toggle(isOn: $etiquetteReplacements) {
                    Text("Ocultar palavrões")
                    Text("Substitui expressões ofensivas por asteriscos.")
                }

                Toggle(isOn: $customVocabulary) {
                    Text("Vocabulário personalizado")
                    Text("Ensina ao modelo a palavra de ativação, os comandos e as pronúncias (“soa como”) definidas em Comandos de voz. Usa o modelo de ditado da Apple.")
                }
            } header: {
                Text("Transcrição")
            } footer: {
                Text("As alterações valem a partir da próxima gravação.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Ativar comandos de voz", isOn: $enableVoiceCommands)

                TextField("Palavra de ativação", text: $commandPrefix, prompt: Text("vox"))
                    .disabled(!enableVoiceCommands)

                TextField("Variações aceitas", text: $commandAliases, prompt: Text(SpeechSettings.defaultCommandAliases))
                    .disabled(!enableVoiceCommands)
            } header: {
                Text("Palavra de ativação")
            } footer: {
                Text("Diga “\(displayPrefix) [comando]” durante a gravação, inclusive no meio de uma frase: o que vem depois não é digitado. Os comandos ficam na entidade <comando> em Comandos de voz, junto com os templates. As variações, separadas por vírgula, cobrem como outros idiomas transcrevem a palavra de ativação; valem sozinhas ou antes de um comando.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            await loadLocales()
        }
    }

    private var displayPrefix: String {
        let trimmed = commandPrefix.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "vox" : trimmed
    }

    private var isSelectedModelInstalled: Bool {
        let selected = localeIdentifier.isEmpty ? Locale.current : Locale(identifier: localeIdentifier)
        // Compare by language + region: identifiers may differ in format (pt_BR vs pt-BR).
        return installedLocales.contains {
            $0.language.languageCode == selected.language.languageCode && $0.region == selected.region
        }
    }

    private func loadLocales() async {
        let supported = await SpeechTranscriber.supportedLocales
        let installed = await SpeechTranscriber.installedLocales
        supportedLocales = supported.sorted { displayName(for: $0) < displayName(for: $1) }
        installedLocales = installed
        isLoading = false
    }

    private func displayName(for locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }
}

// MARK: - Sobre

struct AboutSettingsView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "Versão \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "mic.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .padding(.bottom, 4)

            Text("Vox")
                .font(.title.bold())

            Text("Transcrição de voz minimalista, 100% no dispositivo.")
                .foregroundStyle(.secondary)

            Text(version)
                .font(.caption)
                .foregroundStyle(.tertiary)

            Text("© 2026 Pedro Planel")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 12)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

#Preview {
    let speech = SpeechService()
    SettingsView()
        .environmentObject(speech)
        .environmentObject(CommandExecutor(speech: speech))
}
