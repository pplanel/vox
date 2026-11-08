//
//  VoiceCommandTests.swift
//  voxTests
//
//  Created by Pedro Planel on 03/11/26.
//

import CoreGraphics
import Foundation
import FoundationModels
import Testing
@testable import vox

struct VoiceCommandTests {
    private let claude = EntityValue(key: "claude", label: "Claude", aliases: "cláudio, claudio, clode",
                                     value: "claude", soundsLike: "clód, clódi")
    private let pi = EntityValue(key: "pi", label: "Pi", aliases: "pie", value: "pi")
    private let cogniaLabs = EntityValue(key: "cognia-labs", label: "cognia-labs", value: "/Users/pplanel/src/pplanel/cognia-labs")
    private let cognia = EntityValue(key: "cognia", label: "cognia", value: "/Users/pplanel/src/pplanel/cognia")
    private let nixDarwin = EntityValue(key: "nix-darwin", label: "nix-darwin", value: "/Users/pplanel/.config/nix-darwin")
    private let vox = EntityValue(key: "vox", label: "vox", value: "/Users/pplanel/src/pplanel/vox")
    private let liet = EntityValue(key: "liet", label: "Liet", aliases: "liete, lieti", value: "liet", soundsLike: "liéti")

    private let launch = CommandTemplate(phrase: "abre o <agente> no <projeto>", command: "cd {projeto} && {agente} {pedido}")

    private var config: VoiceCommandConfig {
        VoiceCommandConfig(entities: [
            CommandEntity(name: "agente", values: [claude, pi]),
            CommandEntity(name: "projeto", values: [cogniaLabs, nixDarwin, vox]),
            CommandEntity(name: "nome", values: [liet]),
        ], templates: [launch])
    }

    // MARK: Schema

    @Test func schemaHasOneCasePerTemplateWithClosedChoices() throws {
        var config = config
        config.templates.append(CommandTemplate(phrase: "roda os testes do <projeto>", command: "cd {projeto} && make test",
                                                target: .background))
        // An invalid template gets no case.
        config.templates.append(CommandTemplate(phrase: "liga a <luz>", command: "true"))

        let schema = try CommandResolver.schema(for: config)
        let json = try #require(String(data: JSONEncoder().encode(schema), encoding: .utf8))

        #expect(json.contains("abre o <agente> no <projeto>"))
        #expect(json.contains("roda os testes do <projeto>"))
        #expect(!json.contains("liga a <luz>"))
        #expect(json.contains(CommandResolver.noneChoice))
        for id in ["claude", "pi", "cognia-labs", "nix-darwin", "vox"] {
            #expect(json.contains("\"\(id)\""))
        }
        // One case per valid template plus "nenhum", and only closed lists: every string is an enum.
        let root = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect((root["anyOf"] as? [Any])?.count == 3)
        var strings: [[String: Any]] = []
        func collect(_ node: Any) {
            if let object = node as? [String: Any] {
                if object["type"] as? String == "string" { strings.append(object) }
                object.values.forEach(collect)
            } else if let array = node as? [Any] {
                array.forEach(collect)
            }
        }
        collect(root)
        #expect(!strings.isEmpty)
        #expect(strings.allSatisfy { $0["enum"] is [String] })
        let agent = strings.first { $0["description"] as? String == "agente" }
        #expect(agent?["enum"] as? [String] == ["claude", "pi", CommandResolver.noneChoice])
    }

    @Test func instructionsListValuesAndAliases() {
        let instructions = CommandResolver.instructions(for: config)
        #expect(instructions.contains("- abre o <agente> no <projeto>"))
        #expect(instructions.contains("- claude: Claude (also heard as: cláudio, claudio, clode)"))
        #expect(instructions.contains("- nix-darwin: nix-darwin"))
    }

    @Test func modelResponseMapsToValues() throws {
        let content = GeneratedContent(properties: ["template": launch.phrase, "agente": "pi", "projeto": "vox"])
        let resolution = try CommandResolver.resolution(from: content, config: config)
        #expect(resolution.template == launch)
        #expect(resolution.values == ["agente": pi, "projeto": vox])

        let none = GeneratedContent(properties: ["template": CommandResolver.noneChoice])
        #expect(throws: CommandResolver.Failure.self) { try CommandResolver.resolution(from: none, config: config) }
    }

