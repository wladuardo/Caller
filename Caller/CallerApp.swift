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
    @UIApplicationDelegateAdaptor(NotificationAppDelegate.self) private var appDelegate
    private let notificationService = NotificationService.shared
    private let systemCallService = SystemCallService.shared

    init() {
        FirebaseBootstrapper.configureIfPossible()
        notificationService.configure()
        systemCallService.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .tint(.blue)
        }
    }
}
