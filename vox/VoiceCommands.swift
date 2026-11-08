//
//  VoiceCommands.swift
//  vox
//
//  Created by Pedro Planel on 03/11/26.
//

import Foundation
import FoundationModels

// MARK: - Model

/// A named list of values a template field can take ("agente", "projeto"), edited in
/// Settings → Comandos de voz.
nonisolated struct CommandEntity: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var name: String
    var values: [EntityValue]
    /// Values go into the command as shell code ("git pull") instead of one quoted word.
    /// They come from Settings, never from speech, so only `{pedido}` must always be quoted.
    var insertsRawValue = false

    init(id: UUID = UUID(), name: String, values: [EntityValue], insertsRawValue: Bool = false) {
        self.id = id
        self.name = name
        self.values = values
        self.insertsRawValue = insertsRawValue
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, values, insertsRawValue
    }

    /// Fields added later decode with their defaults, so an older VoiceCommands.json still loads.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        values = try container.decode([EntityValue].self, forKey: .values)
        insertsRawValue = try container.decodeIfPresent(Bool.self, forKey: .insertsRawValue) ?? false
    }
}

nonisolated struct EntityValue: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    /// Canonical id the model chooses from ("claude").
    var key: String
    /// Shown in confirmations and used in training phrases ("Claude").
    var label: String
    /// Comma-separated misrecognitions ("cláudio, clode"); they also fix the names in `{pedido}`.
    var aliases: String = ""
    /// What goes into the shell command (the executable, the folder…).
    var value: String
    /// Comma-separated pt-BR spellings of how it's spoken ("clód, clódi"), see `SoundsLike`.
    var soundsLike: String = ""

    var aliasList: [String] {
        aliases.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

nonisolated struct CommandTemplate: Codable, Identifiable, Hashable, Sendable {
    enum Target: String, Codable, CaseIterable, Sendable {
        /// A new tmux window, shown in Ghostty.
        case tmuxWindow
        /// Detached, output in ~/Library/Logs/vox-commands.log.
        case background
        /// Jumps to the tmux pane already running the command's program and types into it.
        /// Runs nothing, so it doesn't ask for confirmation.
        case tmuxPane
        /// Brings an app's window forward (the "command" is its bundle id, opening it if needed)
        /// and types into it. Runs nothing, so it doesn't ask for confirmation.
        case appWindow
        /// Presses the keys the command spells out in the focused app ("cmd+a delete",
        /// "{tecla}"), see `KeySequence`. Runs nothing, so it doesn't ask for confirmation.
        case keys

        var displayName: String {
            switch self {
            case .tmuxWindow: "Nova janela do tmux"
            case .background: "Segundo plano"
            case .tmuxPane: "Pane do tmux existente"
            case .appWindow: "Focar app"
            case .keys: "Pressionar teclas"
            }
        }

        /// Only targets that run a shell command wait for "sim"; the others move focus or press keys.
        var asksConfirmation: Bool { self == .tmuxWindow || self == .background }
    }

    var id = UUID()
    /// "abre o <agente> no <projeto>"
    var phrase: String
    /// "cd {projeto} && {agente} {pedido}"
    var command: String
    var target: Target = .tmuxWindow
}

nonisolated struct VoiceCommandConfig: Codable, Equatable, Sendable {
    var entities: [CommandEntity]
    var templates: [CommandTemplate]

    /// Templates that pass `TemplateValidator`; the others are ignored until fixed.
    var validTemplates: [CommandTemplate] {
        templates.filter { TemplateValidator.issues(in: $0, entities: entities).isEmpty }
    }

    func entity(named name: String) -> CommandEntity? {
        let folded = CommandText.foldedName(name)
        return entities.first { CommandText.foldedName($0.name) == folded }
    }

    // MARK: Built-in commands

    /// The `<comando>` entity lists the built-in actions ("vox copiar"…): each value's id picks
    /// the action, its label and aliases are the phrases that trigger it.
    static let commandEntityName = "comando"

    /// Ids the `<comando>` values may use, one per built-in action.
    static let commandKeys = ["focar", "copiar", "limpar", "parar", "novo-paragrafo", "apagar-ultima-frase",
                              "enviar", "proximo", "confirmar", "cancelar"]

    /// The default `<tecla>` entity: what you say and the keys it presses ("option+delete"),
    /// run by the `<tecla>` "Pressionar teclas" template. Plain data, editable like any entity.
    static let keyEntityName = "tecla"

    static let defaultCommandEntity = CommandEntity(name: commandEntityName, values: [
        // "vox" alone does the same.
        EntityValue(key: "focar", label: "focar", aliases: "foca, digitar", value: "focar"),
        EntityValue(key: "copiar", label: "copiar", value: "copiar"),
        EntityValue(key: "limpar", label: "limpar", value: "limpar"),
        EntityValue(key: "parar", label: "parar", value: "parar"),
        EntityValue(key: "novo-paragrafo", label: "novo parágrafo", aliases: "nova linha", value: "novo-paragrafo"),
        EntityValue(key: "apagar-ultima-frase", label: "apagar última frase", value: "apagar-ultima-frase"),
        EntityValue(key: "enviar", label: "enviar", aliases: "send", value: "enviar"),
        EntityValue(key: "proximo", label: "próximo", aliases: "próxima, next", value: "proximo"),
        // pt-BR often hears "sim" as "sin" or "si".
        EntityValue(key: "confirmar", label: "sim", aliases: "sin, si, yes, confirmar, confirma", value: "confirmar"),
        EntityValue(key: "cancelar", label: "não", aliases: "no, cancelar, cancela", value: "cancelar"),
    ])

    static let defaultKeyEntity = CommandEntity(name: keyEntityName, values: [
        EntityValue(key: "apagar-palavra", label: "apagar palavra", aliases: "apaga palavra, apagar última palavra",
                    value: "option+delete"),
        EntityValue(key: "apagar-linha", label: "apagar linha", aliases: "apaga linha", value: "cmd+delete"),
        EntityValue(key: "apagar-letra", label: "apagar letra", aliases: "apaga letra", value: "delete"),
        EntityValue(key: "enter", label: "enter", aliases: "quebra de linha", value: "return"),
        EntityValue(key: "tab", label: "tab", value: "tab"),
        EntityValue(key: "esc", label: "esc", aliases: "escape", value: "escape"),
        EntityValue(key: "desfazer", label: "desfazer", aliases: "desfaz", value: "cmd+z"),
        EntityValue(key: "refazer", label: "refazer", aliases: "refaz", value: "cmd+shift+z"),
        EntityValue(key: "selecionar-tudo", label: "selecionar tudo", aliases: "seleciona tudo", value: "cmd+a"),
    ])

    /// The `<app>` entity lists apps with windows, filled from the open ones (see
    /// `addApps`) and kept when they close, so their "soa como" stays. Each value's
    /// "valor no comando" is the bundle id.
    static let appEntityName = "app"

    static let defaultAppEntity = CommandEntity(name: appEntityName, values: [])

    /// "vox gemini": focuses the app.
    static let defaultAppTemplate = CommandTemplate(phrase: "<\(appEntityName)>", command: "{\(appEntityName)}",
                                                    target: .appWindow)

    /// "vox apagar palavra": presses the value's keys.
    static let defaultKeysTemplate = CommandTemplate(phrase: "<\(keyEntityName)>", command: "{\(keyEntityName)}",
                                                     target: .keys)

    /// `<comando>` and `<app>` drive built-in behavior, so they can't be renamed or deleted.
    static let builtInEntityNames = [commandEntityName, appEntityName]

    func isCommandEntity(_ id: CommandEntity.ID) -> Bool {
        entity(named: Self.commandEntityName)?.id == id
    }

    func isAppEntity(_ id: CommandEntity.ID) -> Bool {
        entity(named: Self.appEntityName)?.id == id
    }

    func isBuiltInEntity(_ id: CommandEntity.ID) -> Bool {
        isCommandEntity(id) || isAppEntity(id)
    }

    /// Adds the apps not in `<app>` yet, matched by bundle id; existing values are left as edited.
    mutating func addApps(_ apps: [(name: String, bundleID: String)]) {
        if entity(named: Self.appEntityName) == nil { entities.append(Self.defaultAppEntity) }
        guard let index = entities.firstIndex(where: { CommandText.foldedName($0.name) == Self.appEntityName }) else { return }
        var bundleIDs = Set(entities[index].values.map(\.value))
        var keys = Set(entities[index].values.map(\.key))
        for app in apps where bundleIDs.insert(app.bundleID).inserted {
            // The model picks by id, so ids stay unique ("code", "code-2").
            let base = CommandText.tokens(app.name).joined(separator: "-")
            var key = base.isEmpty ? app.bundleID.lowercased() : base
            var suffix = 2
            while !keys.insert(key).inserted {
                key = "\(base)-\(suffix)"
                suffix += 1
            }
            entities[index].values.append(EntityValue(key: key, label: app.name, value: app.bundleID))
        }
    }

    /// The value of `entityName` the whole phrase names by its id, label or an alias.
    /// Compared without case, accents or punctuation ("Sim!" → "confirmar").
    private func value(in entityName: String, for phrase: String) -> EntityValue? {
        let spoken = CommandText.tokens(phrase)
        guard !spoken.isEmpty, let entity = entity(named: entityName) else { return nil }
        return entity.values.first { value in
            ([value.key, value.label] + value.aliasList).contains { CommandText.tokens($0) == spoken }
        }
    }

    /// Id of the `<comando>` value the phrase names.
    func commandKey(for phrase: String) -> String? {
        value(in: Self.commandEntityName, for: phrase)?.key
    }

    /// Adds the built-in entities, and the default values missing from them, by id. Run once per
    /// `builtInsVersion` (see `VoiceCommandStore`), so values deleted afterwards stay deleted.
    mutating func addMissingBuiltIns() {
        if !templates.contains(where: { $0.target == .appWindow }) {
            templates.append(Self.defaultAppTemplate)
        }
        if !templates.contains(where: { $0.target == .keys }) {
            templates.append(Self.defaultKeysTemplate)
        }
        for defaults in [Self.defaultCommandEntity, Self.defaultKeyEntity, Self.defaultAppEntity] {
            guard let index = entities.firstIndex(where: { CommandText.foldedName($0.name) == defaults.name }) else {
                entities.append(defaults)
                continue
            }
            let keys = Set(entities[index].values.map(\.key))
            entities[index].values += defaults.values.filter { !keys.contains($0.key) }
        }
    }

    // MARK: Editing

    /// Why `name` can't name an entity, or nil. It goes inside `<>` and `{}`, so only letters,
    /// digits, "_" and "-"; `pedido` is taken by the request.
    func nameIssue(_ name: String, for entityID: CommandEntity.ID?) -> String? {
        let folded = CommandText.foldedName(name)
        if folded.isEmpty { return "O nome não pode ficar vazio" }
        if name.contains(where: { !$0.isLetter && !$0.isNumber && $0 != "_" && $0 != "-" }) {
            return "Use só letras, números, _ e -"
        }
        if folded == CommandText.requestPlaceholder { return "“pedido” é reservado para o texto transcrito" }
        // Only the built-in entity itself may keep its reserved name.
        let currentName = entities.first { $0.id == entityID }.map { CommandText.foldedName($0.name) }
        if Self.builtInEntityNames.contains(folded), currentName != folded {
            return "“\(folded)” é reservado para os comandos do Vox"
        }
        if entities.contains(where: { $0.id != entityID && CommandText.foldedName($0.name) == folded }) {
            return "Já existe uma entidade com esse nome"
        }
        return nil
    }

    /// Adds an entity with a free name ("entidade", "entidade2"…) and returns its id.
    mutating func addEntity() -> CommandEntity.ID {
        var name = "entidade"
        var suffix = 2
        while nameIssue(name, for: nil) != nil {
            name = "entidade\(suffix)"
            suffix += 1
        }
        let entity = CommandEntity(name: name, values: [])
        entities.append(entity)
        return entity.id
    }

    /// Renames the entity and its `<campo>` / `{campo}` in every template, so they keep working.
    mutating func renameEntity(_ id: CommandEntity.ID, to newName: String) {
        guard let index = entities.firstIndex(where: { $0.id == id }), nameIssue(newName, for: id) == nil else { return }
        let old = NSRegularExpression.escapedPattern(for: entities[index].name.trimmingCharacters(in: .whitespaces))
        let new = NSRegularExpression.escapedTemplate(for: newName)
        entities[index].name = newName
        guard !old.isEmpty,
              let field = try? NSRegularExpression(pattern: "<\\s*\(old)\\s*>", options: .caseInsensitive),
              let placeholder = try? NSRegularExpression(pattern: "(?<!\\$)\\{\(old)\\}", options: .caseInsensitive)
        else { return }
        for i in templates.indices {
            let phrase = templates[i].phrase
            templates[i].phrase = field.stringByReplacingMatches(
                in: phrase, range: NSRange(location: 0, length: (phrase as NSString).length), withTemplate: "<\(new)>")
            let command = templates[i].command
            templates[i].command = placeholder.stringByReplacingMatches(
                in: command, range: NSRange(location: 0, length: (command as NSString).length), withTemplate: "{\(new)}")
        }
    }

    /// Whether a "Pressionar teclas" template uses the entity, so its values must be keys.
    func pressesKeys(_ entityID: CommandEntity.ID) -> Bool {
        templates(using: entityID).contains { $0.target == .keys }
    }

    /// Templates with a `<campo>` for the entity; they break if it's deleted.
    func templates(using entityID: CommandEntity.ID) -> [CommandTemplate] {
        guard let entity = entities.first(where: { $0.id == entityID }) else { return [] }
        let name = CommandText.foldedName(entity.name)
        return templates.filter { PhrasePart.fields(in: $0.phrase).contains { CommandText.foldedName($0) == name } }
    }

    /// Replaces the template with the same id, or appends it.
    mutating func upsert(_ template: CommandTemplate) {
        if let index = templates.firstIndex(where: { $0.id == template.id }) {
            templates[index] = template
        } else {
            templates.append(template)
        }
    }

    /// Why a value can't be used, or nil: the model chooses by id, so it must be set and unique.
    func valueIssue(_ value: EntityValue, in entityID: CommandEntity.ID) -> String? {
        if value.key.trimmingCharacters(in: .whitespaces).isEmpty { return "Sem id, o valor é ignorado" }
        let siblings = entities.first { $0.id == entityID }?.values ?? []
        if siblings.contains(where: { $0.id != value.id && $0.key == value.key }) { return "Id repetido nesta entidade" }
        if isCommandEntity(entityID), !Self.commandKeys.contains(value.key) {
            return "Id de comando desconhecido; use \(Self.commandKeys.joined(separator: ", "))"
        }
        if isAppEntity(entityID), value.value.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Sem bundle id em “valor no comando”, o app não é encontrado"
        }
        if pressesKeys(entityID), KeySequence(value.value) == nil {
            return "Tecla desconhecida em “valor no comando”; use por exemplo \(KeySequence.examples)"
        }
        return nil
    }
}