    // MARK: Validation

    @Test func validTemplateHasNoIssues() {
        #expect(TemplateValidator.issues(in: launch, entities: config.entities).isEmpty)
    }

    @Test func fieldWithoutEntity() {
        let template = CommandTemplate(phrase: "abre o <agente> no <pasta>", command: "cd {pasta} && {agente}")
        #expect(TemplateValidator.issues(in: template, entities: config.entities) == [.unknownEntity("pasta")])
    }

    @Test func placeholderWithoutField() {
        let template = CommandTemplate(phrase: "abre o <agente>", command: "cd {projeto} && {agente} {pedido}")
        #expect(TemplateValidator.issues(in: template, entities: config.entities) == [.unknownPlaceholder("projeto")])
    }

    @Test func shellVariablesAndRepeatedFields() {
        let shellVariable = CommandTemplate(phrase: "abre o <agente>", command: "cd ${HOME} && {agente}")
        #expect(TemplateValidator.issues(in: shellVariable, entities: config.entities).isEmpty)

        let repeated = CommandTemplate(phrase: "<agente> e <agente>", command: "{agente}")
        #expect(TemplateValidator.issues(in: repeated, entities: config.entities) == [.duplicateField("agente")])


        let empty = CommandTemplate(phrase: " ", command: "")
        #expect(TemplateValidator.issues(in: empty, entities: config.entities) == [.emptyPhrase, .emptyCommand])
    }

    // MARK: Escaping

    @Test("Values are quoted, never concatenated", arguments: [
        ("com espaço", "'com espaço'"),
        ("it's", "'it'\\''s'"),
        ("a; rm -rf ~", "'a; rm -rf ~'"),
        ("$(whoami)", "'$(whoami)'"),
        ("`id` && \"x\"", "'`id` && \"x\"'"),
    ])
    func quoting(_ value: String, expected: String) {
        #expect(ShellCommand.quote(value) == expected)
        #expect(ShellCommand.render("echo {pedido}", values: ["pedido": value]) == "echo \(expected)")
    }

    @Test func renderIsSinglePass() {
        let command = ShellCommand.render("cd {projeto} && {agente} {pedido} ${HOME}",
                                          values: ["projeto": "/tmp/a b", "agente": "{pedido}", "pedido": "oi"])
        #expect(command == "cd '/tmp/a b' && '{pedido}' 'oi' ${HOME}")
    }

    @Test func preparedCommand() {
        let prepared = PreparedCommand(template: launch, values: ["agente": claude, "projeto": cogniaLabs],
                                       transcript: "abre o Cláudio no cognia e pede pra liete resolver o agá gê erre duzentos e dezessete.",
                                       entities: config.entities)
        #expect(prepared.issueID == "HGR-217")
        #expect(prepared.request == "abre o Claude no cognia e pede pra Liet resolver o HGR-217")
        #expect(prepared.command == "cd '/Users/pplanel/src/pplanel/cognia-labs' && 'claude' 'abre o Claude no cognia e pede pra Liet resolver o HGR-217'")
        #expect(prepared.title == "Claude · cognia-labs")
        #expect(prepared.confirmation == "Rodar (HGR-217): \(prepared.command)?")
    }

    @Test func paneFocusUsesTheRawProgramName() throws {
        var config = config
        let focus = CommandTemplate(phrase: "<agente>", command: "{agente}", target: .tmuxPane)
        config.templates.append(focus)
        let resolution = try #require(CommandResolver.resolveWithAliases("Cláudio.", config: config))
        #expect(resolution.template == focus)
        let prepared = PreparedCommand(template: focus, values: resolution.values, transcript: "Cláudio.", entities: config.entities)
        #expect(prepared.command == "claude")
        #expect(TmuxNavigator.Program(displayName: prepared.title, command: prepared.command).names == ["claude", ".claude-wrapped"])
    }

    // MARK: Reported bugs

