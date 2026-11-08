//
//  AppSwitcher.swift
//  vox
//
//  Created by Pedro Planel on 04/11/26.
//

import AppKit
import ApplicationServices

/// Brings a running app's window to the front. Activating the app makes macOS switch to the
/// Space holding its window (with "When switching to an application, switch to a Space with
/// open windows" on, the default). Requires the Accessibility permission.
enum AppSwitcher {
    /// Regular apps other than Vox with at least one window, on any Space.
    static func windowedApps() -> [NSRunningApplication] {
        let windows = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        // Layer 0 holds normal windows; menu bar extras and overlays live above it.
        let owners = Set(windows.compactMap { info -> pid_t? in
            guard info[kCGWindowLayer as String] as? Int == 0 else { return nil }
            return info[kCGWindowOwnerPID as String] as? pid_t
        })
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != ownPID
                && $0.localizedName != nil && owners.contains($0.processIdentifier)
        }
    }

    /// The running app with `bundleID`, opening it when it isn't running (Vox waits for its launch).
    static func app(bundleID: String) async -> NSRunningApplication? {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            return running
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return try? await NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// `activate()` alone is cooperative on macOS 14+ and can be ignored while Vox isn't
    /// active, so the app is also made frontmost through Accessibility.
    static func bringToFront(_ app: NSRunningApplication) {
        if app.isHidden { app.unhide() }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        if let window = element(appElement, kAXMainWindowAttribute) ?? windows(of: appElement).first {
            AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
        AXUIElementSetAttributeValue(appElement, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
        app.activate()
    }

    /// Whether `app` is the one taking keystrokes. Asks Accessibility, since
    /// `NSWorkspace.frontmostApplication` can lag behind while Vox isn't active.
    static func isFrontmost(_ app: NSRunningApplication) -> Bool {
        var pid: pid_t = 0
        if let focused = element(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute),
           AXUIElementGetPid(focused, &pid) == .success {
            return pid == app.processIdentifier
        }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    private static func windows(of appElement: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }
}
