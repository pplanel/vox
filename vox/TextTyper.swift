//
//  TextTyper.swift
//  vox
//
//  Created by Pedro Planel on 02/11/26.
//

import CoreGraphics
import Carbon.HIToolbox

/// Types text into whatever element has keyboard focus by posting synthetic
/// Unicode key events. Works in native, web and Electron apps and leaves the
/// clipboard untouched. Requires the Accessibility permission.
enum TextTyper {
    /// `CGEvent` silently truncates Unicode strings longer than ~20 UTF-16 units per event.
    private static let chunkSize = 20

    static func type(_ text: String) {
        guard !text.isEmpty else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        let units = Array(text.utf16)

        var start = 0
        while start < units.count {
            var end = min(start + chunkSize, units.count)
            // Don't split a surrogate pair (emoji etc.) across two events.
            if end < units.count, UTF16.isLeadSurrogate(units[end - 1]) {
                end -= 1
            }
            let chunk = Array(units[start..<end])
            post(chunk, keyDown: true, source: source)
            post(chunk, keyDown: false, source: source)
            start = end
        }
    }

    /// Presses Return, e.g. to send a chat message.
    static func pressReturn() {
        press(kVK_Return)
    }

    /// Presses Delete `count` times, erasing that many characters before the cursor.
    static func deleteBackward(_ count: Int) {
        for _ in 0..<max(0, count) { press(kVK_Delete) }
    }

    private static func press(_ key: Int) {
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: keyDown) else { continue }
            event.flags = []
            event.post(tap: .cghidEventTap)
        }
    }

    private static func post(_ chunk: [UniChar], keyDown: Bool, source: CGEventSource?) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown) else { return }
        // Clear modifiers so keys still held (e.g. from the hotkey) don't turn text into shortcuts.
        event.flags = []
        event.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
        event.post(tap: .cghidEventTap)
    }
}
