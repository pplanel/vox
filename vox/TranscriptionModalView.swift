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
                        if !speechService.transcript.isEmpty {
                            Text(speechService.transcript)
                                .textSelection(.enabled)
                                .foregroundStyle(.primary)
                        }
                        
                        // Texto volátil (sendo transcrito)
                        if !speechService.volatileText.isEmpty {
                            Text(speechService.volatileText)
                                .foregroundStyle(.secondary)
                                .italic()
                                .id("volatile")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .onChange(of: speechService.volatileText) { _, _ in
                    withAnimation {
                        proxy.scrollTo("volatile", anchor: .bottom)
                    }
                }
                .onChange(of: speechService.transcript) { _, _ in
                    withAnimation {
                        proxy.scrollTo("volatile", anchor: .bottom)
                    }
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
                .disabled(speechService.transcript.isEmpty)
                
                Spacer()
                
                Button("Limpar") {
                    speechService.transcript = ""
                }
                .disabled(speechService.transcript.isEmpty)
                
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
        pasteboard.setString(speechService.transcript, forType: .string)
    }
}

#Preview {
    TranscriptionModalView()
        .environmentObject(SpeechService())
}
