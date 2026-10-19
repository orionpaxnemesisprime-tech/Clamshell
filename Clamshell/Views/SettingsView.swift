// SPDX-License-Identifier: GPL-3.0-or-later

import ClamshellCore
import SwiftUI

/// Preferences, plus About (disclaimer, source code and licences).
struct SettingsView: View {
    let model: EmulatorModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = model.settings
        NavigationStack {
            Form {
                Section {
                    Toggle("Always Show On-Screen Controls", isOn: $settings.alwaysShowTouchControls)
                } header: {
                    Text("Controls")
                } footer: {
                    Text("Otherwise the on-screen controls hide while you play with a game controller, and come back when you touch the screen.")
                }

                Section("Display") {
                    Toggle("Smooth Scaling", isOn: $settings.smoothScaling)
                }

                Section {
                    Toggle("Rumble Pak", isOn: $settings.rumblePak)
                } header: {
                    Text("Accessories")
                } footer: {
                    Text(RumbleOutput.isSupported
                         ? "Games that support a Rumble Pak vibrate the device. Takes effect the next time a game starts."
                         : "This device can’t vibrate, so Rumble Pak games play without vibration.")
                }

                Section {
                    Toggle("Folding Closes Lid", isOn: $settings.foldClosesLid)
                        .onChange(of: settings.foldClosesLid) { model.foldSettingChanged() }
                } header: {
                    Text("Foldable Devices")
                } footer: {
                    Text("Folding the device almost shut closes the console’s lid, which puts many games to sleep. You can also close the lid from the game menu.")
                }

                Section {
                    NavigationLink("About Clamshell") { AboutView() }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
