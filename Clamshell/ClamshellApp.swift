//
//  ClamshellApp.swift
//  Clamshell
//
//  Created by Optimus Prime on 10/19/26.
//

import SwiftUI

@main
struct ClamshellApp: App {
    // Installs the scene delegate that answers per-scene orientation (see OrientationLock).
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate

    init() {
        // Configures RevenueCat early so it can finish any interrupted tip purchase.
        _ = TipJar.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