    private var gitConfig: VoiceCommandConfig {
        VoiceCommandConfig(entities: [
            CommandEntity(name: "agente", values: [claude]),
            CommandEntity(name: "projeto", values: [nixDarwin]),
            CommandEntity(name: "comando", values: [
                EntityValue(key: "gp", label: "git pull", aliases: "git", value: "git pull", soundsLike: "git pul"),
            ], insertsRawValue: true),
        ], templates: [launch, CommandTemplate(phrase: "abre <projeto> e roda <comando>", command: "cd {projeto}; {comando}")])
    }

    /// Alias "git" inside label "git pull" used to turn it into "git pull pull".
    @Test func aliasInsideLabelIsKept() {
        let entities = gitConfig.entities
        #expect(AliasCorrection.apply(entities, to: "roda git pull") == "roda git pull")
        #expect(AliasCorrection.apply(entities, to: "roda git") == "roda git pull")
        #expect(AliasCorrection.apply(entities, to: "abre o cláudio") == "abre o Claude")
    }

    /// Command values were quoted into one word ('git pull'); {pedido} must stay quoted.
    @Test func rawEntityValuesAreNotQuoted() throws {
        let config = gitConfig
        
        let resolution = try #require(CommandResolver.resolveWithAliases("abre nix darwin e roda git pull", config: config))
        let prepared = PreparedCommand(template: resolution.template, values: resolution.values,
                                       transcript: "abre nix darwin e roda git pull", entities: config.entities)
        #expect(prepared.command == "cd '/Users/pplanel/.config/nix-darwin'; git pull")

        var withRequest = config
        withRequest.templates[1].command = "cd {projeto}; {comando} && echo {pedido}"
        let echoed = PreparedCommand(template: withRequest.templates[1], values: resolution.values,
                                     transcript: "abre nix darwin e roda git pull; rm -rf ~", entities: withRequest.entities)
        #expect(echoed.command.hasSuffix("&& echo 'abre nix darwin e roda git pull; rm -rf ~'"))
    }

