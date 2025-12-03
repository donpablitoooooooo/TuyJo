//
//  NotificationManager.swift
//  tedee example
//
//  Created for persistent lock control notification
//

import Foundation
import UserNotifications
import UIKit

@MainActor
class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    // Action identifiers
    static let openActionIdentifier = "OPEN_LOCK"
    static let closeActionIdentifier = "CLOSE_LOCK"
    static let pullSpringActionIdentifier = "PULL_SPRING"

    // Notification identifier
    private let persistentNotificationIdentifier = "tedee_lock_control"

    // Callback for handling actions
    var onActionReceived: ((String) async -> Void)?

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    // Request notification permissions
    func requestAuthorization() async throws {
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        if !granted {
            throw NSError(domain: "NotificationManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Notification permission denied"])
        }
    }

    // Setup notification categories with actions
    func setupNotificationCategories() {
        let openAction = UNNotificationAction(
            identifier: Self.openActionIdentifier,
            title: "🔓 Apri",
            options: [.foreground]
        )

        let closeAction = UNNotificationAction(
            identifier: Self.closeActionIdentifier,
            title: "🔒 Chiudi",
            options: [.foreground]
        )

        let pullSpringAction = UNNotificationAction(
            identifier: Self.pullSpringActionIdentifier,
            title: "🔄 Pull Spring",
            options: [.foreground]
        )

        let category = UNNotificationCategory(
            identifier: "LOCK_CONTROL",
            actions: [openAction, closeAction, pullSpringAction],
            intentIdentifiers: [],
            options: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    // Show persistent notification
    func showPersistentNotification() async throws {
        let content = UNMutableNotificationContent()
        content.title = "Tedee Lock Control"
        content.body = "Controllo rapido del tuo lock"
        content.categoryIdentifier = "LOCK_CONTROL"
        content.sound = nil

        // Create a trigger that fires immediately
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

        let request = UNNotificationRequest(
            identifier: persistentNotificationIdentifier,
            content: content,
            trigger: trigger
        )

        try await UNUserNotificationCenter.current().add(request)
    }

    // Remove persistent notification
    func removePersistentNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [persistentNotificationIdentifier])
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [persistentNotificationIdentifier])
    }

    // MARK: - UNUserNotificationCenterDelegate

    // Handle notification when app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .list]
    }

    // Handle notification action response
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let actionIdentifier = response.actionIdentifier

        // Call the action handler on main actor
        await MainActor.run {
            Task {
                await self.onActionReceived?(actionIdentifier)

                // Re-show the notification after action
                try? await self.showPersistentNotification()
            }
        }
    }
}
