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
import Carbon.HIToolbox

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, ObservableObject {
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var transcriptionWindow: NSWindow?
    private var islandHideTask: Task<Void, Never>?
    private var hotKey: GlobalHotKey?
    private lazy var island = TranscriptionIslandController(speechService: speechService, executor: executor)
    let speechService: SpeechService
    /// Everything said is carried out here; `speechService` only recognizes.
    let executor: CommandExecutor

    override init() {
        let speechService = SpeechService()
        self.speechService = speechService
        executor = CommandExecutor(speech: speechService)
        super.init()
    }
    
    /// Before launch finishes, so a click on a confirmation notification that launched or
    /// reactivated the app is still delivered.
    func applicationWillFinishLaunching(_ notification: Notification) {
        CommandConfirmation.shared.register()
        CommandConfirmation.shared.onDecision = { [weak self] id, decision in
            self?.executor.answerConfirmation(id, decision)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Registrar valores padrão
        registerDefaultSettings()
        
        // Esconder o ícone do Dock
        NSApp.setActivationPolicy(.accessory)
        
        // Criar o item na status bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        updateStatusBarIcon()

        // Menu nativo (estilo 1Password); reconstruído a cada abertura em `menuNeedsUpdate`
        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
        
        // Observar mudanças no status de gravação
        Task {
            for await _ in NotificationCenter.default.notifications(named: .speechServiceStatusChanged) {
                updateStatusBarIcon()
                handleRecordingStatusChange()
            }
        }
        
        registerHotKey()
        TextAreaNavigator.startTrackingFrontmostApp()
        // Apps with open windows become `<app>` values for "vox <app>".
        VoiceCommandStore.shared.addWindowedApps()

        // Solicitar permissão do microfone no início
        requestMicrophonePermission()

        // Necessária para o comando "vox" focar a área de texto do app em uso
        if !TextAreaNavigator.isTrusted {
            TextAreaNavigator.requestTrust()
        }
    }
    
    /// ⌃⌥V inicia/para a gravação de qualquer app. Mantenha em sincronia com `GlobalHotKey.displayString`.
    private func registerHotKey() {
        hotKey = GlobalHotKey(keyCode: kVK_ANSI_V, modifiers: controlKey | optionKey) { [weak self] in
            guard let self else { return }
            Task { await self.speechService.toggle() }
        }
        if hotKey == nil {
            print("Vox: não foi possível registrar o atalho global \(GlobalHotKey.displayString)")
        }
    }

    // MARK: - Menu da barra de status

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        // Status só aparece quando há algo a informar
        if let statusTitle {
            let item = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            menu.addItem(.separator())
        }

        let isBusy = speechService.status == .preparing || speechService.status == .downloadingModel
        // Mesmo atalho do GlobalHotKey (⌃⌥V), exibido à direita como no 1Password
        let record = NSMenuItem(
            title: speechService.isRecording ? "Parar Gravação" : "Iniciar Gravação",
            action: isBusy ? nil : #selector(toggleRecording),
            keyEquivalent: "v"
        )
        record.keyEquivalentModifierMask = [.control, .option]
        record.target = self
        menu.addItem(record)

        if !executor.transcript.isEmpty {
            let clear = NSMenuItem(title: "Limpar Transcrição", action: #selector(clearTranscript), keyEquivalent: "")
            clear.target = self
            menu.addItem(clear)
        }

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Ajustes…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let quit = NSMenuItem(title: "Sair", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private var statusTitle: String? {
        switch speechService.status {
        case .idle: nil
        case .preparing: "Preparando…"
        case .downloadingModel: "Baixando modelo…"
        case .recording: "Gravando…"
        case .error(let message): "Erro: \(message)"
        }
    }

    @objc private func toggleRecording() {
        Task { await speechService.toggle() }
    }

    @objc private func clearTranscript() {
        executor.transcript = ""
    }

    /// Janela própria: o `showSettingsWindow:` da cena `Settings` não funciona a partir do AppKit
    /// no macOS 14+, e o `openSettings` do SwiftUI só existe dentro de views.
    @objc private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: SettingsView()
                    .environmentObject(speechService)
                    .environmentObject(executor)
            ))
            window.title = "Ajustes do Vox"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
            // Back to a menu bar–only app once Settings closes.
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window,
                                                   queue: .main) { _ in
                MainActor.assumeIsolated { _ = NSApp.setActivationPolicy(.accessory) }
            }
        }
        // As an accessory app, `activate()` is only a cooperative request since macOS 14 and is
        // ignored while another app (Xcode…) is active, leaving the window behind. A regular app
        // can be activated, and `orderFrontRegardless` raises the window even if it still isn't.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
        settingsWindow?.orderFrontRegardless()
    }

    private func updateStatusBarIcon() {
        guard let button = statusItem?.button else { return }
        
        let iconName: String
        let tintColor: NSColor?

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
            // Sem tint: a imagem template segue a aparência da barra de menus (branca em barra escura).
            // `.controlTextColor` resolvia pela aparência do app e ficava preta.
            tintColor = nil
        }

        // A barra de menus ignora `contentTintColor` (o ícone saía preto), então a cor vai no
        // próprio símbolo; só o estado parado usa template para seguir a aparência da barra.
        var config = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        if let tintColor {
            config = config.applying(NSImage.SymbolConfiguration(paletteColors: [tintColor]))
        }
        if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            image.isTemplate = tintColor == nil
            button.image = image
            button.contentTintColor = nil
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
        // Default must match @AppStorage in GeneralSettingsView (false — debug only).
        let showDockModal = UserDefaults.standard.object(forKey: "showDockModal") as? Bool ?? false
        // Default must match @AppStorage in GeneralSettingsView (false).
        let showIsland = UserDefaults.standard.object(forKey: "showIsland") as? Bool ?? false
        
        islandHideTask?.cancel()
        if speechService.isRecording {
            if showIsland { island.show() }
            if showDockModal { showTranscriptionModal() }
        } else if case .error = speechService.status, showIsland {
            // Recording stopped by itself: the island says why for a few seconds.
            island.show()
            closeTranscriptionModal()
            islandHideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                self?.island.hide()
            }
        } else {
            island.hide()
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
        
        // ARC owns the window via `transcriptionWindow`; prevent AppKit's extra release on close,
        // which would leave a dangling reference and crash in closeTranscriptionModal().
        window.isReleasedWhenClosed = false
        window.title = "Vox - Transcrição"
        window.center()
        window.contentView = NSHostingView(
            rootView: TranscriptionModalView()
                .environmentObject(speechService)
                .environmentObject(executor)
        )
        
        // Debug window: show it without activating Vox, so the user's app keeps
        // focus and voice commands like "vox" still target it.
        window.level = .floating
        window.orderFrontRegardless()
        
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
            "showDockModal": false,
            "showIsland": false,
            "enableVoiceCommands": true,
            "commandPrefix": "vox"
        ])
    }
}

extension Notification.Name {
    static let speechServiceStatusChanged = Notification.Name("speechServiceStatusChanged")
}
