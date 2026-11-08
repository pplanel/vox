//
//  VoiceCommandRouter.swift
//  vox
//
//  Created by Pedro Planel on 04/11/26.
//

import Foundation

/// The built-in actions of the `<comando>` entity. Raw values are its values' ids
/// (see `VoiceCommandConfig.commandKeys`).
nonisolated enum BuiltInCommand: String, Sendable {
    case focus = "focar"
    case copy = "copiar", clear = "limpar", stop = "parar", newParagraph = "novo-paragrafo"
    case deleteLastSentence = "apagar-ultima-frase", send = "enviar", next = "proximo"
    case confirm = "confirmar", cancel = "cancelar"
}

/// What a recognized segment asks for. `CommandExecutor` carries it out.
nonisolated enum VoiceAction: Equatable, Sendable {
    /// Speech to add to the transcript and, in typing mode, to the focused app.
    case dictate(String)
    case command(BuiltInCommand)
    /// What followed the wake word, for a template to resolve ("abre o claude no vox", "gemini").
    case template(String)
    /// "vox <texto>": focus the main text area, then type the text.
    case focusAndDictate(String)
    /// A lone wake word while typing: the next segment is the command.
    case awaitCommand
    case unknownCommand(String)
}

/// Turns recognized speech into `VoiceAction`s: wake word, its aliases, the `<comando>` phrases,
/// templates and the commands that work without the wake word at the end of a sentence.
/// Runs nothing, so it's testable on its own.
nonisolated struct VoiceCommandRouter {
    var wakeWord: String
    /// How other languages' models mishear the wake word ("voz", "box"…).
    var aliases: [String]
    var isEnabled: Bool

    /// Set by `.awaitCommand`; expires so a "vox" followed by silence doesn't swallow later dictation.
    private(set) var awaitingCommandUntil: ContinuousClock.Instant?
    static let awaitCommandTimeout: Duration = .seconds(5)

    init(wakeWord: String, aliases: [String], isEnabled: Bool) {
        self.wakeWord = wakeWord
        self.aliases = aliases
        self.isEnabled = isEnabled
    }

    func isAwaitingCommand(at now: ContinuousClock.Instant = .now) -> Bool {
        awaitingCommandUntil.map { now < $0 } ?? false
    }

    mutating func reset() {
        awaitingCommandUntil = nil
    }

    // MARK: - Routing

    /// The actions for a finalized segment, in order. `isTyping` is whether speech goes into an app.
    mutating func route(_ text: String, isTyping: Bool, config: VoiceCommandConfig,
                        now: ContinuousClock.Instant = .now) -> [VoiceAction] {
        guard isEnabled else { return [.dictate(text)] }

        // The segment after a lone wake word is the command.
        let awaited = isAwaitingCommand(at: now)
        awaitingCommandUntil = nil
        if awaited {
            return [routeCommand(text, isTyping: isTyping, allowsDictation: false, config: config, now: now)]
        }

        // "… texto vox enviar": the words before the wake word are dictation, the rest a command.
        if let split = Self.split(text, atWakeWord: wakeWord), !Self.isBlank(split.dictation) {
            return dictation(split.dictation, config: config)
                + [routeCommand(split.remainder, isTyping: isTyping, allowsDictation: false, config: config, now: now)]
        }

        if let remainder = Self.remainder(afterWakeWord: wakeWord, in: text) {
            return [routeCommand(remainder, isTyping: isTyping, allowsDictation: true, config: config, now: now)]
        }

        // Aliases only count before a known command or template, so ordinary sentences starting
        // with "voz" stay dictation. Templates that run something ask for confirmation, so a
        // false match is harmless.
        for alias in aliases {
            guard let remainder = Self.remainder(afterWakeWord: alias, in: text) else { continue }
            if let command = Self.command(for: remainder, config: config) {
                return [.command(command)]
            }
            if CommandResolver.isRequest(remainder, config: config) {
                return [.template(remainder)]
            }
        }
        return dictation(text, config: config)
    }

    /// What follows the wake word. `allowsDictation` keeps "vox <texto>" for segments that start
    /// with the wake word; mid-speech (and for the silence action) it's only ever a command.
    mutating func routeCommand(_ remainder: String, isTyping: Bool, allowsDictation: Bool,
                               config: VoiceCommandConfig, now: ContinuousClock.Instant = .now) -> VoiceAction {
        if let command = Self.command(for: remainder, config: config) {
            // A lone "vox" while already typing waits for the command in the next segment.
            if command == .focus && CommandText.tokens(remainder).isEmpty && (isTyping || !allowsDictation) {
                awaitingCommandUntil = now + Self.awaitCommandTimeout
                return .awaitCommand
            }
            return .command(command)
        }
        if CommandResolver.isRequest(remainder, config: config) {
            return .template(remainder)
        }
        if allowsDictation {
            return .focusAndDictate(remainder)
        }
        return .unknownCommand(remainder.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The part of a phrase still being recognized that may be typed: nothing from the wake word on.
    func liveDictation(_ text: String, now: ContinuousClock.Instant = .now) -> String {
        guard isEnabled else { return text }
        if isAwaitingCommand(at: now) { return "" }
        return Self.split(text, atWakeWord: wakeWord)?.dictation ?? text
    }

    /// Dictation, then the command it ends with, if any: "enviar" and "próximo" work without the
    /// wake word as the whole segment or right after a finished sentence ("Tudo bem? Enviar."),
    /// never mid-sentence ("vou enviar o arquivo").
    func dictation(_ text: String, config: VoiceCommandConfig) -> [VoiceAction] {
        for (command, pattern) in Self.trailingCommandPatterns(config: config) {
            guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { continue }
            var body = text
            body.removeSubrange(range)
            return [.dictate(body), .command(command)]
        }
        return [.dictate(text)]
    }

    // MARK: - Text

    /// The wake word alone focuses; anything else is looked up in the `<comando>` entity,
    /// without case, accents or punctuation, since the transcriber varies them.
    static func command(for phrase: String, config: VoiceCommandConfig) -> BuiltInCommand? {
        if CommandText.tokens(phrase).isEmpty { return .focus }
        guard let key = config.commandKey(for: phrase), VoiceCommandConfig.commandKeys.contains(key) else { return nil }
        return BuiltInCommand(rawValue: key)
    }

    /// Splits the segment at the first whole-word wake word: the dictation before it and the
    /// text after it ("Tudo certo vox enviar" → ("Tudo certo ", " enviar")). Nil without one.
    static func split(_ text: String, atWakeWord wakeWord: String) -> (dictation: String, remainder: String)? {
        let word = wakeWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return nil }
        let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: word) + "(?![\\p{L}\\p{N}])"
        guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return (String(text[..<range.lowerBound]), String(text[range.upperBound...]))
    }

    /// Text after `wakeWord` when the segment starts with it as a whole word
    /// ("Vox, copiar." → " copiar.", but "Voxel" → nil). Original casing is kept for dictation.
    static func remainder(afterWakeWord wakeWord: String, in text: String) -> String? {
        let word = wakeWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { return nil }
        let pattern = "^[\\s\\p{P}]*" + NSRegularExpression.escapedPattern(for: word) + "\\b[\\s\\p{P}]*"
        guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return String(text[range.upperBound...])
    }

    private static func isBlank(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).isEmpty
    }

    /// The phrases come from the `<comando>` values for "enviar" and "proximo".
    private static func trailingCommandPatterns(config: VoiceCommandConfig) -> [(BuiltInCommand, String)] {
        let values = config.entity(named: VoiceCommandConfig.commandEntityName)?.values ?? []
        return [BuiltInCommand.send, .next].compactMap { command in
            guard let value = values.first(where: { $0.key == command.rawValue }) else { return nil }
            // Regex can't ignore accents, so each phrase also goes in without them ("próximo", "proximo").
            let phrases = ([value.label] + value.aliasList).flatMap { phrase in
                [phrase, phrase.folding(options: .diacriticInsensitive, locale: nil)]
            }
            let words = Set(phrases.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
                .map { NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(of: " ", with: "\\s+") }
            guard !words.isEmpty else { return nil }
            return (command, "(^|(?<=[.!?…])\\s+)[\\s\\p{P}]*(\(words.joined(separator: "|")))[\\s\\p{P}]*$")
        }
    }
}
