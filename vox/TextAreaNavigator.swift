//
//  TextAreaNavigator.swift
//  vox
//
//  Created by Pedro Planel on 02/11/26.
//

import AppKit
import ApplicationServices

/// Uses the Accessibility API to move keyboard focus to the main text input
/// of the frontmost app's focused window. Requires the Accessibility permission.
/// Everything runs on the main actor (the project's default isolation).
enum TextAreaNavigator {
    /// Upper bound on visited AX nodes, so huge trees (web pages, Xcode) can't stall the main thread.
    private static let maxVisitedNodes = 3000
    private static let maxDepth = 40

    /// Roles whose subtrees never contain editable text; skipping them keeps the walk cheap.
    private static let leafRoles: Set<String> = [
        kAXStaticTextRole, kAXImageRole, kAXButtonRole, kAXMenuBarRole,
        kAXMenuButtonRole, kAXCheckBoxRole, kAXRadioButtonRole, kAXSliderRole,
    ]

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Privacy → Accessibility.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Why a focus request did or didn't work; shown in the island so failures aren't silent.
    enum FocusResult: Error {
        case focused(app: String)
        case notTrusted
        case noTargetApp
        case noWindow(app: String)
        case noTextArea(app: String)
        case focusRejected(app: String)

        var succeeded: Bool {
            if case .focused = self { return true }
            return false
        }

        var message: String {
            switch self {
            case .focused(let app): "Digitando em \(app)"
            case .notTrusted: "Permita o Vox em Ajustes → Privacidade → Acessibilidade"
            case .noTargetApp: "Nenhum app em foco"
            case .noWindow(let app): "\(app): nenhuma janela em foco"
            case .noTextArea(let app): "\(app): nenhuma área de texto encontrada"
            case .focusRejected(let app): "\(app) recusou o foco na área de texto"
            }
        }
    }

    /// An editable text element found in the focused window.
    private struct Candidate {
        let element: AXUIElement
        let frame: CGRect
        /// On-screen area weighted so multi-line text areas beat single-line fields and search boxes.
        let score: Double
    }

    /// Last app other than Vox to become active. Clicking the menu bar popover or opening
    /// Settings makes Vox frontmost, and the target should still be the app the user was in.
    private static var lastExternalApp: NSRunningApplication?

