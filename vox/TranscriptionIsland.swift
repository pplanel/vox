//
//  TranscriptionIsland.swift
//  vox
//
//  Created by Pedro Planel on 02/11/26.
//

import AppKit
import SwiftUI

/// Dynamic Island–style overlay hanging from the notch that shows the live transcription.
/// macOS has no public island API, so this is a borderless, click-through panel
/// that never takes focus away from the app being dictated into.
final class TranscriptionIslandController {
    /// Height of the text area shown below the notch.
    private static let contentHeight: CGFloat = 52
    private static let width: CGFloat = 440

    private var panel: NSPanel?
    private let speechService: SpeechService
    private let executor: CommandExecutor

    init(speechService: SpeechService, executor: CommandExecutor) {
        self.speechService = speechService
        self.executor = executor
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        guard !panel.isVisible else { return }

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            panel.animator().alphaValue = 0
        } completionHandler: {
            // Skip if recording restarted and `show()` faded it back in meanwhile.
            if panel.alphaValue == 0 { panel.orderOut(nil) }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        // Above the menu bar so it can merge with the notch.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        return panel
    }

    /// Pins the panel to the top center of the screen with a notch (or the main screen),
    /// reserving the notch height so the text starts right below it.
    private func position(_ panel: NSPanel) {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return }
        let notchHeight = max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
        let size = CGSize(width: Self.width, height: notchHeight + Self.contentHeight)
        let origin = CGPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height)
        panel.setFrame(CGRect(origin: origin, size: size), display: false)

        panel.contentView = NSHostingView(
            rootView: TranscriptionIslandView(notchHeight: notchHeight)
                .environmentObject(speechService)
                .environmentObject(executor)
        )
    }
}

struct TranscriptionIslandView: View {
    @EnvironmentObject var speechService: SpeechService
    @EnvironmentObject var executor: CommandExecutor
    let notchHeight: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: executor.isTypingIntoApp ? "keyboard" : "waveform")
                .symbolEffect(.variableColor.iterative, isActive: speechService.isRecording)
                .foregroundStyle(.red)
                .font(.system(size: 14, weight: .semibold))

            Group {
                if case .error(let message) = speechService.status {
                    Text("Gravação parou: \(message)")
                        .foregroundStyle(.red)
                } else if let feedback = executor.feedback {
                    Text(feedback)
                        .foregroundStyle(.yellow)
                } else {
                    // Only status: the speech itself is typed into the app as it's recognized.
                    Text(executor.isTypingIntoApp ? "Digitando…" : "Ouvindo…")
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .font(.system(size: 13, weight: .medium))
            .lineLimit(2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.top, notchHeight)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: 20, bottomTrailingRadius: 20, style: .continuous)
                .fill(.black)
        )
    }
}
