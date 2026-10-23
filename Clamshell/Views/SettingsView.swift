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
                    Picker("Directional Control", selection: $settings.directionalControl) {
                        ForEach(DirectionalControl.allCases) { control in
                            Text(control.name).tag(control)
                        }
                    }
                    Picker("Theme", selection: $settings.controlsTheme) {
                        ForEach(ControlsTheme.allCases) { theme in
                            Label {
                                Text(theme.name)
                            } icon: {
                                ThemeSwatch(theme: theme)
                            }
                            .tag(theme)
                        }
                    }
                    .pickerStyle(.navigationLink)
                } header: {
                    Text("Controls")
                } footer: {
                    Text("Otherwise the on-screen controls hide while you play with a game controller, and come back when you touch the screen. The theme colours the controls and the background around the screens.")
                }

                Section("Display") {
                    Toggle("Smooth Scaling", isOn: $settings.smoothScaling)
                }

                Section {
                    Toggle("Rumble Accessory", isOn: $settings.rumblePak)
                } header: {
                    Text("Accessories")
                } footer: {
                    Text(RumbleOutput.isSupported
                         ? "Games that support the rumble accessory vibrate the device. Takes effect the next time a game starts."
                         : "This device can’t vibrate, so games play without vibration.")
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

/// A theme's background with a resting and a pressed button.
private struct ThemeSwatch: View {
    let theme: ControlsTheme

    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(Color(uiColor: theme.button).opacity(theme.buttonOpacity))
            Circle().fill(Color(uiColor: theme.pressed).opacity(min(1, theme.buttonOpacity + 0.35)))
        }
        .padding(4)
        .frame(width: 30, height: 20)
        .background(Color(uiColor: theme.background), in: .rect(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5).strokeBorder(.separator)
        }
        .accessibilityHidden(true)
    }
}
