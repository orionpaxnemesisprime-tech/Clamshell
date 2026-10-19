// SPDX-License-Identifier: GPL-3.0-or-later

import ClamshellCore
import SwiftUI
import UniformTypeIdentifiers

/// Games the user has imported. Clamshell ships no games and never downloads any.
struct LibraryView: View {
    let model: EmulatorModel
    @State private var isImporting = false
    @State private var isShowingSettings = false
    @State private var pendingDelete: GameFile?

    private static let gameTypes: [UTType] = [UTType(filenameExtension: "nds") ?? .data]

    var body: some View {
        List(model.library) { game in
            Button { model.play(game) } label: {
                GameRow(game: game)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain) // keep title/subtitle colours instead of the accent tint
            .swipeActions {
                Button("Delete", role: .destructive) { pendingDelete = game }
            }
        }
        .overlay {
            if model.library.isEmpty {
                ContentUnavailableView {
                    Label("No Games", systemImage: "rectangle.split.1x2")
                } description: {
                    Text("Import game files you have the right to use. Clamshell doesn’t include any games.")
                } actions: {
                    Button("Import Games") { isImporting = true }
                }
            }
        }
        .navigationTitle("Library")
        .toolbar {
            Button("Import Games", systemImage: "plus") { isImporting = true }
            Button("Settings", systemImage: "gearshape") { isShowingSettings = true }
        }
        .sheet(isPresented: $isShowingSettings) { SettingsView(model: model) }
        .confirmationDialog("Delete this game?", isPresented: Binding(
            get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }
        ), presenting: pendingDelete) { game in
            Button("Delete \(game.displayTitle)", role: .destructive) { model.deleteGame(game) }
        } message: { _ in
            Text("Its saves and save states are kept, so importing it again brings them back.")
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: Self.gameTypes,
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                urls.forEach(model.importGame)
            }
        }
        .task { model.refreshLibrary() }
        .refreshable { model.refreshLibrary() }
    }
}

private struct GameRow: View {
    let game: GameFile

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(game.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let subtitle = game.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private var icon: some View {
        if let image = game.banner?.iconImage() {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.none)
        } else {
            Image(systemName: "rectangle.split.1x2")
                .font(.title2)
                .foregroundStyle(.secondary)
        }
    }
}
