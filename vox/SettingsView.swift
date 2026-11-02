//
//  SettingsView.swift
//  vox
//
//  Created by Pedro Planel on 02/11/26.
//

import SwiftUI
import AVFoundation

struct SettingsView: View {
    @EnvironmentObject var speechService: SpeechService

    var body: some View {
        TabView {
            Tab("Geral", systemImage: "gearshape") {
                GeneralSettingsView()
            }

            Tab("Comandos", systemImage: "waveform.badge.mic") {
                VoiceCommandsSettingsView()
            }

            Tab("Sobre", systemImage: "info.circle") {
                AboutSettingsView()
            }
        }
        .frame(width: 480, height: 420)
    }
}

// MARK: - Geral

struct GeneralSettingsView: View {
    @AppStorage("autoStartRecording") private var autoStartRecording = false
    @AppStorage("autoCopyToClipboard") private var autoCopyToClipboard = true
    @AppStorage("showDockModal") private var showDockModal = true

    var body: some View {
        Form {
            Section("Gravação") {
                Toggle("Iniciar gravação ao abrir", isOn: $autoStartRecording)

                Toggle(isOn: $autoCopyToClipboard) {
                    Text("Copiar para o clipboard ao parar")
                    Text("O texto transcrito é copiado automaticamente quando a gravação termina.")
                }

                Toggle(isOn: $showDockModal) {
                    Text("Mostrar janela de transcrição")
                    Text("Exibe o texto sendo transcrito em tempo real durante a gravação.")
                }
            }

            Section("Privacidade") {
                MicrophonePermissionRow()
            }
        }
        .formStyle(.grouped)
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

// MARK: - Comandos de voz

struct VoiceCommandsSettingsView: View {
    @AppStorage("enableVoiceCommands") private var enableVoiceCommands = true
    @AppStorage("commandPrefix") private var commandPrefix = "vox"

    /// Mirrors the commands handled in `SpeechService.processVoiceCommand`.
    private let commands: [(phrase: String, description: String)] = [
        ("copiar", "Copia o texto para o clipboard"),
        ("limpar", "Limpa a transcrição atual"),
        ("parar", "Para a gravação"),
        ("novo parágrafo", "Adiciona uma quebra de parágrafo"),
        ("apagar última frase", "Remove a última frase"),
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Ativar comandos de voz", isOn: $enableVoiceCommands)

                TextField("Palavra de ativação", text: $commandPrefix, prompt: Text("vox"))
                    .disabled(!enableVoiceCommands)
            } footer: {
                Text("Diga “\(displayPrefix) [comando]” durante a gravação para executar uma ação.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Comandos disponíveis") {
                ForEach(commands, id: \.phrase) { command in
                    LabeledContent {
                        Text(command.description)
                            .foregroundStyle(.secondary)
                    } label: {
                        Text("\(displayPrefix) \(command.phrase)")
                            .font(.body.monospaced())
                    }
                }
            }
            .disabled(!enableVoiceCommands)
        }
        .formStyle(.grouped)
    }

    private var displayPrefix: String {
        let trimmed = commandPrefix.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "vox" : trimmed
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
    SettingsView()
        .environmentObject(SpeechService())
}
