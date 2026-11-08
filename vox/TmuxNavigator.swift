//
//  TmuxNavigator.swift
//  vox
//
//  Created by Pedro Planel on 03/11/26.
//

import AppKit

/// "vox pi" / "vox claude": finds the tmux pane running a CLI program, switches the attached
/// tmux client to that window and pane, and brings Ghostty to the front so dictation lands there.
enum TmuxNavigator {
    private static let ghosttyBundleID = "com.mitchellh.ghostty"

    /// A CLI program to look for in tmux panes.
    struct Program {
        let displayName: String
        /// Executable or script names; Nix wrappers rename the binary (".claude-wrapped").
        let names: Set<String>

        /// `command` is an executable name or path ("claude", "/opt/bin/pi").
        init(displayName: String, command: String) {
            self.displayName = displayName
            let name = (command.trimmingCharacters(in: .whitespaces) as NSString).lastPathComponent
            names = [name, ".\(name)-wrapped"]
        }
    }

    enum Failure: Error {
        case tmuxNotFound
        case helperMissing
        case noPane(Program)
        case tmuxFailed(String)
        case ghosttyNotRunning

        var message: String {
            switch self {
            case .tmuxNotFound: "tmux não encontrado"
            case .helperMissing: "Instale o vox-helper.sh em ~/Library/Application Scripts/dev.pplanel.vox"
            case .noPane(let program): "Nenhum pane do tmux rodando o \(program.displayName)"
            case .tmuxFailed(let error): "tmux: \(error)"
            case .ghosttyNotRunning: "Ghostty não está aberto"
            }
        }
    }

    static func focus(_ program: Program) async -> Result<Void, Failure> {
        guard let ghostty = NSRunningApplication.runningApplications(withBundleIdentifier: ghosttyBundleID).first else {
            return .failure(.ghosttyNotRunning)
        }

        // The third field is 1 for the pane the attached client is looking at.
        let format = "#{pane_id} #{pane_pid} #{&&:#{pane_active},#{&&:#{window_active},#{session_attached}}} #{pane_current_command}"
        let listing: String
        switch await run(.tmux, ["list-panes", "-a", "-F", format]) {
        case .success(let output): listing = output
        case .failure(let error): return .failure(error)
        }
        guard let target = await pane(running: program, in: listing) else { return .failure(.noPane(program)) }
        return await show(target, in: ghostty)
    }

    /// A voice command template run in a new tmux window, shown like `focus` does for an
    /// existing pane. The command goes to tmux as a single argument, so its shell runs it.
    static func openWindow(named name: String, running command: String) async -> Result<Void, Failure> {
        guard let ghostty = NSRunningApplication.runningApplications(withBundleIdentifier: ghosttyBundleID).first else {
            return .failure(.ghosttyNotRunning)
        }
        let target: String
        switch await run(.tmux, newWindowArguments(named: name, running: command)) {
        case .success(let output): target = output.trimmingCharacters(in: .whitespacesAndNewlines)
        case .failure(let error): return .failure(error)
        }
        return await show(target, in: ghostty)
    }

    /// -P prints the new pane id for `show`. A quick command ("cd …; git pull") would close the
    /// window before `show` finds its pane ("can't find pane: %19"), so a shell takes over
    /// when it ends: the output stays visible, in the folder the command moved to.
    nonisolated static func newWindowArguments(named name: String, running command: String) -> [String] {
        ["new-window", "-P", "-F", "#{pane_id}", "-n", name, "--", "\(command); exec \"${SHELL:-/bin/sh}\""]
    }

    /// A voice command template run detached with `sh -c`; output goes to
    /// ~/Library/Logs/vox-commands.log.
    static func runInBackground(_ command: String) async -> Result<Void, Failure> {
        if isSandboxed {
            return await runHelper(["run", command]).map { _ in () }
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = URL(fileURLWithPath: realHomeDirectory)
        var environment = Foundation.ProcessInfo.processInfo.environment
        environment["PATH"] = searchPath
        process.environment = environment
        let logURL = URL(fileURLWithPath: realHomeDirectory).appending(path: "Library/Logs/vox-commands.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        if let log = try? FileHandle(forWritingTo: logURL) {
            log.seekToEndOfFile()
            process.standardOutput = log
            process.standardError = log
        }
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
            return .success(())
        } catch {
            return .failure(.tmuxFailed(error.localizedDescription))
        }
    }

