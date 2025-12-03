//
//  tedee_exampleApp.swift
//  tedee example
//
//  Created by Mateusz Samosij on 21/02/2024.
//

import SwiftUI

@main
struct tedee_exampleApp: App {
    @State private var viewModel = ContentViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .task {
                    // Initialize notification manager on main thread
                    let notificationManager = NotificationManager.shared

                    // Setup notification categories
                    notificationManager.setupNotificationCategories()

                    // Request authorization
                    do {
                        try await notificationManager.requestAuthorization()

                        // Show persistent notification
                        try await notificationManager.showPersistentNotification()
                    } catch {
                        print("Notification setup error: \(error)")
                    }

                    // Setup notification action handler
                    NotificationManager.shared.onActionReceived = { actionIdentifier in
                        await self.viewModel.handleNotificationAction(actionIdentifier)
                    }
                }
        }
    }
}

