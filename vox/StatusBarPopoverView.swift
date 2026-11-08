//
//  StatusBarPopoverView.swift
//  vox
//
//  Created by Pedro Planel on 02/11/26.
//

import SwiftUI

struct StatusBarPopoverView: View {
    @EnvironmentObject var speechService: SpeechService
    @EnvironmentObject var executor: CommandExecutor
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 16) {
            // Status atual
            HStack {
                statusIndicator
                Spacer()
            }
            
            Divider()
            
            // Botão de gravar
            Button {
                Task {
                    await speechService.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: speechService.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    Text(speechService.isRecording ? "Parar Gravação" : "Iniciar Gravação")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(speechService.isRecording ? .red : .accentColor)
            .disabled(speechService.status == .preparing || speechService.status == .downloadingModel)
            .keyboardShortcut(speechService.isRecording ? "s" : "r", modifiers: [.command])
            
            // Botão de limpar transcrição
            if !executor.transcript.isEmpty {
                Button("Limpar Transcrição") {
                    executor.transcript = ""
                }
                .buttonStyle(.bordered)
            }
            
            Divider()
            
            // Botões de ação
            HStack {
                Button("Ajustes…") {
                    // App de barra de menus: ativar para a janela de Ajustes vir para frente
                    NSApp.activate()
                    openSettings()
                }
                .buttonStyle(.link)
                
                Spacer()
                
                Button("Sair") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.link)
            }
        }
        .padding()
        .frame(width: 280)
    }
    
    @ViewBuilder
    private var statusIndicator: some View {
        switch speechService.status {
        case .idle:
            Label("Pronto", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        case .preparing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Preparando…")
            }
            .foregroundStyle(.secondary)
        case .downloadingModel:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Baixando modelo…")
            }
            .foregroundStyle(.secondary)
        case .recording:
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative)
                Text("Gravando")
            }
            .foregroundStyle(.red)
        case .error(let message):
            VStack(alignment: .leading, spacing: 4) {
                Label("Erro", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    let speech = SpeechService()
    StatusBarPopoverView()
        .environmentObject(speech)
        .environmentObject(CommandExecutor(speech: speech))
}
