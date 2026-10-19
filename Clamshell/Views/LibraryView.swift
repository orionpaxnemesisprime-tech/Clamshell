// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UniformTypeIdentifiers

/// Games the user has imported. Clamshell ships no games and never downloads any.
struct LibraryView: View {
    let model: EmulatorModel
    @State private var isImporting = false
    @State private var isShowingSettings = false

    private static let gameTypes: [UTType] = [UTType(filenameExtension: "nds") ?? .data]

    var body: some View {
        List(model.library) { game in
            Button(game.name) { model.play(game) }
        }
        .overlay {
            if model.library.isEmpty {
                ContentUnavailableView {
                    Label("No Games", systemImage: "rectangle.split.1x2")
                } description: {
                    Text("Import game files you have the right to use. Clamshell doesn’t include any games.")
                } actions: {
                    Button("Import Game") { isImporting = true }
                }
            }
        }
        .navigationTitle("Library")
        .toolbar {
            Button("Import Game", systemImage: "plus") { isImporting = true }
            Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
        }
        .sheet(isPresented: $isShowingSettings) { SettingsView(model: model) }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: Self.gameTypes,
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                urls.forEach(model.importGame)
            }
        }
        .task { model.refreshLibrary() }
    }
}