// MARK: - Text

/// Comparisons ignore case, accents and punctuation, since the transcriber varies them.
nonisolated enum CommandText {
    /// "Cognia-Labs!" → ["cognia", "labs"]
    static func tokens(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    static func foldedName(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// The special placeholder for the transcribed request.
    static let requestPlaceholder = "pedido"

    /// Folded words that are the same or differ only in a verb ending, since the transcriber
    /// picks its own form: "abre", "abra" and "abrir"; "roda" and "rodar". At most two letters
    /// more, so "abreviar" isn't "abre"; words under three letters must match exactly.
    static func sameWord(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let shorter = min(a.count, b.count)
        guard shorter >= 3, abs(a.count - b.count) <= 2 else { return false }
        let common = zip(a, b).prefix { $0 == $1 }.count
        return common >= max(3, shorter - 1)
    }

    /// Whether `tokens` starts with `words`, allowing `sameWord` variants.
    static func starts(_ tokens: some Collection<String>, with words: [String]) -> Bool {
        tokens.count >= words.count && zip(tokens, words).allSatisfy { sameWord($0, $1) }
    }
}

/// One piece of a template phrase: literal words or a `<campo>`.
nonisolated enum PhrasePart: Equatable {
    case words([String])
    case field(String)

    private static let fieldPattern = try! NSRegularExpression(pattern: "<([^<>]*)>")

    /// "abre o <agente> no <projeto>" → [words(abre o), field(agente), words(no), field(projeto)];
    /// field names keep their spelling, words are folded with `CommandText.tokens`.
    static func parse(_ phrase: String) -> [PhrasePart] {
        var parts: [PhrasePart] = []
        var cursor = phrase.startIndex
        let ns = phrase as NSString
        for match in fieldPattern.matches(in: phrase, range: NSRange(location: 0, length: ns.length)) {
            guard let whole = Range(match.range, in: phrase), let name = Range(match.range(at: 1), in: phrase) else { continue }
            let words = CommandText.tokens(String(phrase[cursor..<whole.lowerBound]))
            if !words.isEmpty { parts.append(.words(words)) }
            parts.append(.field(phrase[name].trimmingCharacters(in: .whitespaces)))
            cursor = whole.upperBound
        }
        let words = CommandText.tokens(String(phrase[cursor...]))
        if !words.isEmpty { parts.append(.words(words)) }
        return parts
    }

    static func fields(in phrase: String) -> [String] {
        parse(phrase).compactMap { if case .field(let name) = $0 { name } else { nil } }
    }
}

// MARK: - Validation

nonisolated enum TemplateIssue: Equatable, Hashable {
    case emptyPhrase
    case emptyCommand
    case emptyField
    case unknownEntity(String)
    case duplicateField(String)
    case unknownPlaceholder(String)
    case invalidKeys(String)

    var message: String {
        switch self {
        case .emptyPhrase: "A frase está vazia"
        case .emptyCommand: "O comando está vazio"
        case .emptyField: "Há um campo <> sem nome"
        case .unknownEntity(let name): "<\(name)> não é uma entidade"
        case .duplicateField(let name): "<\(name)> aparece mais de uma vez na frase"
        case .unknownPlaceholder(let name): "{\(name)} não é um campo da frase nem {pedido}"
        case .invalidKeys(let keys): "“\(keys)” não é uma tecla; use por exemplo \(KeySequence.examples)"
        }
    }
}

nonisolated enum TemplateValidator {
    static func issues(in template: CommandTemplate, entities: [CommandEntity]) -> [TemplateIssue] {
        var issues: [TemplateIssue] = []
        if template.phrase.trimmingCharacters(in: .whitespaces).isEmpty { issues.append(.emptyPhrase) }
        if template.command.trimmingCharacters(in: .whitespaces).isEmpty { issues.append(.emptyCommand) }

        let entityNames = Set(entities.map { CommandText.foldedName($0.name) })
        // A field without entity is reported once, not again for its placeholder.
        var seen: Set<String> = []
        for field in PhrasePart.fields(in: template.phrase) {
            let folded = CommandText.foldedName(field)
            if folded.isEmpty {
                issues.append(.emptyField)
            } else if !seen.insert(folded).inserted {
                issues.append(.duplicateField(field))
            } else if !entityNames.contains(folded) {
                issues.append(.unknownEntity(field))
            }
        }
        for placeholder in ShellCommand.placeholders(in: template.command) {
            let folded = CommandText.foldedName(placeholder)
            if folded != CommandText.requestPlaceholder && !seen.contains(folded) {
                issues.append(.unknownPlaceholder(placeholder))
            }
        }
        // Keys written in the command itself; the entities' values are checked per value.
        if template.target == .keys {
            let literal = ShellCommand.render(template.command, values: [:], removingPlaceholders: true)
            for token in literal.split(whereSeparator: \.isWhitespace) where KeySequence(String(token)) == nil {
                issues.append(.invalidKeys(String(token)))
            }
        }
        return issues
    }
}

// MARK: - Shell

nonisolated enum ShellCommand {
    /// `{campo}`, but not `${VAR}`, which belongs to the shell.
    private static let placeholderPattern = try! NSRegularExpression(pattern: "(?<!\\$)\\{([\\p{L}\\p{N}_-]+)\\}")

    static func placeholders(in command: String) -> [String] {
        let ns = command as NSString
        return placeholderPattern.matches(in: command, range: NSRange(location: 0, length: ns.length))
            .map { ns.substring(with: $0.range(at: 1)) }
    }

    /// Single quotes keep everything literal (spaces, `;`, `$(…)`); a quote inside is closed,
    /// escaped and reopened.
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Replaces each placeholder with its quoted value in one pass, so a value that contains
    /// `{campo}` is never expanded again. Keys are folded field names; those in `raw` go in
    /// unquoted (entities marked as shell code, or everything for `.tmuxPane`, whose "command"
    /// is a program name to look for, never run).
    /// `removingPlaceholders` drops the unknown ones instead of keeping them as written.
    static func render(_ command: String, values: [String: String], raw: Set<String> = [],
                       removingPlaceholders: Bool = false) -> String {
        let ns = command as NSString
        var result = ""
        var cursor = 0
        for match in placeholderPattern.matches(in: command, range: NSRange(location: 0, length: ns.length)) {
            result += ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let name = CommandText.foldedName(ns.substring(with: match.range(at: 1)))
            result += values[name].map { raw.contains(name) ? $0 : quote($0) }
                ?? (removingPlaceholders ? " " : ns.substring(with: match.range))
            cursor = match.range.location + match.range.length
        }
        return result + ns.substring(from: cursor)
    }
}

// MARK: - Prepared command

/// A template with its fields chosen, ready for "vox sim".
nonisolated struct PreparedCommand: Equatable {
    let template: CommandTemplate
    /// Folded field name → chosen value.
    let values: [String: EntityValue]
    /// `{pedido}`: the transcript with names fixed by the aliases and the issue ID normalized.
    let request: String
    /// Empty when the request names no issue.
    let issueID: String
    /// Exactly what runs.
    let command: String

    init(template: CommandTemplate, values: [String: EntityValue], transcript: String, entities: [CommandEntity]) {
        self.template = template
        self.values = values

        let issue = IssueID.find(in: transcript)
        issueID = issue?.id ?? ""
        var text = transcript
        if let issue {
            text.replaceSubrange(issue.range, with: issue.id)
        }
        request = AliasCorrection.apply(entities, to: text)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))

        var substitutions = values.mapValues(\.value)
        substitutions[CommandText.requestPlaceholder] = request
        // The request is transcribed speech: quoted even when everything else is raw, except
        // for targets that don't run a shell command.
        var raw = Set(PhrasePart.fields(in: template.phrase).map(CommandText.foldedName).filter { field in
            entities.first { CommandText.foldedName($0.name) == field }?.insertsRawValue == true
        })
        if !template.target.asksConfirmation { raw.formUnion(substitutions.keys) }
        command = ShellCommand.render(template.command, values: substitutions, raw: raw)
    }

    /// Labels in phrase order, e.g. "Claude · cognia-labs"; names the tmux window.
    var title: String {
        PhrasePart.fields(in: template.phrase)
            .compactMap { values[CommandText.foldedName($0)]?.label }
            .joined(separator: " · ")
    }

    /// "Rodar (HGR-217): cd '…' && 'claude' '…'?"
    var confirmation: String {
        let issue = issueID.isEmpty ? "" : " (\(issueID))"
        return "Rodar\(issue): \(command)?"
    }
}