    /// switch-client moves the attached client to the session (it uses the most recently
    /// active client, since Vox runs outside tmux); the other two pick window and pane.
    private static func show(_ target: String, in ghostty: NSRunningApplication) async -> Result<Void, Failure> {
        for arguments in [["switch-client", "-t", target], ["select-window", "-t", target], ["select-pane", "-t", target]] {
            if case .failure(let error) = await run(.tmux, arguments) { return .failure(error) }
        }
        bringToFront(ghostty)
        return .success(())
    }

    // MARK: - Folders

    /// The user's real home; inside the sandbox `NSHomeDirectory()` is the container.
    nonisolated static var realHomeDirectory: String {
        getpwuid(getuid()).flatMap { String(validatingCString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
    }

    /// Absolute paths of the folders in `directory` ("~/…" allowed). Sandboxed, the app can't
    /// read arbitrary folders (and its home is the container), so the helper lists them.
    static func subfolders(of directory: String) async -> Result<[String], Failure> {
        if isSandboxed {
            return await runHelper(["subfolders", directory]).map { output in
                output.split(separator: "\n").map(String.init)
            }
        }
        let path = directory.hasPrefix("~") ? realHomeDirectory + directory.dropFirst() : directory
        let folders = (try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: path), includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        return .success(folders
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.path)
            .sorted())
    }

    /// Raises the already-running Ghostty instance. `activate()` alone is cooperative on
    /// macOS 14+ and can be ignored while Vox isn't active, leaving Ghostty behind other windows.
    private static func bringToFront(_ app: NSRunningApplication) {
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        var window: CFTypeRef?
        if AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &window) == .success,
           let window, CFGetTypeID(window) == AXUIElementGetTypeID() {
            AXUIElementPerformAction(unsafeDowncast(window, to: AXUIElement.self), kAXRaiseAction as CFString)
        }
        app.activate()
    }

    // MARK: - Pane lookup

    private struct Pane {
        let target: String
        let pid: Int32
        let isCurrent: Bool
        let command: String
    }

    /// Lines are "%<id> <pid> <current> <command>": tmux turns tabs in -F output into "_", so
    /// fields are space-separated with the command last. The pane id ("%3") works as a target
    /// for switch-client, select-window and select-pane regardless of the session name.
    ///
    /// With several matching panes, repeating the command cycles through them, starting after
    /// the one currently shown.
    private static func pane(running program: Program, in listing: String) async -> String? {
        let panes = listing.split(separator: "\n").compactMap { line -> Pane? in
            let fields = line.split(separator: " ", maxSplits: 3)
            guard fields.count == 4, let pid = Int32(fields[1]) else { return nil }
            return Pane(target: String(fields[0]), pid: pid, isCurrent: fields[2] == "1", command: String(fields[3]))
        }

        // `pane_current_command` is "node" when the program runs as a Node script, so the
        // pane's process tree is checked too (only when needed, since `ps` is slower).
        var processes: [RunningProcess]?
        var matches: [Pane] = []
        for pane in panes {
            if program.names.contains(pane.command) {
                matches.append(pane)
                continue
            }
            if processes == nil { processes = await processTable() }
            if descendants(of: pane.pid, in: processes ?? []).contains(where: { runs(program, arguments: $0.arguments) }) {
                matches.append(pane)
            }
        }
        guard !matches.isEmpty else { return nil }

        let next = matches.firstIndex(where: \.isCurrent).map { ($0 + 1) % matches.count } ?? 0
        return matches[next].target
    }

    private struct RunningProcess {
        let pid: Int32
        let parent: Int32
        let arguments: String
    }

