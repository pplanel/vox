//
//  KeyCombo.swift
//  vox
//
//  Created by Pedro Planel on 04/11/26.
//

import CoreGraphics
import Carbon.HIToolbox

/// A key with modifiers written as text in Settings ("option+delete", "cmd+shift+z", "return").
nonisolated struct KeyCombo: Equatable, Sendable {
    let keyCode: CGKeyCode
    let flags: CGEventFlags

    /// Parses "mod+mod+key", ignoring case and spaces; nil for an unknown key or modifier.
    init?(_ text: String) {
        let parts = text.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        guard let keyName = parts.last, !keyName.isEmpty, let keyCode = Self.keys[keyName] else { return nil }
        var flags: CGEventFlags = []
        for name in parts.dropLast() {
            guard let flag = Self.modifiers[name] else { return nil }
            flags.insert(flag)
        }
        self.keyCode = CGKeyCode(keyCode)
        self.flags = flags
    }

    /// Whether the key ends what was being typed (a message, a field), so the next
    /// dictated text doesn't start with a separating space.
    var endsSegment: Bool {
        [kVK_Return, kVK_ANSI_KeypadEnter, kVK_Tab, kVK_Escape].map(CGKeyCode.init).contains(keyCode)
    }

    func press() {
        let source = CGEventSource(stateID: .hidSystemState)
        for keyDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown) else { continue }
            // Set explicitly so modifiers still held from the hotkey don't leak in.
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }

    private static let modifiers: [String: CGEventFlags] = [
        "cmd": .maskCommand, "command": .maskCommand, "⌘": .maskCommand,
        "option": .maskAlternate, "opt": .maskAlternate, "alt": .maskAlternate, "⌥": .maskAlternate,
        "ctrl": .maskControl, "control": .maskControl, "⌃": .maskControl,
        "shift": .maskShift, "⇧": .maskShift,
        "fn": .maskSecondaryFn,
    ]

    private static let keys: [String: Int] = {
        var keys: [String: Int] = [
            "return": kVK_Return, "enter": kVK_Return, "tab": kVK_Tab, "space": kVK_Space, "espaco": kVK_Space,
            "delete": kVK_Delete, "backspace": kVK_Delete, "forwarddelete": kVK_ForwardDelete, "del": kVK_ForwardDelete,
            "escape": kVK_Escape, "esc": kVK_Escape,
            "left": kVK_LeftArrow, "right": kVK_RightArrow, "up": kVK_UpArrow, "down": kVK_DownArrow,
            "home": kVK_Home, "end": kVK_End, "pageup": kVK_PageUp, "pagedown": kVK_PageDown,
            "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal, "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
            ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote, ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period,
            "/": kVK_ANSI_Slash, "\\": kVK_ANSI_Backslash, "`": kVK_ANSI_Grave,
        ]
        let letters: [Int] = [
            kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H,
            kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P,
            kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X,
            kVK_ANSI_Y, kVK_ANSI_Z,
        ]
        for (letter, code) in zip("abcdefghijklmnopqrstuvwxyz", letters) { keys[String(letter)] = code }
        let digits: [Int] = [kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
                             kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        for (digit, code) in digits.enumerated() { keys[String(digit)] = code }
        let functionKeys: [Int] = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
                                   kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12]
        for (index, code) in functionKeys.enumerated() { keys["f\(index + 1)"] = code }
        return keys
    }()
}

/// Keys pressed one after the other, written as space-separated `KeyCombo`s with an optional
/// repeat count: "cmd+a delete", "option+delete*3". What the "Pressionar teclas" templates run.
nonisolated struct KeySequence: Equatable, Sendable {
    let strokes: [KeyCombo]

    static let examples = "option+delete, cmd+shift+z, return, cmd+a delete, option+delete*3"
    /// Keeps a typo like "delete*300" from flooding the app.
    static let maxRepeat = 50

    /// Nil when empty or when any key, modifier or count is invalid.
    init?(_ text: String) {
        var strokes: [KeyCombo] = []
        for token in text.split(whereSeparator: \.isWhitespace) {
            let parts = token.split(separator: "*", omittingEmptySubsequences: false)
            guard parts.count <= 2, let combo = KeyCombo(String(parts[0])) else { return nil }
            var count = 1
            if parts.count == 2 {
                guard let repeatCount = Int(parts[1]), (1...Self.maxRepeat).contains(repeatCount) else { return nil }
                count = repeatCount
            }
            strokes += Array(repeating: combo, count: count)
        }
        guard !strokes.isEmpty else { return nil }
        self.strokes = strokes
    }

    /// Whether the last key ends what was being typed (Return, Tab, Esc).
    var endsSegment: Bool { strokes.last?.endsSegment ?? false }

    /// A short pause between keys, so apps see "cmd+a" before the "delete" that follows.
    @MainActor
    func press() async {
        for (index, stroke) in strokes.enumerated() {
            if index > 0 { try? await Task.sleep(for: .milliseconds(15)) }
            stroke.press()
        }
    }
}
