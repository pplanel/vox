//
//  GlobalHotKey.swift
//  vox
//
//  Created by Pedro Planel on 02/11/26.
//

import AppKit
import Carbon.HIToolbox

/// System-wide hotkey registered through Carbon's `RegisterEventHotKey`.
/// Unlike `NSEvent` global monitors, it needs no Accessibility permission
/// and fires even while another app is frontmost.
final class GlobalHotKey {
    /// Shortcut shown in the UI; keep in sync with `AppDelegate.registerHotKey()`.
    static let displayString = "⌃⌥V"

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    /// - Parameters:
    ///   - keyCode: Virtual key code, e.g. `kVK_ANSI_V`.
    ///   - modifiers: Carbon modifier mask, e.g. `controlKey | optionKey`.
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        // The C callback can't capture context, so `self` travels through `userData`.
        // Application-target handlers are always invoked on the main thread.
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { hotKey.action() }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard installStatus == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x564F_5821) /* 'VOX!' */, id: 1)
        let registerStatus = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            RemoveEventHandler(handlerRef)
            return nil
        }
    }

    isolated deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
