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

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
