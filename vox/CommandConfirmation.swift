//
//  CommandConfirmation.swift
//  vox
//
//  Created by Pedro Planel on 03/11/26.
//

import Foundation
import UserNotifications
import os

private let log = Logger(subsystem: "dev.pplanel.vox", category: "CommandConfirmation")

/// Asks "Rodar …?" for a voice command template as a notification with Executar / Cancelar
/// buttons and the exact command in the body. Saying "vox sim" / "vox não" still works; the
/// first answer wins and the notification goes away.
final class CommandConfirmation: NSObject, UNUserNotificationCenterDelegate {
    enum Decision {
        case accept, deny
    }

    static let shared = CommandConfirmation()

    private static let categoryID = "dev.pplanel.vox.command"
    private static let acceptID = "accept"
    private static let denyID = "deny"

    /// Called with the id passed to `ask` when a button is clicked.
    var onDecision: ((UUID, Decision) -> Void)?

    private var center: UNUserNotificationCenter { .current() }

    /// Call at launch, before it finishes, so clicks on a notification left from a previous
    /// run are delivered too.
    func register() {
        center.delegate = self
        let accept = UNNotificationAction(identifier: Self.acceptID, title: "Executar", options: [])
        let deny = UNNotificationAction(identifier: Self.denyID, title: "Cancelar", options: [.destructive])
        center.setNotificationCategories([
            // `customDismissAction`: closing the notification counts as "Cancelar".
            UNNotificationCategory(identifier: Self.categoryID, actions: [accept, deny], intentIdentifiers: [],
                                   options: [.customDismissAction]),
        ])
    }

    /// Posts the confirmation for `command`. Returns false when notifications aren't allowed,
    /// so the caller can fall back to the voice answer alone.
    func ask(_ command: PreparedCommand, id: UUID) async -> Bool {
        do {
            guard try await center.requestAuthorization(options: [.alert, .sound]) else {
                log.info("Notifications not allowed")
                return false
            }
            let content = UNMutableNotificationContent()
            content.title = "Rodar comando?"
            content.subtitle = [command.title, command.template.target.displayName, command.issueID]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            content.body = command.command
            content.categoryIdentifier = Self.categoryID
            content.sound = .default
            content.interruptionLevel = .active
            try await center.add(UNNotificationRequest(identifier: id.uuidString, content: content, trigger: nil))
            return true
        } catch {
            log.error("Confirmation notification failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Removes the notification once the command was answered some other way.
    func dismiss(_ id: UUID) {
        center.removeDeliveredNotifications(withIdentifiers: [id.uuidString])
        center.removePendingNotificationRequests(withIdentifiers: [id.uuidString])
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Vox may be the active app (Settings open); show the banner anyway.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    /// Clicking the notification itself (not a button) decides nothing: the command still
    /// waits for a button or "vox sim".
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let decision: Decision
        switch response.actionIdentifier {
        case Self.acceptID: decision = .accept
        case Self.denyID, UNNotificationDismissActionIdentifier: decision = .deny
        default: return
        }
        guard let id = UUID(uuidString: response.notification.request.identifier) else { return }
        await MainActor.run {
            onDecision?(id, decision)
        }
    }
}