    private static func processTable() async -> [RunningProcess] {
        guard case .success(let output) = await run(.ps, ["-A", "-o", "pid=,ppid=,args="]) else { return [] }
        return output.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3, let pid = Int32(fields[0]), let parent = Int32(fields[1]) else { return nil }
            return RunningProcess(pid: pid, parent: parent, arguments: String(fields[2]))
        }
    }

    private static func descendants(of root: Int32, in processes: [RunningProcess]) -> [RunningProcess] {
        var result: [RunningProcess] = []
        var frontier: Set<Int32> = [root]
        while !frontier.isEmpty {
            let children = processes.filter { frontier.contains($0.parent) }
            result += children
            frontier = Set(children.map(\.pid))
        }
        return result
    }

    /// Matches the executable or the script passed to an interpreter ("node /…/bin/pi").
    private static func runs(_ program: Program, arguments: String) -> Bool {
        arguments.split(separator: " ").prefix(2).contains { program.names.contains(($0 as NSString).lastPathComponent) }
    }

    // MARK: - Process helpers

    private enum Tool: String {
        case tmux, ps
    }

    /// Inside the App Sandbox (needed to compile the custom vocabulary) child processes are
    /// sandboxed too and can't reach the Nix tmux or its socket in /private/tmp. The only way
    /// out is a user-installed script run with NSUserUnixTask; see Scripts/vox-helper.sh.
    private static let isSandboxed = Foundation.ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    private static let helperName = "vox-helper.sh"

    private static func run(_ tool: Tool, _ arguments: [String]) async -> Result<String, Failure> {
        if isSandboxed {
            return await runHelper([tool.rawValue] + arguments)
        }
        switch tool {
        case .ps:
            return runProcess("/bin/ps", arguments)
        case .tmux:
            guard let tmux = tmuxPath else { return .failure(.tmuxNotFound) }
            return runProcess(tmux, arguments)
        }
    }

    private static func runHelper(_ arguments: [String]) async -> Result<String, Failure> {
        guard let scripts = try? FileManager.default.url(for: .applicationScriptsDirectory, in: .userDomainMask,
                                                         appropriateFor: nil, create: false),
              let task = try? NSUserUnixTask(url: scripts.appending(path: helperName)) else {
            return .failure(.helperMissing)
        }
        let output = Pipe()
        let error = Pipe()
        task.standardOutput = output.fileHandleForWriting
        task.standardError = error.fileHandleForWriting
        // Read while the script runs: `ps` output can exceed the pipe buffer and block it.
        let reader = Task.detached { output.fileHandleForReading.readDataToEndOfFile() }
        let failure: (any Error)?
        do {
            try await task.execute(withArguments: arguments)
            failure = nil
        } catch {
            failure = error
        }
        // Our copies of the write ends keep the pipes open until closed.
        try? output.fileHandleForWriting.close()
        try? error.fileHandleForWriting.close()
        let data = await reader.value
        if let failure {
            let message = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .failure(.tmuxFailed(message.isEmpty ? failure.localizedDescription : message))
        }
        return .success(String(decoding: data, as: UTF8.self))
    }

    /// Same PATH as Scripts/vox-helper.sh, since GUI apps don't inherit the shell's.
    private static var searchPath: String {
        let home = realHomeDirectory
        return ["/etc/profiles/per-user/\(NSUserName())/bin", "/run/current-system/sw/bin", home + "/.nix-profile/bin",
                "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"].joined(separator: ":")
    }

    /// GUI apps don't inherit the shell's PATH, so look in the usual install locations
    /// and fall back to asking a login shell once.
    private static let tmuxPath: String? = {
        let candidates = ["/etc/profiles/per-user/\(NSUserName())/bin/tmux", "/opt/homebrew/bin/tmux", "/usr/local/bin/tmux",
                          "/run/current-system/sw/bin/tmux", NSHomeDirectory() + "/.nix-profile/bin/tmux", "/usr/bin/tmux"]
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return path
        }
        guard case .success(let output) = runProcess("/bin/zsh", ["-lc", "command -v tmux"]) else { return nil }
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }()

    private static func runProcess(_ executable: String, _ arguments: [String]) -> Result<String, Failure> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        do {
            try process.run()
        } catch {
            return .failure(.tmuxFailed(error.localizedDescription))
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: error.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return .failure(.tmuxFailed(message.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return .success(String(decoding: data, as: UTF8.self))
    }
}
