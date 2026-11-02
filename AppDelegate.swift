//
//  AppDelegate.swift
//  vox
//
//  Created by Pedro Planel on 02/11/26.
//

import AppKit
import SwiftUI
import AVFoundation
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var transcriptionWindow: NSWindow?
    @Published var speechService = SpeechService()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Registrar valores padrão
        registerDefaultSettings()
        
        // Esconder o ícone do Dock
        NSApp.setActivationPolicy(.accessory)
        
        // Criar o item na status bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            updateStatusBarIcon()
            button.action = #selector(togglePopover)
            button.target = self
        }
        
        // Observar mudanças no status de gravação
        Task {
            for await _ in NotificationCenter.default.notifications(named: .speechServiceStatusChanged) {
                updateStatusBarIcon()
                handleRecordingStatusChange()
            }
        }
        
        // Solicitar permissão do microfone no início
        requestMicrophonePermission()
    }
    
    @objc func togglePopover() {
        if let popover = popover, popover.isShown {
            popover.close()
        } else {
            showPopover()
        }
    }
    
    private func showPopover() {
        guard let button = statusItem?.button else { return }
        
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 200)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: StatusBarPopoverView()
                .environmentObject(speechService)
        )
        
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.popover = popover
    }
    
    private func updateStatusBarIcon() {
        guard let button = statusItem?.button else { return }
        
        let iconName: String
        let tintColor: NSColor
        
        switch speechService.status {
        case .recording:
            iconName = "mic.fill"
            tintColor = .systemRed
        case .preparing, .downloadingModel:
            iconName = "mic"
            tintColor = .systemYellow
        case .error:
            iconName = "mic.slash"
            tintColor = .systemRed
        case .idle:
            iconName = "mic"
            tintColor = .controlTextColor
        }
        
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            button.image = image
            button.contentTintColor = tintColor
        }
    }
    
    private func requestMicrophonePermission() {
        Task {
            // Solicitar permissão explicitamente
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
            
            if !granted {
                // Mostrar alerta se negado
                await MainActor.run {
                    let alert = NSAlert()
                    alert.messageText = "Permissão de Microfone Necessária"
                    alert.informativeText = "O Vox precisa de acesso ao microfone para funcionar. Por favor, ative em:\n\nAjustes do Sistema → Privacidade e Segurança → Microfone"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Abrir Ajustes do Sistema")
                    alert.addButton(withTitle: "Cancelar")
                    
                    if alert.runModal() == .alertFirstButtonReturn {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        }
    }
    
    private func handleRecordingStatusChange() {
        let showDockModal = UserDefaults.standard.bool(forKey: "showDockModal")
        
        if speechService.isRecording && showDockModal {
            showTranscriptionModal()
        } else if !speechService.isRecording {
            closeTranscriptionModal()
        }
    }
    
    private func showTranscriptionModal() {
        guard transcriptionWindow == nil else { return }
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "Vox - Transcrição"
        window.center()
        window.contentView = NSHostingView(
            rootView: TranscriptionModalView()
                .environmentObject(speechService)
        )
        
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        transcriptionWindow = window
    }
    
    private func closeTranscriptionModal() {
        transcriptionWindow?.close()
        transcriptionWindow = nil
    }
    
    private func registerDefaultSettings() {
        UserDefaults.standard.register(defaults: [
            "autoStartRecording": false,
            "autoCopyToClipboard": true,
            "showDockModal": true,
            "enableVoiceCommands": true,
            "commandPrefix": "vox"
        ])
    }
}

extension Notification.Name {
    static let speechServiceStatusChanged = Notification.Name("speechServiceStatusChanged")
}