/// Fixes how the transcriber writes names, word by word, using each value's aliases.
nonisolated enum AliasCorrection {
    static func apply(_ entities: [CommandEntity], to text: String) -> String {
        // Longest first, so "nix darwin" wins over "nix"; the first value claiming a form wins.
        // Labels and ids map to nil (kept as spoken): with alias "git" and label "git pull",
        // "git pull" must stay as is instead of becoming "git pull pull".
        var replacements: [(alias: String, label: String?)] = []
        var claimed: Set<String> = []
        for value in entities.flatMap(\.values) {
            for form in [value.label, value.key] where !CommandText.tokens(form).isEmpty
                && claimed.insert(CommandText.foldedName(form)).inserted {
                replacements.append((form, nil))
            }
            for alias in value.aliasList where claimed.insert(CommandText.foldedName(alias)).inserted {
                replacements.append((alias, value.label))
            }
        }
        replacements.sort { $0.alias.count > $1.alias.count }
        guard !replacements.isEmpty else { return text }

        let alternatives = replacements.map { alias in
            CommandText.tokens(alias.alias).map(NSRegularExpression.escapedPattern(for:)).joined(separator: "[\\s\\p{P}]+")
        }
        // Matched on the folded text so accents and case don't matter; offsets carry over
        // because folding keeps one character per character for Latin text.
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard (folded as NSString).length == (text as NSString).length,
              let regex = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}])(?:\(alternatives.joined(separator: "|")))(?![\\p{L}\\p{N}])")
        else { return text }

        let labels = Dictionary(replacements.map { (CommandText.tokens($0.alias), $0.label) }, uniquingKeysWith: { first, _ in first })
        let source = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: folded, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let matched = CommandText.tokens((folded as NSString).substring(with: match.range))
            result += labels[matched].flatMap { $0 } ?? source.substring(with: match.range)
            cursor = match.range.location + match.range.length
        }
        return result + source.substring(from: cursor)
    }
}

