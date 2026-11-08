//
//  VoiceCommandStore.swift
//  vox
//
//  Created by Pedro Planel on 03/11/26.
//

import AppKit
import Foundation
import Observation
import os

private let log = Logger(subsystem: "dev.pplanel.vox", category: "VoiceCommandStore")

/// Entities and templates from Settings → Comandos de voz, saved as JSON in
/// Application Support/dev.pplanel.vox/VoiceCommands.json on every change.
@Observable
final class VoiceCommandStore {
    static let shared = VoiceCommandStore()

    var config: VoiceCommandConfig {
        didSet {
            guard config != oldValue else { return }
            save()
        }
    }

    private let url: URL?

    /// `url` nil keeps everything in memory (previews).
    init(url: URL? = VoiceCommandStore.defaultURL) {
        self.url = url
        if let url, let data = try? Data(contentsOf: url),
           var config = try? JSONDecoder().decode(VoiceCommandConfig.self, from: data) {
            // Bring in new built-in commands once; values deleted later aren't added back.
            let defaults = UserDefaults.standard
            if defaults.integer(forKey: Self.builtInsVersionKey) < Self.builtInsVersion {
                config.addMissingBuiltIns()
                defaults.set(Self.builtInsVersion, forKey: Self.builtInsVersionKey)
            }
            self.config = config
            save()
            return
        }
        config = VoiceCommandStore.defaultConfig
        guard let url else { return }
        // A file that doesn't decode is kept aside instead of being overwritten by the defaults.
        if FileManager.default.fileExists(atPath: url.path) {
            let backup = url.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: url, to: backup)
            log.error("VoiceCommands.json didn't decode; moved to \(backup.lastPathComponent, privacy: .public)")
        }
        save()
        // The project folders live on disk; fill them in once, like the old launch did.
        Task { await fillDefaultProjects() }
    }

    /// Bump when the built-in entities gain values or a built-in template is added.
    private static let builtInsVersion = 3
    private static let builtInsVersionKey = "voiceCommandBuiltInsVersion"

    private static var defaultURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "dev.pplanel.vox/VoiceCommands.json")
    }

    private func save() {
        guard let url else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config).write(to: url, options: .atomic)
        } catch {
            log.error("Saving voice commands failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Apps

    /// Adds the apps with open windows to `<app>`. Apps that closed stay, with their edits.
    func addWindowedApps() {
        let apps = AppSwitcher.windowedApps().compactMap { app -> (name: String, bundleID: String)? in
            guard let name = app.localizedName, let bundleID = app.bundleIdentifier else { return nil }
            return (name, bundleID)
        }
        config.addApps(apps)
    }

    // MARK: - Folders

    /// Adds a value per subfolder of `paths` to the entity, skipping folders whose id is
    /// already there: id and label are the folder name, the value its absolute path.
    func addSubfolders(_ paths: [String], toEntity entityID: CommandEntity.ID) {
        guard let index = config.entities.firstIndex(where: { $0.id == entityID }) else { return }
        var existing = Set(config.entities[index].values.map(\.key))
        for path in paths.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            let name = (path as NSString).lastPathComponent
            guard existing.insert(name.lowercased()).inserted else { continue }
            config.entities[index].values.append(EntityValue(key: name.lowercased(), label: name, value: path))
        }
    }

    private func fillDefaultProjects() async {
        guard let projects = config.entities.first(where: { $0.name == "projeto" }), projects.values.isEmpty else { return }
        var paths: [String] = []
        if case .success(let folders) = await TmuxNavigator.subfolders(of: "~/src/pplanel") {
            paths = folders
        }
        if case .success(let folders) = await TmuxNavigator.subfolders(of: "~/.config") {
            paths += folders.filter { ($0 as NSString).lastPathComponent == "nix-darwin" }
        }
        addSubfolders(paths, toEntity: projects.id)
    }

    // MARK: - Defaults

    /// What used to be hard-coded: the agents, the project entity (filled from disk), the
    /// names whose pronunciation the vocabulary taught, the "abre o … no …" launch and the
    /// "vox claude" / "vox pi" pane focus, and the built-in `<comando>`s.
    static let defaultConfig = VoiceCommandConfig(
        entities: [
            CommandEntity(name: "agente", values: [
                EntityValue(key: "claude", label: "Claude", aliases: "cláudio, claudio, cloud, clode, clod",
                            value: "claude", soundsLike: "clód, clódi, clôd"),
                EntityValue(key: "pi", label: "Pi", aliases: "pai, pie", value: "pi", soundsLike: "pái, pí"),
            ]),
            CommandEntity(name: "projeto", values: []),
            CommandEntity(name: "nome", values: [
                EntityValue(key: "vox", label: "Vox", value: "vox", soundsLike: "vóks, vóquis"),
                EntityValue(key: "liet", label: "Liet", aliases: "liete, lieti, líete, lied", value: "liet", soundsLike: "liéti"),
            ]),
            VoiceCommandConfig.defaultCommandEntity,
            VoiceCommandConfig.defaultKeyEntity,
            VoiceCommandConfig.defaultAppEntity,
        ],
        templates: [
            CommandTemplate(phrase: "abre o <agente> no <projeto>", command: "cd {projeto} && {agente} {pedido}"),
            // "vox claude": the pane already running it (repeat to cycle through several).
            CommandTemplate(phrase: "<agente>", command: "{agente}", target: .tmuxPane),
            VoiceCommandConfig.defaultAppTemplate,
            VoiceCommandConfig.defaultKeysTemplate,
        ]
    )
}