    /// The model picked "abre o <agente> no <projeto>" (and invented the agent) for a phrase
    /// without "o" and "no".
    @Test func modelOnlySeesPlausibleTemplates() {
        let config = gitConfig
        #expect(CommandResolver.plausibleTemplates(for: "abre nix-darwin e roda git pull", config: config).map(\.phrase)
                == ["abre <projeto> e roda <comando>"])
        // Misheard words still leave the template in.
        #expect(CommandResolver.plausibleTemplates(for: "abra o cloud no vox", config: config).map(\.phrase)
                == ["abre o <agente> no <projeto>"])
    }

    /// "abre o mix Darvin e executa pool" passed the filter and the model ran claude, never said.
    @Test func modelValuesMustBeMentioned() {
        let spoken = CommandText.tokens("abre o mix Darvin e executa pool")
        #expect(!CommandResolver.isMentioned(claude, in: spoken))
        #expect(CommandResolver.isMentioned(nixDarwin, in: spoken))
        // Aliases and "soa como" count, and short words need an exact match.
        #expect(CommandResolver.isMentioned(claude, in: CommandText.tokens("abre o clódi no vox")))
        #expect(!CommandResolver.isMentioned(pi, in: CommandText.tokens("abre o vox")))
    }

    /// "abre o mix Darwin e roda o git pull" went to the model: the articles aren't in the
    /// phrase and "roda" isn't "rodar".
    @Test func articlesAndTyposStillResolveWithoutModel() throws {
        var config = gitConfig
        config.entities[1].values[0].aliases = "nix darvin, mix Darwin"
        let rodar = EntityValue(key: "executar", label: "executar", aliases: "rodar, executar", value: "executar")
        config.entities.append(CommandEntity(name: "verbo", values: [rodar]))
        config.templates[1] = CommandTemplate(phrase: "abre <projeto> e <verbo>  <comando>", command: "cd {projeto}; {comando}")

        let resolution = try #require(CommandResolver.resolveWithAliases("abre o mix Darwin e roda o git pull", config: config))
        #expect(resolution.template == config.templates[1])
        #expect(resolution.values == ["projeto": config.entities[1].values[0], "verbo": rodar,
                                      "comando": config.entities[2].values[0]])
    }

    /// "Vox abrir nix-darwin e rodar git pull" wasn't a request: the phrase says "abre".
    @Test func verbFormsStillResolve() throws {
        var config = gitConfig
        let rodar = EntityValue(key: "executar", label: "executar", aliases: "rodar, executar", value: "executar")
        config.entities.append(CommandEntity(name: "verbo", values: [rodar]))
        config.templates[1] = CommandTemplate(phrase: "abre <projeto> e <verbo>  <comando>", command: "cd {projeto}; {comando}")

        let phrase = "abrir nix-darwin e rodar git pull"
        #expect(CommandResolver.isRequest(phrase, config: config))
        #expect(CommandResolver.plausibleTemplates(for: phrase, config: config).map(\.phrase).contains(config.templates[1].phrase))
        let resolution = try #require(CommandResolver.resolveWithAliases(phrase, config: config))
        #expect(resolution.template == config.templates[1])
        #expect(resolution.values["projeto"] == nixDarwin)
    }

    @Test("Verb forms", arguments: [
        ("abre", "abrir", true), ("abre", "abra", true), ("roda", "rodar", true), ("executa", "executar", true),
        ("abre", "abreviar", false), ("no", "na", false), ("abre", "roda", false),
    ])
    func verbForms(_ a: String, _ b: String, expected: Bool) {
        #expect(CommandText.sameWord(a, b) == expected)
    }

    /// An exact value beats a close one instead of tying and going to the model.
    @Test func exactValueBeatsTypo() {
        var config = config
        config.entities[1].values.append(EntityValue(key: "fox", label: "fox", value: "/tmp/fox"))
        #expect(CommandResolver.resolveWithAliases("abre o claude no vox", config: config)?.values["projeto"] == vox)
    }

    @Test func olderJSONWithoutNewFieldsStillDecodes() throws {
        let json = #"{"entities":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"agente","values":[]}],"templates":[]}"#
        let config = try JSONDecoder().decode(VoiceCommandConfig.self, from: Data(json.utf8))
        #expect(config.entities.first?.insertsRawValue == false)
    }

    // MARK: Alias resolution

    @Test func resolvesByAliasWithoutModel() throws {
        let resolution = try #require(CommandResolver.resolveWithAliases("Abre o cláudio no nix darwin.", config: config))
        #expect(resolution.template == launch)
        #expect(resolution.values == ["agente": claude, "projeto": nixDarwin])
    }

    @Test func trailingRequestDoesNotPickAValue() {
        // "cognia" isn't a value; "vox" later in the request must not be taken as the project.
        #expect(CommandResolver.resolveWithAliases("abre o claude no cognia e pede pra revisar o vox", config: config) == nil)
        let resolution = CommandResolver.resolveWithAliases("abre o pi no vox e pede pra revisar o claude", config: config)
        #expect(resolution?.values == ["agente": pi, "projeto": vox])
    }

    @Test func longestValueWinsAndTiesGoToModel() {
        var config = config
        config.entities[1].values.append(cognia)
        let resolution = CommandResolver.resolveWithAliases("abre o claude no cognia labs", config: config)
        #expect(resolution?.values["projeto"] == cogniaLabs)

        // Two values claiming the same alias: ambiguous, so the model decides.
        config.entities[0].values.append(EntityValue(key: "claude-personal", label: "Claude pessoal", aliases: "clode", value: "claude-personal"))
        #expect(CommandResolver.resolveWithAliases("abre o clode no vox", config: config) == nil)
    }

    @Test("Requests", arguments: [
        ("abre o claude no cognia", true),
        (" Abre o pi no vox", true),
        ("abreviar o texto", false),
        ("copiar", false),
    ])
    func isRequest(_ remainder: String, expected: Bool) {
        #expect(CommandResolver.isRequest(remainder, config: config) == expected)
    }

    // MARK: Editing

    @Test func renamingAnEntityUpdatesTemplates() {
        var config = config
        config.templates.append(CommandTemplate(phrase: "testa o <Projeto>", command: "cd {projeto} && echo ${HOME} {projeto}"))
        let id = config.entities[1].id
        config.renameEntity(id, to: "repo")
        #expect(config.entities[1].name == "repo")
        #expect(config.templates[0].phrase == "abre o <agente> no <repo>")
        #expect(config.templates[0].command == "cd {repo} && {agente} {pedido}")
        #expect(config.templates[1].command == "cd {repo} && echo ${HOME} {repo}")
        #expect(config.validTemplates.count == 2)

        // An invalid name changes nothing.
        config.renameEntity(id, to: "agente")
        #expect(config.entities[1].name == "repo")
    }

    @Test("Entity names", arguments: [
        ("", true), ("agente", true), ("Agente", true), ("pedido", true), ("meu projeto", true), ("<x>", true),
        ("projeto", false), ("repo_2", false), ("ação", false),
    ])
    func entityNames(_ name: String, rejected: Bool) {
        let config = config
        #expect((config.nameIssue(name, for: config.entities[1].id) != nil) == rejected)
    }

    @Test func addingDeletingAndUpserting() {
        var config = config
        let first = config.addEntity()
        let second = config.addEntity()
        #expect(config.entities.suffix(2).map(\.name) == ["entidade", "entidade2"])
        #expect(first != second)

        #expect(config.templates(using: config.entities[1].id) == [launch])
        #expect(config.templates(using: first).isEmpty)

        var edited = launch
        edited.target = .background
        config.upsert(edited)
        #expect(config.templates == [edited])
        let new = CommandTemplate(phrase: "<agente>", command: "{agente}", target: .tmuxPane)
        config.upsert(new)
        #expect(config.templates == [edited, new])
    }

    @Test func valueIssues() {
        var config = config
        let agents = config.entities[0].id
        #expect(config.valueIssue(claude, in: agents) == nil)
        config.entities[0].values.append(EntityValue(key: "claude", label: "Outro", value: "x"))
        #expect(config.valueIssue(config.entities[0].values.last!, in: agents) != nil)
        #expect(config.valueIssue(EntityValue(key: " ", label: "", value: ""), in: agents) != nil)
    }

    // MARK: Vocabulary

    @Test func trainingPhrasesExpandTemplates() {
        let phrases = CommandResolver.trainingPhrases(for: config)
        #expect(phrases.count == 6)
        #expect(phrases.contains("abre o Claude no cognia-labs"))
        #expect(phrases.contains("abre o Pi no nix-darwin"))
    }

    @MainActor
    @Test func vocabularyComesFromEntities() {
        let (terms, phrases) = CustomVocabulary.vocabulary(for: "pt", config: config)
        #expect(terms.map(\.grapheme) == ["Claude", "Liet"])
        #expect(terms.first?.phonemes == ["k l \"O d", "k l \"O dZ i"])
        #expect(phrases.contains("Claude"))
        #expect(phrases.contains("abre o Claude no cognia-labs"))
        #expect(phrases.contains("sim"))
        #expect(CustomVocabulary.vocabulary(for: "en", config: config).terms.map(\.grapheme) == ["Vox", "Claude", "Pi"])
    }

    // MARK: Execution

    @Test func tmuxNewWindowPassesCommandToShell() {
        let arguments = TmuxNavigator.newWindowArguments(named: "Claude · cognia-labs", running: "cd '/a b' && 'claude'")
        #expect(arguments == ["new-window", "-P", "-F", "#{pane_id}", "-n", "Claude · cognia-labs", "--",
                              "cd '/a b' && 'claude'; exec \"${SHELL:-/bin/sh}\""])
    }

    @MainActor
    @Test("Confirmation replies", arguments: [
        (" sim.", BuiltInCommand.confirm),
        ("Sim!", .confirm),
        (" Sin", .confirm),
        (" não.", .cancel),
        ("cancelar", .cancel),
    ])
    func replies(_ phrase: String, expected: BuiltInCommand) {
        #expect(VoiceCommandRouter.command(for: phrase, config: VoiceCommandStore.defaultConfig) == expected)
    }

    @MainActor
    @Test("Built-in commands from <comando>", arguments: [
        (" copiar.", BuiltInCommand.copy),
        ("Novo parágrafo", .newParagraph),
        ("nova linha", .newParagraph),
        ("Próxima!", .next),
        (" ", .focus),
    ])
    func builtInCommands(_ phrase: String, expected: BuiltInCommand) {
        #expect(VoiceCommandRouter.command(for: phrase, config: VoiceCommandStore.defaultConfig) == expected)
    }

    @MainActor
    @Test func editedCommandEntityChangesPhrases() {
        var config = VoiceCommandStore.defaultConfig
        let index = config.entities.firstIndex { $0.name == VoiceCommandConfig.commandEntityName }!
        let copy = config.entities[index].values.firstIndex { $0.key == "copiar" }!
        config.entities[index].values[copy].aliases = "copia aí"
        #expect(VoiceCommandRouter.command(for: "copia aí", config: config) == .copy)
        config.entities[index].values.remove(at: copy)
        #expect(VoiceCommandRouter.command(for: "copiar", config: config) == nil)
    }

    @MainActor
    @Test func olderConfigsGetTheBuiltIns() {
        var config = VoiceCommandStore.defaultConfig
        config.entities.removeAll { $0.name == VoiceCommandConfig.keyEntityName }
        let index = config.entities.firstIndex { $0.name == VoiceCommandConfig.commandEntityName }!
        config.entities[index].values.removeAll { $0.key == "focar" || $0.key == "copiar" }
        config.entities[index].values[0].aliases = "minha frase"
        config.addMissingBuiltIns()
        #expect(config.commandKey(for: "copiar") == "copiar")
        #expect(config.commandKey(for: "focar") == "focar")
        #expect(config.commandKey(for: "minha frase") != nil)
        #expect(config.entity(named: "tecla")?.values.first { $0.label == "apagar palavra" }?.value == "option+delete")
        #expect(config.nameIssue("comando", for: config.entities[0].id) != nil)
        // `<tecla>` is plain data now.
        #expect(config.nameIssue("tecla", for: nil) != nil)
        #expect(config.nameIssue("teclas", for: nil) == nil)
        #expect(config.nameIssue("comando", for: config.entities[index].id) == nil)
    }

    @MainActor
    @Test func appsAreAddedOnceAndKept() {
        var config = VoiceCommandStore.defaultConfig
        config.addApps([("Gemini", "com.google.gemini"), ("Visual Studio Code", "com.microsoft.VSCode")])
        let index = config.entities.firstIndex { $0.name == VoiceCommandConfig.appEntityName }!
        config.entities[index].values[0].soundsLike = "djêmini"
        // Seen again (and a second app with the same name): the edit stays, ids stay unique.
        config.addApps([("Gemini", "com.google.gemini"), ("Gemini", "com.other.gemini")])
        let values = config.entities[index].values
        #expect(values.map(\.key) == ["gemini", "visual-studio-code", "gemini-2"])
        #expect(values[0].soundsLike == "djêmini")
    }

    @MainActor
    @Test func appTemplateFocusesByBundleID() {
        var config = VoiceCommandStore.defaultConfig
        config.addApps([("Gemini", "com.google.gemini")])
        let resolution = CommandResolver.resolveWithAliases("gemini", config: config)
        #expect(resolution?.template.target == .appWindow)
        let prepared = resolution.map {
            PreparedCommand(template: $0.template, values: $0.values, transcript: "gemini", entities: config.entities)
        }
        #expect(prepared?.command == "com.google.gemini")
        #expect(CommandResolver.isRequest(" Gemini.", config: config))
    }

    @MainActor
    @Test func olderConfigsGetTheAppTemplate() {
        var config = VoiceCommandStore.defaultConfig
        config.templates.removeAll { $0.target == .appWindow }
        config.entities.removeAll { $0.name == VoiceCommandConfig.appEntityName }
        config.addMissingBuiltIns()
        config.addMissingBuiltIns()
        #expect(config.templates.filter { $0.target == .appWindow }.count == 1)
        #expect(config.entity(named: "app") != nil)
    }

    // MARK: Keys

    @MainActor
    @Test func keysTemplatePressesTheValue() {
        let config = VoiceCommandStore.defaultConfig
        let resolution = CommandResolver.resolveWithAliases("apagar palavra", config: config)
        #expect(resolution?.template.target == .keys)
        let prepared = resolution.map {
            PreparedCommand(template: $0.template, values: $0.values, transcript: "apagar palavra", entities: config.entities)
        }
        // Raw, not shell-quoted.
        #expect(prepared?.command == "option+delete")
        #expect(prepared?.template.target.asksConfirmation == false)
    }

    @MainActor
    @Test func keysTemplatesAreValidated() {
        let entities = VoiceCommandStore.defaultConfig.entities
        let literal = CommandTemplate(phrase: "apagar tudo", command: "cmd+a delete", target: .keys)
        #expect(TemplateValidator.issues(in: literal, entities: entities).isEmpty)
        let typo = CommandTemplate(phrase: "apagar tudo", command: "cmd+a delet", target: .keys)
        #expect(TemplateValidator.issues(in: typo, entities: entities) == [.invalidKeys("delet")])
        let withField = CommandTemplate(phrase: "aperta <tecla>", command: "{tecla} return", target: .keys)
        #expect(TemplateValidator.issues(in: withField, entities: entities).isEmpty)

        var config = VoiceCommandStore.defaultConfig
        let keys = config.entity(named: "tecla")!
        #expect(config.valueIssue(EntityValue(key: "x", label: "x", value: "hyper+x"), in: keys.id) != nil)
        // Not used by a keys template anymore: any value goes.
        config.templates.removeAll { $0.target == .keys }
        #expect(config.valueIssue(EntityValue(key: "x", label: "x", value: "hyper+x"), in: keys.id) == nil)
    }

    @Test("Key sequences", arguments: [
        ("option+delete", 1), ("cmd+a delete", 2), ("option+delete*3", 3), ("tab*2 return", 3),
    ])
    func keySequences(_ text: String, count: Int) {
        #expect(KeySequence(text)?.strokes.count == count)
    }

    @Test("Invalid key sequences", arguments: ["", "delete*0", "delete*51", "delete*x", "a**2", "hyper+a"])
    func invalidKeySequences(_ text: String) {
        #expect(KeySequence(text) == nil)
    }

    @Test("Key combos", arguments: [
        ("option+delete", true), ("Cmd + Shift + Z", true), ("return", true), ("f5", true),
        ("hyper+a", false), ("option+", false), ("", false),
    ])
    func keyCombos(_ text: String, valid: Bool) {
        #expect((KeyCombo(text) != nil) == valid)
    }

    @Test func keyComboFlags() {
        let combo = KeyCombo("cmd+shift+z")
        #expect(combo?.flags == [.maskCommand, .maskShift])
        #expect(KeyCombo("return")?.endsSegment == true)
        #expect(KeyCombo("option+delete")?.endsSegment == false)
    }


    @MainActor
    @Test("Wake word mid-segment", arguments: [
        ("Tudo certo, vox enviar.", "Tudo certo, ", " enviar."),
        ("Vox copiar", "", " copiar"),
        ("escrevi isso Vox.", "escrevi isso ", "."),
    ])
    func splitsAtWakeWord(_ text: String, dictation: String, remainder: String) {
        let split = VoiceCommandRouter.split(text, atWakeWord: "vox")
        #expect(split?.dictation == dictation)
        #expect(split?.remainder == remainder)
    }

    // MARK: Routing

    @MainActor
    @Test("Routing", arguments: [
        ("Oi, tudo bem?", false, [VoiceAction.dictate("Oi, tudo bem?")]),
        ("Vox copiar.", false, [.command(.copy)]),
        ("Voz parar", false, [.command(.stop)]),
        // An alias before ordinary words stays dictation.
        ("voz bonita a dela", false, [.dictate("voz bonita a dela")]),
        ("Tudo certo. Enviar.", true, [.dictate("Tudo certo."), .command(.send)]),
        ("Tudo certo, vox enviar.", true, [.dictate("Tudo certo, "), .command(.send)]),
        ("escrevi isso vox blá", true, [.dictate("escrevi isso "), .unknownCommand("blá")]),
        ("Vox escreve isso", false, [.focusAndDictate("escreve isso")]),
        ("Vox apagar palavra", true, [.template("apagar palavra")]),
        ("Vox", false, [.command(.focus)]),
        ("Vox", true, [.awaitCommand]),
    ])
    func routes(_ text: String, isTyping: Bool, expected: [VoiceAction]) {
        var router = VoiceCommandRouter(wakeWord: "vox", aliases: ["voz"], isEnabled: true)
        #expect(router.route(text, isTyping: isTyping, config: VoiceCommandStore.defaultConfig) == expected)
    }

    @MainActor
    @Test func loneWakeWordAwaitsTheNextSegment() {
        let config = VoiceCommandStore.defaultConfig
        var router = VoiceCommandRouter(wakeWord: "vox", aliases: [], isEnabled: true)
        let start = ContinuousClock.now
        #expect(router.route("texto vox.", isTyping: true, config: config, now: start) == [.dictate("texto "), .awaitCommand])
        #expect(router.liveDictation("enviar", now: start + .seconds(1)) == "")
        #expect(router.route("enviar", isTyping: true, config: config, now: start + .seconds(1)) == [.command(.send)])
        // Expired: dictation again.
        _ = router.route("vox", isTyping: true, config: config, now: start)
        #expect(router.route("enviar a mensagem", isTyping: true, config: config, now: start + .seconds(6))
                == [.dictate("enviar a mensagem")])
    }

    @MainActor
    @Test func disabledCommandsAreDictation() {
        var router = VoiceCommandRouter(wakeWord: "vox", aliases: [], isEnabled: false)
        #expect(router.route("vox copiar", isTyping: false, config: VoiceCommandStore.defaultConfig) == [.dictate("vox copiar")])
        #expect(router.liveDictation("texto vox enviar") == "texto vox enviar")
    }

    @MainActor
    @Test func liveDictationStopsAtTheWakeWord() {
        let router = VoiceCommandRouter(wakeWord: "vox", aliases: [], isEnabled: true)
        #expect(router.liveDictation("Tudo certo vox env") == "Tudo certo ")
        #expect(router.liveDictation("Vox copi") == "")
    }

    @MainActor
    @Test func wakeWordMustBeAWholeWord() {
        #expect(VoiceCommandRouter.split("o voxel ficou bom", atWakeWord: "vox") == nil)
    }

    @MainActor
    @Test func defaultsKeepTheOldLaunch() {
        let defaults = VoiceCommandStore.defaultConfig
        #expect(defaults.entities.prefix(2).map(\.name) == ["agente", "projeto"])
        #expect(defaults.validTemplates.map(\.target) == [.tmuxWindow, .tmuxPane, .appWindow, .keys])
        let store = VoiceCommandStore(url: nil)
        store.addSubfolders(["/x/cognia-labs", "/x/Vox"], toEntity: store.config.entities[1].id)
        store.addSubfolders(["/y/vox"], toEntity: store.config.entities[1].id)
        #expect(store.config.entities[1].values.map(\.key) == ["cognia-labs", "vox"])
        #expect(store.config.entities[1].values.last?.value == "/x/Vox")
    }
}