// MARK: - Resolution

nonisolated enum CommandResolver {
    struct Resolution: Equatable {
        let template: CommandTemplate
        /// Folded field name → value.
        let values: [String: EntityValue]
    }

    enum Failure: LocalizedError {
        case modelUnavailable
        case notUnderstood
        case missingField(String)

        var errorDescription: String? {
            switch self {
            case .modelUnavailable: "Apple Intelligence indisponível"
            case .notUnderstood: "Não entendi o comando"
            case .missingField(let field): "Não entendi o \(field)"
            }
        }
    }

    /// Whether the text after the wake word looks like one of the templates: it starts with
    /// a template's first words (or, for a phrase that starts with a field, one of its values).
    static func isRequest(_ remainder: String, config: VoiceCommandConfig) -> Bool {
        let tokens = CommandText.tokens(remainder)
        return config.validTemplates.contains { template in
            switch PhrasePart.parse(template.phrase).first {
            case .words(let words): CommandText.starts(tokens, with: words)
            case .field(let name):
                (config.entity(named: name)?.values ?? []).contains { value in
                    forms(of: value).contains { tokens.starts(with: $0) }
                }
            case nil: false
            }
        }
    }

    /// Resolves without the model when the phrase matches word by word and every field names
    /// a value through its id, label or an alias. Among several matches the one covering more
    /// words wins ("cognia labs" over "cognia"), then the one with fewer typos ("vox" over
    /// "fox"); a tie means nil, so the model decides.
    static func resolveWithAliases(_ remainder: String, config: VoiceCommandConfig) -> Resolution? {
        let tokens = CommandText.tokens(remainder)
        var best: [(resolution: Resolution, score: Score)] = []
        for template in config.validTemplates {
            for (values, score) in matches(PhrasePart.parse(template.phrase)[...], tokens: tokens[...], config: config) {
                let candidate = Resolution(template: template, values: values)
                if best.isEmpty || score.beats(best[0].score) {
                    best = [(candidate, score)]
                } else if !best[0].score.beats(score), !best.contains(where: { $0.resolution == candidate }) {
                    best.append((candidate, score))
                }
            }
        }
        return best.count == 1 ? best[0].resolution : nil
    }

    /// Words of the phrase a match covered and how many of them were misheard.
    private struct Score {
        var consumed = 0
        var typos = 0

        func beats(_ other: Score) -> Bool {
            consumed != other.consumed ? consumed > other.consumed : typos < other.typos
        }

        static func + (lhs: Score, rhs: Score) -> Score {
            Score(consumed: lhs.consumed + rhs.consumed, typos: lhs.typos + rhs.typos)
        }
    }

    /// Said before a value but rarely written in the phrase: "abre o mix darwin e roda o git pull"
    /// for "abre <projeto> e <verbo> <comando>".
    private static let articles: Set<String> = ["o", "a", "os", "as", "um", "uma"]

    /// Every way `parts` matches the start of `tokens`, with the words each consumed.
    private static func matches(_ parts: ArraySlice<PhrasePart>, tokens: ArraySlice<String>,
                                config: VoiceCommandConfig) -> [([String: EntityValue], Score)] {
        guard let part = parts.first else { return [([:], Score())] }
        switch part {
        case .words(let words):
            guard CommandText.starts(tokens, with: words) else { return [] }
            // A different verb form counts as a typo, so the exact template wins a tie.
            let typos = zip(tokens, words).filter { $0 != $1 }.count
            return matches(parts.dropFirst(), tokens: tokens.dropFirst(words.count), config: config)
                .map { ($0.0, $0.1 + Score(consumed: words.count, typos: typos)) }
        case .field(let name):
            guard let entity = config.entity(named: name) else { return [] }
            let key = CommandText.foldedName(name)
            var starts = [(tokens, 0)]
            if let first = tokens.first, articles.contains(first) { starts.append((tokens.dropFirst(), 1)) }
            var results: [([String: EntityValue], Score)] = []
            for (start, skipped) in starts {
                for value in entity.values where !value.key.isEmpty {
                    // The longest form of a value is enough; shorter ones would only duplicate it.
                    let found = forms(of: value).compactMap { form in typos(start, startingWith: form).map { (form, $0) } }
                    guard let (form, typos) = found.max(by: { ($0.0.count, -$0.1) < ($1.0.count, -$1.1) }) else { continue }
                    for (rest, score) in matches(parts.dropFirst(), tokens: start.dropFirst(form.count), config: config) {
                        var values = rest
                        values[key] = value
                        results.append((values, score + Score(consumed: form.count + skipped, typos: typos)))
                    }
                }
            }
            return results
        }
    }

    /// Misheard words if `tokens` starts with `form` allowing `isClose` typos ("roda" for
    /// "rodar"), or nil.
    private static func typos(_ tokens: ArraySlice<String>, startingWith form: [String]) -> Int? {
        guard tokens.count >= form.count else { return nil }
        var typos = 0
        for (word, said) in zip(form, tokens) where word != said {
            guard isClose(word, said) else { return nil }
            typos += 1
        }
        return typos
    }

    private static func forms(of value: EntityValue) -> [[String]] {
        ([value.key, value.label] + value.aliasList).map(CommandText.tokens).filter { !$0.isEmpty }
    }

    // MARK: Model

    /// Choice meaning "no template" or "field not said".
    static let noneChoice = "nenhum"
    static let templateProperty = "template"

    /// `anyOf` with one object per template — its phrase as a one-choice `template` property
    /// plus one property per field, each a closed list of the entity's ids or "nenhum" — and
    /// a last case for "nenhum". The model never writes free text.
    static func schema(for config: VoiceCommandConfig) throws -> GenerationSchema {
        let templates = config.validTemplates
        var dependencies: [String: DynamicGenerationSchema] = [:]
        var cases: [DynamicGenerationSchema] = []
        for (index, template) in templates.enumerated() {
            var properties = [DynamicGenerationSchema.Property(
                name: templateProperty, description: "Template escolhido",
                schema: DynamicGenerationSchema(name: "Template\(index + 1)Phrase", anyOf: [template.phrase]))]
            for field in PhrasePart.fields(in: template.phrase) {
                guard let entity = config.entity(named: field) else { continue }
                let schemaName = entitySchemaName(entity)
                if dependencies[schemaName] == nil {
                    dependencies[schemaName] = DynamicGenerationSchema(
                        name: schemaName, description: "Id de \(entity.name)",
                        anyOf: entity.values.map(\.key).filter { !$0.isEmpty } + [noneChoice])
                }
                properties.append(.init(name: CommandText.foldedName(field), description: entity.name,
                                        schema: DynamicGenerationSchema(referenceTo: schemaName)))
            }
            cases.append(DynamicGenerationSchema(name: "Template\(index + 1)", description: template.phrase, properties: properties))
        }
        cases.append(DynamicGenerationSchema(name: "None", description: "Nenhum template corresponde ao pedido", properties: [
            .init(name: templateProperty, schema: DynamicGenerationSchema(name: "NonePhrase", anyOf: [noneChoice])),
        ]))
        let root = DynamicGenerationSchema(name: "VoiceCommand", description: "Template e valores do comando", anyOf: cases)
        return try GenerationSchema(root: root, dependencies: Array(dependencies.values))
    }

    private static func entitySchemaName(_ entity: CommandEntity) -> String {
        let name = CommandText.tokens(entity.name).map(\.capitalized).joined()
        return "Entity" + (name.isEmpty ? entity.id.uuidString.filter(\.isLetter) : name)
    }

    /// Lists templates and values (with their aliases) so the model can map misheard names.
    static func instructions(for config: VoiceCommandConfig) -> String {
        var lines = [
            "You route a Portuguese voice command to one of the command templates below, or to \"\(noneChoice)\" if none fits.",
            "The command is a speech transcription and often misspells names or splits them into words.",
            "Choose the template and, for each field, the id of the value the user meant (\"\(noneChoice)\" if it wasn't said).",
            "Only choose a template whose fixed words appear in the command. Never choose a value the command doesn't mention; use \"\(noneChoice)\" instead.",
            "",
            "Templates:",
        ]
        lines += config.validTemplates.map { "- \($0.phrase)" }
        for entity in config.entities {
            lines.append("")
            lines.append("Values of <\(entity.name)>:")
            for value in entity.values where !value.key.isEmpty {
                let aliases = value.aliasList.isEmpty ? "" : " (also heard as: \(value.aliasList.joined(separator: ", ")))"
                lines.append("- \(value.key): \(value.label)\(aliases)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Asks the on-device model for the template and values; it only picks from closed lists.
    static func resolveWithModel(_ remainder: String, config: VoiceCommandConfig) async throws -> Resolution {
        guard SystemLanguageModel.default.isAvailable else { throw Failure.modelUnavailable }
        var candidates = config
        candidates.templates = plausibleTemplates(for: remainder, config: config)
        guard !candidates.templates.isEmpty else { throw Failure.notUnderstood }
        let session = LanguageModelSession(instructions: instructions(for: candidates))
        let response = try await session.respond(to: remainder, schema: try schema(for: candidates),
                                                 options: GenerationOptions(samplingMode: .greedy))
        let resolution = try resolution(from: response.content, config: candidates)
        // The model fills every field even when the command doesn't name it ("abre o mix
        // darvin e executa pool" came back with agente = claude), so check each value was said.
        let spoken = CommandText.tokens(remainder)
        for field in PhrasePart.fields(in: resolution.template.phrase) {
            guard let value = resolution.values[CommandText.foldedName(field)], isMentioned(value, in: spoken) else {
                throw Failure.missingField(field)
            }
        }
        return resolution
    }

    /// Whether some word of the value's id, label, aliases or "soa como" is in `spoken`, allowing
    /// a typo per four letters since the transcriber mishears names ("darvin" for "darwin").
    static func isMentioned(_ value: EntityValue, in spoken: [String]) -> Bool {
        let words = Set((forms(of: value) + CommandText.tokens(value.soundsLike).map { [$0] }).joined())
        return words.contains { word in spoken.contains { word == $0 || isClose(word, $0) } }
    }

    /// A typo per four letters; words under three letters must match exactly.
    static func isClose(_ word: String, _ said: String) -> Bool {
        min(word.count, said.count) >= 3 && editDistance(word, said) <= max(1, word.count / 4)
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        var previous = Array(0...b.count)
        for i in 1...a.count {
            var current = [i] + Array(repeating: 0, count: b.count)
            for j in b.indices {
                current[j + 1] = a[i - 1] == b[j]
                    ? previous[j]
                    : 1 + min(previous[j], previous[j + 1], current[j])
            }
            previous = current
        }
        return previous[b.count]
    }

    /// Valid templates with at least half of their fixed words in the text, so the model can't
    /// pick "abre o <agente> no <projeto>" for "abre nix-darwin e roda git pull" (no "o", no
    /// "no") and invent the agent. Half tolerates misheard words ("abra o claude no vox").
    static func plausibleTemplates(for remainder: String, config: VoiceCommandConfig) -> [CommandTemplate] {
        let spoken = CommandText.tokens(remainder)
        return config.validTemplates.filter { template in
            let words = PhrasePart.parse(template.phrase).flatMap { part -> [String] in
                if case .words(let words) = part { words } else { [] }
            }
            guard !words.isEmpty else { return true }
            let said = words.filter { word in spoken.contains { CommandText.sameWord(word, $0) } }
            return said.count * 2 >= words.count
        }
    }

    static func resolution(from content: GeneratedContent, config: VoiceCommandConfig) throws -> Resolution {
        let phrase = try content.value(String.self, forProperty: templateProperty)
        guard let template = config.validTemplates.first(where: { $0.phrase == phrase }) else { throw Failure.notUnderstood }
        var values: [String: EntityValue] = [:]
        for field in PhrasePart.fields(in: template.phrase) {
            let key = CommandText.foldedName(field)
            let id = try content.value(String.self, forProperty: key)
            guard let value = config.entity(named: field)?.values.first(where: { $0.key == id }) else {
                throw Failure.missingField(field)
            }
            values[key] = value
        }
        return Resolution(template: template, values: values)
    }

    // MARK: Training phrases

    /// Each template with its fields filled by every combination of value labels
    /// ("abre o Claude no cognia-labs"), at most `limit` per template.
    static func trainingPhrases(for config: VoiceCommandConfig, limit: Int = 300) -> [String] {
        config.validTemplates.flatMap { template -> [String] in
            var phrases = [""]
            for part in phraseSegments(template.phrase) {
                switch part {
                case .literal(let text):
                    phrases = phrases.map { $0 + text }
                case .field(let name):
                    let labels = (config.entity(named: name)?.values ?? []).map(\.label).filter { !$0.isEmpty }
                    phrases = Array(phrases.lazy.flatMap { phrase in labels.map { phrase + $0 } }.prefix(limit))
                }
            }
            return phrases.map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }.filter { !$0.isEmpty }
        }
    }

    private enum Segment { case literal(String), field(String) }

    /// Like `PhrasePart.parse`, but keeps the literal text as written.
    private static func phraseSegments(_ phrase: String) -> [Segment] {
        var segments: [Segment] = []
        var rest = Substring(phrase)
        while let open = rest.firstIndex(of: "<"), let close = rest[open...].firstIndex(of: ">") {
            segments.append(.literal(String(rest[..<open])))
            segments.append(.field(rest[rest.index(after: open)..<close].trimmingCharacters(in: .whitespaces)))
            rest = rest[rest.index(after: close)...]
        }
        segments.append(.literal(String(rest)))
        return segments
    }
}
