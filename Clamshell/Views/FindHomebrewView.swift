// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// An original, openly licensed homebrew game published by its author.
///
/// Clamshell only *links* to the author's own release page: it never hosts, downloads or
/// redistributes games. Every entry must be original work (not based on another company's
/// game, characters or trademarks), published under a licence that allows people to download
/// it, link to an individual project page (never a list or site that also carries ports of
/// other people's games), and be verified to boot in Clamshell. See the app-store-compliance
/// skill before adding one.
struct HomebrewGame: Identifiable {
    let title: String
    let author: String
    let summary: LocalizedStringKey
    let licence: String
    let releasePage: URL
    /// Extra step the player needs after downloading, if any.
    let note: LocalizedStringKey?

    var id: String { title }

    /// Checked on 2026-10-19: each boots to its title or menu screen in Clamshell.
    static let catalog: [HomebrewGame] = [
        HomebrewGame(
            title: "Space Impakto DS",
            author: "Relminator, Anyatech",
            summary: "A fast vertical shoot-’em-up with dense bullet patterns and a high-score table.",
            licence: "MIT",
            releasePage: URL(string: "https://codeberg.org/SkyLyrac/SpaceImpakto-DS/releases")!,
            note: "The download is a ZIP file. Tap it in the Files app to unzip it, then open the game file."),
        HomebrewGame(
            title: "Traffic Escape DS",
            author: "Warioware64",
            summary: "A 3D sliding-block puzzle: move the cars to clear a path for yours, across 20 levels.",
            licence: "Apache-2.0",
            releasePage: URL(string: "https://github.com/Warioware64/Traffic-Escape-DS/releases")!,
            note: nil),
        HomebrewGame(
            title: "WolveSlayer",
            author: "Firehazard Studio",
            summary: "A 3D hack-and-slash adventure with hand-made textures and music.",
            licence: "MIT (code)",
            releasePage: URL(string: "https://codeberg.org/SkyLyrac/wolveslayer/releases")!,
            note: nil),
        HomebrewGame(
            title: "Tales of Dagur",
            author: "LiraNuna",
            summary: "A complete role-playing adventure made for the handheld.",
            licence: "WTFPL",
            releasePage: URL(string: "https://codeberg.org/SkyLyrac/talesofdagur/releases")!,
            note: nil),
    ]
}

/// Links to original homebrew on its authors' own pages. Players download a game in Safari,
/// then open it in Clamshell.
struct FindHomebrewView: View {
    var body: some View {
        List {
            Section {
                ForEach(HomebrewGame.catalog) { game in
                    HomebrewRow(game: game)
                }
            } footer: {
                Text("These games are made and published by their authors. Clamshell doesn’t host or download them; you get them from the author’s page. Licences listed are as published by the authors.")
            }

            Section("How to Play One") {
                Label("Open the game’s page and download the latest “.nds” file.", systemImage: "1.circle")
                Label("Tap the downloaded file and choose Open in Clamshell, or use Import Games in the Library.", systemImage: "2.circle")
            }
        }
        .navigationTitle("Find Homebrew")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct HomebrewRow: View {
    let game: HomebrewGame

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(game.title)
                .font(.headline)
            Text("By \(game.author) · \(game.licence)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(game.summary)
                .font(.body)
            if let note = game.note {
                Text(note)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Link(destination: game.releasePage) {
                Label("Open Author’s Page", systemImage: "safari")
            }
            .accessibilityLabel("Open \(game.title) author’s page")
            .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}
