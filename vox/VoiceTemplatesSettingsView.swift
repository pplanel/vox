//
//  VoiceTemplatesSettingsView.swift
//  vox
//
//  Created by Pedro Planel on 03/11/26.
//

import AppKit
import SwiftUI

/// Settings → Comandos de voz: the entities and templates `CommandResolver` interprets, plus
/// a place to try phrases. Settings windows give their toolbar to the tabs, so every pane is
/// a sidebar + detail inside the tab instead of a navigation stack.
struct VoiceTemplatesSettingsView: View {
    enum Pane: Hashable {
        case entities, templates, tryout
    }

    var store = VoiceCommandStore.shared
    @State private var pane = Pane.entities

    var body: some View {
        VStack(spacing: 12) {
            Picker("Seção", selection: $pane) {
                Text("Entidades").tag(Pane.entities)
                Text("Templates").tag(Pane.templates)
                Text("Testar").tag(Pane.tryout)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()

            switch pane {
            case .entities: EntitiesPane(store: store)
            case .templates: TemplatesPane(store: store)
            case .tryout: TryoutPane(store: store)
            }
        }
        .padding()
    }
}

// MARK: - Shared pieces

/// The "+ −" strip under a macOS list, with room for extra controls.
private struct ListActionBar<Extra: View>: View {
    let addLabel: String
    let canRemove: Bool
    let onAdd: () -> Void
    let onRemove: () -> Void
    @ViewBuilder var extra: Extra

    var body: some View {
        HStack(spacing: 8) {
            Button(addLabel, systemImage: "plus", action: onAdd)
                .labelStyle(.iconOnly)
                .help(addLabel)
            Button("Apagar", systemImage: "minus", action: onRemove)
                .labelStyle(.iconOnly)
                .disabled(!canRemove)
                .help("Apagar a seleção")
            extra
            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }
}

extension ListActionBar where Extra == EmptyView {
    init(addLabel: String, canRemove: Bool, onAdd: @escaping () -> Void, onRemove: @escaping () -> Void) {
        self.init(addLabel: addLabel, canRemove: canRemove, onAdd: onAdd, onRemove: onRemove) { EmptyView() }
    }
}

private struct IssueLabel: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
    }
}

// MARK: - Entities

private struct EntitiesPane: View {
    let store: VoiceCommandStore
    @State private var selection: CommandEntity.ID?