struct SoundsLikeTests {
    /// The pt-BR pronunciations that were hard-coded in `CustomVocabulary`, from their spellings.
    @Test("Previous pronunciations", arguments: [
        ("vóks", "v \"O k s"),
        ("vóquis", "v \"O k i s"),
        ("clód", "k l \"O d"),
        ("clódi", "k l \"O dZ i"),
        ("clôd", "k l \"o d"),
        ("pái", "p \"a j"),
        ("pí", "p \"i"),
    ])
    func previous(_ spelling: String, expected: String) {
        #expect(SoundsLike.xsampa(spelling) == expected)
    }

    @Test("Prototype rules", arguments: [
        ("liéti", "l j \"E tS i"),
        ("vócs", "v \"O k s"),
        ("chuva", "S u v a"),
        ("carro", "k a x u"),
        ("casa", "k a z a"),
        ("guerra", "g e x a"),
        ("ilha", "i L a"),
        ("sol", "s o w"),
        ("cidade", "s i d a d i"),
        ("CLÓDI", "k l \"O dZ i"),
    ])
    func rules(_ spelling: String, expected: String) {
        #expect(SoundsLike.xsampa(spelling) == expected)
    }

    @Test func commaSeparatedSpellings() {
        #expect(SoundsLike.pronunciations("vóks, vóquis,, ") == ["v \"O k s", "v \"O k i s"])
    }
}