    /// Call once at launch.
    static func startTrackingFrontmostApp() {
        lastExternalApp = externalApp(NSWorkspace.shared.frontmostApplication)
        NotificationCenter.default.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                if let app = externalApp(app) { lastExternalApp = app }
            }
        }
    }

    private static func externalApp(_ app: NSRunningApplication?) -> NSRunningApplication? {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        return app
    }

    /// Focuses the largest editable text element in the target app's focused window.
    /// `app` targets a specific app (one just brought forward) instead of the frontmost one.
    static func focusMainTextArea(in app: NSRunningApplication? = nil) -> FocusResult {
        let target: Target
        switch focusedWindow(in: app) {
        case .success(let found): target = found
        case .failure(let result): return result
        }
        guard let best = textElements(for: target).max(by: { $0.score < $1.score }) else {
            return .noTextArea(app: target.name)
        }
        return focus(best, in: target)
    }

    /// Focuses the text element after the currently focused one, in reading order
    /// (top to bottom, then left to right), wrapping around at the end.
    static func focusNextTextArea() -> FocusResult {
        let target: Target
        switch focusedWindow() {
        case .success(let found): target = found
        case .failure(let result): return result
        }
        let ordered = textElements(for: target).sorted {
            // Rows within a few points count as the same line.
            abs($0.frame.minY - $1.frame.minY) > 4 ? $0.frame.minY < $1.frame.minY : $0.frame.minX < $1.frame.minX
        }
        guard !ordered.isEmpty else { return .noTextArea(app: target.name) }

        let current = element(target.appElement, kAXFocusedUIElementAttribute).flatMap { focused in
            ordered.firstIndex { isSameOrAncestor($0.element, of: focused) }
        }
        let nextIndex = current.map { ($0 + 1) % ordered.count } ?? 0
        return focus(ordered[nextIndex], in: target)
    }

    // MARK: - Focus

    private struct Target {
        let app: NSRunningApplication
        let appElement: AXUIElement
        let window: AXUIElement
        var name: String { app.localizedName ?? "App" }
    }

    private static func focusedWindow(in requested: NSRunningApplication? = nil) -> Result<Target, FocusResult> {
        guard isTrusted else {
            requestTrust()
            return .failure(.notTrusted)
        }
        guard let app = requested ?? externalApp(NSWorkspace.shared.frontmostApplication) ?? lastExternalApp,
              !app.isTerminated else {
            return .failure(.noTargetApp)
        }
        let name = app.localizedName ?? "App"

        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 1)
        // Electron apps only build their AX tree when asked to.
        AXUIElementSetAttributeValue(appElement, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        guard let window = element(appElement, kAXFocusedWindowAttribute)
                ?? element(appElement, kAXMainWindowAttribute) else {
            return .failure(.noWindow(app: name))
        }
        return .success(Target(app: app, appElement: appElement, window: window))
    }

    /// Chromium-based apps (Chrome, Arc, Brave…) expose their web content only to
    /// "enhanced" clients, so retry once with that flag when the first walk finds nothing.
    private static func textElements(for target: Target) -> [Candidate] {
        let candidates = textElements(in: target.window)
        guard candidates.isEmpty else { return candidates }
        AXUIElementSetAttributeValue(target.appElement, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        // The tree is built asynchronously after the flag flips.
        Thread.sleep(forTimeInterval: 0.25)
        return textElements(in: target.window)
    }

    private static func focus(_ candidate: Candidate, in target: Target) -> FocusResult {
        AXUIElementPerformAction(target.window, kAXRaiseAction as CFString)
        target.app.activate()
        if AXUIElementSetAttributeValue(candidate.element, kAXFocusedAttribute as CFString, kCFBooleanTrue) == .success {
            return .focused(app: target.name)
        }
        // Some web views reject AXFocused; a click in the field focuses it anyway.
        return click(at: CGPoint(x: candidate.frame.midX, y: candidate.frame.midY))
            ? .focused(app: target.name)
            : .focusRejected(app: target.name)
    }

    /// AX frames and CGEvent locations share the same top-left-origin global coordinates.
    private static func click(at point: CGPoint) -> Bool {
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
            return false
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    /// Web text areas report an inner node as focused, so walk up a few parents to find the candidate.
    private static func isSameOrAncestor(_ candidate: AXUIElement, of focused: AXUIElement) -> Bool {
        var current: AXUIElement? = focused
        for _ in 0..<6 {
            guard let node = current else { return false }
            if CFEqual(node, candidate) { return true }
            current = element(node, kAXParentAttribute)
        }
        return false
    }

    // MARK: - Tree search

    /// Breadth-first walk collecting every visible, focusable text element.
    private static func textElements(in root: AXUIElement) -> [Candidate] {
        var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
        var index = 0
        var candidates: [Candidate] = []

        while index < queue.count, index < maxVisitedNodes {
            let (current, depth) = queue[index]
            index += 1

            let role = string(current, kAXRoleAttribute) ?? ""
            if let weight = weight(role: role, subrole: string(current, kAXSubroleAttribute)),
               isFocusable(current) {
                let frame = frame(of: current)
                let score = Double(frame.width * frame.height) * weight
                if score > 0 {
                    candidates.append(Candidate(element: current, frame: frame, score: score))
                }
                // Text areas in web content expose their text runs as children; no need to descend.
                continue
            }

            guard depth < maxDepth, !leafRoles.contains(role) else { continue }
            for child in children(of: current) {
                queue.append((child, depth + 1))
            }
        }
        return candidates
    }

    private static func weight(role: String, subrole: String?) -> Double? {
        switch role {
        case kAXTextAreaRole:
            return 3
        case kAXTextFieldRole:
            return subrole == kAXSearchFieldSubrole ? 0.5 : 1
        case kAXComboBoxRole:
            return 0.5
        default:
            return nil
        }
    }

    /// Only rejects explicitly disabled or read-only fields: many web and Electron fields
    /// report AXFocused as not settable even though focusing them works.
    private static func isFocusable(_ element: AXUIElement) -> Bool {
        if let enabled = value(element, kAXEnabledAttribute) as? Bool, !enabled { return false }
        var valueSettable: DarwinBoolean = false
        var focusSettable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &valueSettable)
        AXUIElementIsAttributeSettable(element, kAXFocusedAttribute as CFString, &focusSettable)
        let editable = value(element, "AXEditableAncestor") != nil
        return valueSettable.boolValue || focusSettable.boolValue || editable
    }

    // MARK: - AX helpers

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute),
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private static func frame(of element: AXUIElement) -> CGRect {
        var origin = CGPoint.zero
        var size = CGSize.zero
        if let value = value(element, kAXPositionAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
            AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgPoint, &origin)
        }
        if let value = value(element, kAXSizeAttribute), CFGetTypeID(value) == AXValueGetTypeID() {
            AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cgSize, &size)
        }
        return CGRect(origin: origin, size: size)
    }
}
