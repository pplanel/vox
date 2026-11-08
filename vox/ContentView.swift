//
//  ContentView.swift
//  vox
//
//  Created by Pedro Planel on 01/11/26.
//
//  NOTA: Este arquivo não é usado no projeto.
//  O app funciona apenas com o ícone na status bar e a janela de Settings.
//

import SwiftUI

// Este ContentView não é usado no aplicativo final
// Mantido apenas para referência ou desenvolvimento futuro
struct ContentView_NotUsed: View {
    @EnvironmentObject private var speech: SpeechService
    @EnvironmentObject private var executor: CommandExecutor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $executor.transcript)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            if !speech.volatileText.isEmpty {
                Text(speech.volatileText)
                    .foregroundStyle(.secondary)
                    .italic()
                    .lineLimit(2)
            }

            HStack {
                statusView
                Spacer()
                Button("Limpar") {
                    executor.transcript = ""
                }
                .disabled(executor.transcript.isEmpty)

                Button {
                    Task { await speech.toggle() }
                } label: {
                    Label(
                        speech.isRecording ? "Parar" : "Gravar",
                        systemImage: speech.isRecording ? "stop.circle.fill" : "mic.circle.fill"
                    )
                    .frame(minWidth: 80)
                }
                .buttonStyle(.borderedProminent)
                .tint(speech.isRecording ? .red : .accentColor)
                .disabled(speech.status == .preparing || speech.status == .downloadingModel)
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 360)
    }

    @ViewBuilder
    private var statusView: some View {
        switch speech.status {
        case .idle:
            Text("Pronto")
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
                Text("Baixando modelo de transcrição…")
            }
            .foregroundStyle(.secondary)
        case .recording:
            HStack(spacing: 6) {
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative)
                Text("Gravando…")
            }
            .foregroundStyle(.red)
        case .error(let message):
            Text(message)
                .foregroundStyle(.red)
                .lineLimit(2)
        }
    }
}

#Preview {
    let speech = SpeechService()
    ContentView_NotUsed()
        .environmentObject(speech)
        .environmentObject(CommandExecutor(speech: speech))
}
