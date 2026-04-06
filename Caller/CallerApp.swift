//
//  CallerApp.swift
//  Caller
//
//  Created by Владислав Ковальский on 05.04.2026.
//

import FirebaseCore
import SwiftUI

@main
struct CallerApp: App {
    private let notificationService = NotificationService()

    init() {
        FirebaseBootstrapper.configureIfPossible()
        notificationService.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(.blue)
                .task {
                    await notificationService.requestAuthorization()
                }
        }
    }
}