    /// Starts on the first entity; setting it in `onAppear` races the list's first update.
    init(store: VoiceCommandStore) {
        self.store = store
        _selection = State(initialValue: store.config.entities.first?.id)
    }
    /// Entity waiting for "Apagar" in the dialog, because templates use it.
    @State private var pendingDeletion: CommandEntity?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                List(selection: $selection) {
                    // Rows stay inline: a custom row view inside this List crashes AppKit's
                    // outline coordinator (ViewListTree.visitItem) on macOS 27.
                    ForEach(store.config.entities) { entity in
                        HStack {
                            Text(entity.name)
                            Spacer()
                            Text(entity.values.count, format: .number)
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.bordered)
                .contextMenu(forSelectionType: CommandEntity.ID.self) { ids in
                    if let id = ids.first, !store.config.isBuiltInEntity(id) {
                        Button("Apagar", role: .destructive) { requestDeletion(of: id) }
                    }
                }
                ListActionBar(addLabel: "Nova entidade",
                              canRemove: selection.map { !store.config.isBuiltInEntity($0) } ?? false) {
                    selection = store.config.addEntity()
                } onRemove: {
                    if let selection { requestDeletion(of: selection) }
                }
            }
            .frame(width: 170)

            if let selection, store.config.entities.contains(where: { $0.id == selection }) {
                EntityDetail(store: store, entityID: selection)
                    // Fresh name field and value selection per entity.
                    .id(selection)
            } else {
                ContentUnavailableView("Nenhuma entidade selecionada", systemImage: "list.bullet.rectangle",
                                       description: Text("Entidades são listas de valores que os campos <> dos templates aceitam."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .confirmationDialog("Apagar “\(pendingDeletion?.name ?? "")”?", isPresented: Binding(
                                get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
                            presenting: pendingDeletion) { entity in
            Button("Apagar", role: .destructive) { delete(entity.id) }
            Button("Cancelar", role: .cancel) { pendingDeletion = nil }
        } message: { entity in
            let phrases = store.config.templates(using: entity.id).map { "“\($0.phrase)”" }
            Text("Estes templates deixam de funcionar até serem corrigidos: \(phrases.formatted(.list(type: .and))).")
        }
    }

    private func requestDeletion(of id: CommandEntity.ID) {
        // `<comando>` and `<tecla>` hold the built-in commands, so they can't go.
        guard let entity = store.config.entities.first(where: { $0.id == id }),
              !store.config.isBuiltInEntity(id) else { return }
        if store.config.templates(using: id).isEmpty {
            delete(id)
        } else {
            pendingDeletion = entity
        }
    }

    private func delete(_ id: CommandEntity.ID) {
        pendingDeletion = nil
        guard let index = store.config.entities.firstIndex(where: { $0.id == id }) else { return }
        // Let a field being edited commit now, while its entity still exists.
        NSApp.keyWindow?.makeFirstResponder(nil)
        store.config.entities.remove(at: index)
        let remaining = store.config.entities
        selection = remaining.indices.contains(index) ? remaining[index].id : remaining.last?.id
    }
}

private struct EntityDetail: View {
    let store: VoiceCommandStore
    let entityID: CommandEntity.ID
    @AppStorage("commandPrefix") private var commandPrefix = "vox"
    @State private var selectedValues: Set<EntityValue.ID>

    /// Starts with the first value selected, so its fields are visible right away.
    init(store: VoiceCommandStore, entityID: CommandEntity.ID) {
        self.store = store
        self.entityID = entityID
        let first = store.config.entities.first { $0.id == entityID }?.values.first?.id
        _selectedValues = State(initialValue: first.map { [$0] } ?? [])
    }

    private var index: Int? { store.config.entities.firstIndex { $0.id == entityID } }
    private var currentEntity: CommandEntity? { index.map { store.config.entities[$0] } }

    /// Bindings go through the id, not an index captured in `body`: a text field that commits
    /// while its entity is being deleted would otherwise write past the end of the array
    /// (crash) or into the entity that took its place. Once the entity is gone this is a no-op.
    private func updateEntity(_ change: (inout CommandEntity) -> Void) {
        guard let index else { return }
        change(&store.config.entities[index])
    }

    var body: some View {
        if let index {
            let entity = store.config.entities[index]
            let isBuiltIn = store.config.isBuiltInEntity(entityID)
            VStack(alignment: .leading, spacing: 10) {
                if isBuiltIn {
                    // Built-in actions: the label and aliases are what you say.
                    VStack(alignment: .leading, spacing: 4) {
                        Text("<\(entity.name)>").font(.body.monospaced())
                        Text(store.config.isAppEntity(entityID)
                             ? "Apps com janela, adicionados ao abrir o Vox e a cada gravação; ficam salvos mesmo fechados, com o “soa como” que você definir. “valor no comando” é o bundle id. O template <\(entity.name)> (Focar app) traz o app para a frente e digita nele."
                             : "Comandos do Vox. Diga “\(commandPrefix) [rótulo ou alias]”; o id escolhe a ação (\(VoiceCommandConfig.commandKeys.joined(separator: ", "))). “\(commandPrefix)” sozinho foca a área de texto do app em uso; “enviar” e “próximo” também valem sem “\(commandPrefix)” ao fim de uma frase digitada.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    EntityNameField(store: store, entityID: entityID, savedName: entity.name)

                    Toggle(isOn: Binding(
                        get: { currentEntity?.insertsRawValue ?? entity.insertsRawValue },
                        set: { newValue in updateEntity { $0.insertsRawValue = newValue } })) {
                        Text("Valor entra como código de shell (sem aspas)")
                        Text(entity.insertsRawValue
                             ? "{\(entity.name)} vira, por exemplo, git pull. Use para comandos; {pedido} continua sempre entre aspas."
                             : "{\(entity.name)} vira um argumento entre aspas, por exemplo '/caminho/com espaço'.")
                    }
                }

                ValuesTable(values: entity.values, selection: $selectedValues) { ids in
                    deleteValues(ids)
                }
                ListActionBar(addLabel: "Novo valor", canRemove: !selectedValues.isEmpty) {
                    let value = EntityValue(key: "", label: "", value: "")
                    updateEntity { $0.values.append(value) }
                    selectedValues = [value.id]
                } onRemove: {
                    deleteValues(selectedValues)
                } extra: {
                    if store.config.isAppEntity(entityID) {
                        Button("Adicionar apps abertos", systemImage: "macwindow.badge.plus") { store.addWindowedApps() }
                            .help("Um valor por app com janela aberta que ainda não está na lista")
                    }
                    if !isBuiltIn {
                        Button("Preencher com subpastas…", systemImage: "folder.badge.plus") { chooseFolder() }
                            .help("Um valor por subpasta: id e rótulo são o nome, o valor é o caminho")
                    }
                    Spacer()
                    Text(entity.values.count == 1 ? "1 valor" : "\(entity.values.count) valores")
                        .foregroundStyle(.secondary)
                }

                if selectedValues.count == 1, let valueIndex = entity.values.firstIndex(where: { selectedValues.contains($0.id) }) {
                    let value = entity.values[valueIndex]
                    ValueInspector(value: Binding(
                        get: { currentEntity?.values.first { $0.id == value.id } ?? value },
                        set: { edited in
                            updateEntity { entity in
                                guard let i = entity.values.firstIndex(where: { $0.id == value.id }) else { return }
                                entity.values[i] = edited
                            }
                        }
                    ), issue: store.config.valueIssue(value, in: entityID))
                } else {
                    Text(selectedValues.isEmpty ? "Selecione um valor para editar." : "\(selectedValues.count) valores selecionados.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
            }
        }
    }

    private func deleteValues(_ ids: Set<EntityValue.ID>) {
        updateEntity { $0.values.removeAll { ids.contains($0.id) } }
        selectedValues.subtract(ids)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Usar subpastas"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        let paths = folders
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.path)
        store.addSubfolders(paths, toEntity: entityID)
    }
}

/// Commits on Return or when focus leaves, so templates are renamed once with a valid name,
/// not on every keystroke.
private struct EntityNameField: View {
    let store: VoiceCommandStore
    let entityID: CommandEntity.ID
    let savedName: String
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var issue: String? {
        text == savedName ? nil : store.config.nameIssue(text, for: entityID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("<").foregroundStyle(.secondary)
                TextField("Nome", text: $text, prompt: Text("projeto"))
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .focused($isFocused)
                    .onSubmit(commit)
                    .frame(maxWidth: 220)
                Text(">").foregroundStyle(.secondary)
                if text != savedName && issue == nil {
                    Button("Renomear", action: commit)
                        .controlSize(.small)
                }
            }
            if let issue {
                IssueLabel(message: issue)
            } else {
                Text("Renomear atualiza os templates que usam esta entidade.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { text = savedName }
        .onChange(of: isFocused) { _, focused in
            if !focused { commit() }
        }
    }

    private func commit() {
        guard text != savedName else { return }
        if issue == nil {
            store.config.renameEntity(entityID, to: text)
        } else if !isFocused {
            text = savedName
        }
    }
}

private struct ValuesTable: View {
    let values: [EntityValue]
    @Binding var selection: Set<EntityValue.ID>
    let onDelete: (Set<EntityValue.ID>) -> Void

    var body: some View {
        Table(values, selection: $selection) {
            TableColumn("Rótulo") { value in
                Text(value.label.isEmpty ? "—" : value.label)
            }
            TableColumn("Id") { value in
                Text(value.key.isEmpty ? "—" : value.key)
                    .font(.body.monospaced())
            }
            TableColumn("Valor no comando") { value in
                Text(value.value)
                    .font(.body.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(value.value)
            }
        }
        .tableStyle(.bordered)
        .alternatingRowBackgrounds()
        .contextMenu(forSelectionType: EntityValue.ID.self) { ids in
            if !ids.isEmpty {
                Button(ids.count == 1 ? "Apagar valor" : "Apagar \(ids.count) valores", role: .destructive) { onDelete(ids) }
            }
        }
        .onDeleteCommand { onDelete(selection) }
        .frame(minHeight: 130)
    }
}

private struct ValueInspector: View {
    @Binding var value: EntityValue
    let issue: String?

    var body: some View {
        Form {
            TextField("Rótulo:", text: $value.label, prompt: Text("Claude"))
            TextField("Id:", text: $value.key, prompt: Text("claude"))
            TextField("Valor no comando:", text: $value.value, prompt: Text("claude"))
            TextField("Aliases:", text: $value.aliases, prompt: Text("cláudio, clode"))
            TextField("Soa como:", text: $value.soundsLike, prompt: Text("clód, clódi"))
            LabeledContent("X-SAMPA:") {
                PronunciationPreview(soundsLike: value.soundsLike)
            }
            if let issue {
                LabeledContent("") { IssueLabel(message: issue) }
            }
        }
        .formStyle(.columns)
        .textFieldStyle(.roundedBorder)
    }
}

private struct PronunciationPreview: View {
    let soundsLike: String

    var body: some View {
        let phonemes = SoundsLike.pronunciations(soundsLike)
        Text(phonemes.isEmpty ? "—" : phonemes.joined(separator: "  ·  "))
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }
}

// MARK: - Templates

private struct TemplatesPane: View {
    let store: VoiceCommandStore
    @State private var selection: CommandTemplate.ID?

    init(store: VoiceCommandStore) {
        self.store = store
        _selection = State(initialValue: store.config.templates.first?.id)
    }
    /// Unsaved edits per template, including templates that were never saved.
    @State private var drafts: [CommandTemplate.ID: CommandTemplate] = [:]
    /// New templates in creation order; they only reach the store when saved.
    @State private var newIDs: [CommandTemplate.ID] = []

    /// Saved templates (with their drafts applied) followed by the new ones.
    private var rows: [CommandTemplate] {
        store.config.templates.map { drafts[$0.id] ?? $0 } + newIDs.compactMap { drafts[$0] }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                let entities = store.config.entities
                List(selection: $selection) {
                    // Inline for the same reason as the entity rows.
                    ForEach(rows) { template in
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(template.phrase.isEmpty ? "Novo template" : template.phrase)
                                    .foregroundStyle(template.phrase.isEmpty ? .secondary : .primary)
                                    .lineLimit(1)
                                Text(template.target.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if drafts[template.id] != nil {
                                Circle().fill(.tint).frame(width: 6, height: 6).help("Alterações não salvas")
                            }
                            if !TemplateValidator.issues(in: template, entities: entities).isEmpty {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .help("Template inválido: é ignorado até ser corrigido")
                            }
                        }
                    }
                }
                .listStyle(.bordered)
                .contextMenu(forSelectionType: CommandTemplate.ID.self) { ids in
                    if let id = ids.first {
                        Button("Duplicar") { duplicate(id) }
                        Button("Apagar", role: .destructive) { delete(id) }
                    }
                }
                ListActionBar(addLabel: "Novo template", canRemove: selection != nil) {
                    let template = CommandTemplate(phrase: "", command: "")
                    drafts[template.id] = template
                    newIDs.append(template.id)
                    selection = template.id
                } onRemove: {
                    if let selection { delete(selection) }
                } extra: {
                    Button("Duplicar", systemImage: "plus.square.on.square") {
                        if let selection { duplicate(selection) }
                    }
                    .labelStyle(.iconOnly)
                    .disabled(selection == nil)
                    .help("Duplicar o template")
                }
            }
            .frame(width: 210)

            if let selection, let saved = rows.first(where: { $0.id == selection }) {
                TemplateDetail(
                    template: Binding(
                        get: { drafts[selection] ?? saved },
                        set: { edited in
                            let stored = store.config.templates.first { $0.id == selection }
                            drafts[selection] = edited == stored ? nil : edited
                        }),
                    config: store.config,
                    isNew: newIDs.contains(selection),
                    isDirty: drafts[selection] != nil,
                    onSave: { save(selection) },
                    onRevert: { revert(selection) })
            } else {
                ContentUnavailableView("Nenhum template selecionado", systemImage: "text.bubble",
                                       description: Text("Um template liga uma frase falada a um comando de shell."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func save(_ id: CommandTemplate.ID) {
        guard let draft = drafts[id], TemplateValidator.issues(in: draft, entities: store.config.entities).isEmpty else { return }
        store.config.upsert(draft)
        drafts[id] = nil
        newIDs.removeAll { $0 == id }
    }

    /// Drops the edits; a template that was never saved disappears.
    private func revert(_ id: CommandTemplate.ID) {
        drafts[id] = nil
        if newIDs.contains(id) {
            newIDs.removeAll { $0 == id }
            selection = rows.last?.id
        }
    }

    private func delete(_ id: CommandTemplate.ID) {
        let index = rows.firstIndex { $0.id == id }
        drafts[id] = nil
        newIDs.removeAll { $0 == id }
        store.config.templates.removeAll { $0.id == id }
        let remaining = rows
        selection = index.flatMap { remaining.indices.contains($0) ? remaining[$0].id : remaining.last?.id }
    }

    /// The copy starts as an unsaved draft, so it can be tweaked before it's saved.
    private func duplicate(_ id: CommandTemplate.ID) {
        guard var copy = rows.first(where: { $0.id == id }) else { return }
        copy.id = UUID()
        drafts[copy.id] = copy
        newIDs.append(copy.id)
        selection = copy.id
    }
}

private struct TemplateDetail: View {
    @Binding var template: CommandTemplate
    let config: VoiceCommandConfig
    let isNew: Bool
    let isDirty: Bool
    let onSave: () -> Void
    let onRevert: () -> Void

    var body: some View {
        let issues = TemplateValidator.issues(in: template, entities: config.entities)
        VStack(alignment: .leading, spacing: 12) {
            Form {
                LabeledContent("Frase:") {
                    HStack {
                        TextField("Frase", text: $template.phrase, prompt: Text("abre o <agente> no <projeto>"))
                            .labelsHidden()
                        Menu("Campo", systemImage: "chevron.left.forwardslash.chevron.right") {
                            ForEach(config.entities) { entity in
                                Button("<\(entity.name)>") { template.phrase = appending("<\(entity.name)>", to: template.phrase) }
                            }
                        }
                        .menuStyle(.button)
                        .buttonStyle(.borderless)
                        .labelStyle(.iconOnly)
                        .fixedSize()
                        .help("Inserir um campo de entidade")
                    }
                }
                LabeledContent("Comando:") {
                    HStack(alignment: .top) {
                        TextField("Comando", text: $template.command, prompt: Text("cd {projeto} && {agente} {pedido}"), axis: .vertical)
                            .labelsHidden()
                            .font(.body.monospaced())
                            .lineLimit(2...4)
                        Menu("Placeholder", systemImage: "curlybraces") {
                            ForEach(PhrasePart.fields(in: template.phrase), id: \.self) { field in
                                Button("{\(field)}") { template.command = appending("{\(field)}", to: template.command) }
                            }
                            Divider()
                            Button("{pedido} — texto transcrito") { template.command = appending("{pedido}", to: template.command) }
                        }
                        .menuStyle(.button)
                        .buttonStyle(.borderless)
                        .labelStyle(.iconOnly)
                        .fixedSize()
                        .help("Inserir um placeholder")
                    }
                }
                Picker("Onde roda:", selection: $template.target) {
                    ForEach(CommandTemplate.Target.allCases, id: \.self) { target in
                        Text(target.displayName).tag(target)
                    }
                }
                .pickerStyle(.radioGroup)
            }
            .formStyle(.columns)
            .textFieldStyle(.roundedBorder)

            if issues.isEmpty {
                TemplatePreview(template: template, config: config)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(issues, id: \.self) { IssueLabel(message: $0.message) }
                }
            }

            Spacer(minLength: 0)

            HStack {
                Text(template.target == .keys
                     ? "O comando são teclas separadas por espaço, por exemplo \(KeySequence.examples); {campo} vira as teclas do valor escolhido."
                     : template.target.asksConfirmation
                     ? "Placeholders viram o valor escolhido entre aspas de shell; {pedido} é o texto transcrito."
                     : "Placeholders viram o valor escolhido, sem aspas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(isNew ? "Descartar" : "Reverter", action: onRevert)
                    .disabled(!isDirty)
                Button("Salvar", action: onSave)
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isDirty || !issues.isEmpty)
            }
        }
    }

    /// Adds a token with a separating space, as if typed at the end.
    private func appending(_ token: String, to text: String) -> String {
        text.isEmpty || text.hasSuffix(" ") ? text + token : text + " " + token
    }
}

/// What saying the template with the first value of each field would run.
private struct TemplatePreview: View {
    let template: CommandTemplate
    let config: VoiceCommandConfig
    @AppStorage("commandPrefix") private var commandPrefix = "vox"

    var body: some View {
        let example = Self.example(for: template, config: config)
        GroupBox("Exemplo") {
            VStack(alignment: .leading, spacing: 6) {
                if let example {
                    LabeledContent("Diga") { Text("\(commandPrefix) \(example.request)").textSelection(.enabled) }
                    LabeledContent("Roda") {
                        Text(example.command)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    }
                } else {
                    Text("Adicione valores às entidades dos campos para ver um exemplo.")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    static func example(for template: CommandTemplate, config: VoiceCommandConfig) -> PreparedCommand? {
        var values: [String: EntityValue] = [:]
        var spoken = template.phrase
        for field in PhrasePart.fields(in: template.phrase) {
            guard let value = config.entity(named: field)?.values.first(where: { !$0.key.isEmpty }) else { return nil }
            values[CommandText.foldedName(field)] = value
            spoken = spoken.replacingOccurrences(of: "<\(field)>", with: value.label)
        }
        return PreparedCommand(template: template, values: values, transcript: spoken, entities: config.entities)
    }
}

// MARK: - Try out

/// Types a phrase as if spoken after the wake word and shows what would run.
private struct TryoutPane: View {
    let store: VoiceCommandStore
    @State private var phrase = ""
    @State private var modelResult: Result<PreparedCommand, any Error>?
    @State private var isAskingModel = false
    @AppStorage("commandPrefix") private var commandPrefix = "vox"

    var body: some View {
        let config = store.config
        Form {
            // Label in the header: beside it the Form right-aligns the field, which hides a
            // trailing space while typing and cuts long phrases.
            Section {
                TextField("Frase", text: $phrase, prompt: Text("abre o cláudio no nix darwin e pede pra rodar os testes"),
                          axis: .vertical)
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
                    .onChange(of: phrase) { modelResult = nil }
            } header: {
                Text("Depois de “\(commandPrefix)”")
            } footer: {
                Text("Nada é executado aqui.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !phrase.trimmingCharacters(in: .whitespaces).isEmpty {
                Section("Pelos aliases (sem o modelo)") {
                    if !CommandResolver.isRequest(phrase, config: config) {
                        Text("Não começa como nenhum template: vira ditado.")
                            .foregroundStyle(.secondary)
                    } else if let resolution = CommandResolver.resolveWithAliases(phrase, config: config) {
                        ResolutionView(prepared: PreparedCommand(template: resolution.template, values: resolution.values,
                                                                 transcript: phrase, entities: config.entities))
                    } else {
                        Text("Os aliases não bastam: o modelo decide.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Pelo modelo") {
                    switch modelResult {
                    case .success(let prepared):
                        ResolutionView(prepared: prepared)
                    case .failure(let error):
                        IssueLabel(message: error.localizedDescription)
                    case nil:
                        EmptyView()
                    }
                    Button(isAskingModel ? "Perguntando…" : "Perguntar ao modelo") { askModel(config) }
                        .disabled(isAskingModel)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func askModel(_ config: VoiceCommandConfig) {
        isAskingModel = true
        let phrase = phrase
        Task {
            defer { isAskingModel = false }
            do {
                let resolution = try await CommandResolver.resolveWithModel(phrase, config: config)
                modelResult = .success(PreparedCommand(template: resolution.template, values: resolution.values,
                                                       transcript: phrase, entities: config.entities))
            } catch {
                modelResult = .failure(error)
            }
        }
    }
}

private struct ResolutionView: View {
    let prepared: PreparedCommand

    var body: some View {
        LabeledContent("Template", value: prepared.template.phrase)
        LabeledContent("Valores", value: prepared.title)
        LabeledContent("Onde roda", value: prepared.template.target.displayName)
        LabeledContent("Comando") {
            Text(prepared.command)
                .font(.callout.monospaced())
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
    }
}

#Preview {
    VoiceTemplatesSettingsView(store: VoiceCommandStore(url: nil))
        .frame(width: 760, height: 600)
}

#Preview("Templates") {
    TemplatesPane(store: VoiceCommandStore(url: nil))
        .padding()
        .frame(width: 760, height: 560)
}

#Preview("Testar") {
    TryoutPane(store: VoiceCommandStore(url: nil))
        .frame(width: 760, height: 560)
}
