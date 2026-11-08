//
//  TranscriptionModalView.swift
//  vox
//
//  Created by Pedro Planel on 02/11/26.
//

import SwiftUI

/// Modal que aparece no Dock mostrando a transcrição em tempo real
struct TranscriptionModalView: View {
    @EnvironmentObject var speechService: SpeechService
    @EnvironmentObject var executor: CommandExecutor
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative)
                        .foregroundStyle(.red)
                    Text("Gravando")
                        .font(.headline)
                }
                
                Spacer()
                
                Button {
                    Task {
                        await speechService.stop()
                        dismiss()
                    }
                } label: {
                    Image(systemName: "stop.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .font(.title2)
            }
            
            Divider()
            
            // Área de transcrição
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        // Texto finalizado
                        if !executor.transcript.isEmpty {
                            Text(executor.transcript)
                                .textSelection(.enabled)
                                .foregroundStyle(.primary)
                        }
                        
                        // Texto volátil (sendo transcrito)
                        if !speechService.volatileText.isEmpty {
                            Text(speechService.volatileText)
                                .foregroundStyle(.secondary)
                                .italic()
                        }

                        // Âncora estável para rolagem automática
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                // Um único observador: transcript e volatileText mudam no mesmo frame
                .onChange(of: executor.transcript + speechService.volatileText) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            
            // Footer com ações
            HStack {
                Button {
                    copyToClipboard()
                } label: {
                    Label("Copiar", systemImage: "doc.on.doc")
                }
                .disabled(executor.transcript.isEmpty)
                
                Spacer()
                
                Button("Limpar") {
                    executor.transcript = ""
                }
                .disabled(executor.transcript.isEmpty)
                
                Button {
                    Task {
                        await speechService.stop()
                        dismiss()
                    }
                } label: {
                    Label("Parar", systemImage: "stop.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
        .padding()
        .frame(width: 500, height: 400)
    }
    
    private func copyToClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(executor.transcript, forType: .string)
    }
}

#Preview {
    let speech = SpeechService()
    TranscriptionModalView()
        .environmentObject(speech)
        .environmentObject(CommandExecutor(speech: speech))
}
