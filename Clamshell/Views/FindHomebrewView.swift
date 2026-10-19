// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UIKit

/// An original homebrew game its author offers for free download on their own page.
///
/// Clamshell only *links* to that page: it never hosts, downloads or redistributes games.
/// Entries live in `Homebrew/homebrew-catalog.json` (compiled into the app, so App Review sees
/// exactly what is linked). The rules for adding one are in the app-store-compliance skill;
/// verify each game boots with `swift run clamshell-catalog` first. An icon is bundled only
/// when the game's licence clearly allows redistributing its art.
struct HomebrewGame: Identifiable, Decodable, Hashable {
    let id: String
    let title: String
    let author: String
    let genre: String
    let summary: String
    let licence: String
    let page: URL
    let note: String?
    /// Whether `homebrew-<id>.png` (the game's own banner icon) is bundled.
    let icon: Bool

    static let catalog: [HomebrewGame] = {
        guard let url = Bundle.main.url(forResource: "homebrew-catalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let games = try? JSONDecoder().decode([HomebrewGame].self, from: data)
        else { return [] }
        return games.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }()

    var iconImage: UIImage? {
        guard icon, let url = Bundle.main.url(forResource: "homebrew-\(id)", withExtension: "png") else { return nil }
        return UIImage(contentsOfFile: url.path(percentEncoded: false))
    }

    /// Symbol shown when no icon is bundled.
    var genreSymbol: String {
        switch genre {
        case "Shooter": "scope"
        case "Puzzle": "puzzlepiece.extension"
        case "Platformer": "figure.run"
        case "RPG": "shield.lefthalf.filled"
        case "Adventure": "map"
        case "Action": "bolt"
        case "Arcade": "gamecontroller"
        case "Racing": "flag.checkered"
        case "Sports": "sportscourt"
        case "Strategy": "checkerboard.rectangle"
        case "Card & Board": "suit.club"
        case "Music": "music.note"
        default: "sparkles"
        }
    }

    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return [title, author, genre, summary].contains { $0.localizedStandardContains(query) }
    }
}

/// Links to original homebrew on its authors' own pages. Players download a game in Safari,
/// then open it in Clamshell.
struct FindHomebrewView: View {
    @State private var query = ""
    @State private var genre: String?

    private let games = HomebrewGame.catalog

    private var genres: [String] {
        Array(Set(games.map(\.genre))).sorted()
    }

    private var results: [HomebrewGame] {
        games.filter { (genre == nil || $0.genre == genre) && $0.matches(query) }
    }

    var body: some View {
        List {
            Section {
                GenreFilter(genres: genres, selection: $genre)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
            }

            Section {
                ForEach(results) { game in
                    HomebrewRow(game: game)
                }
            } header: {
                Text(results.count == 1 ? "1 Game" : "\(results.count) Games")
            } footer: {
                Text("These games are made and published by their authors. Clamshell doesn’t host or download them; you get them from each author’s page, under the licence they publish.")
            }

            if query.isEmpty, genre == nil {
                Section("How to Play One") {
                    Label("Open the game’s page and download the latest version of the game file.", systemImage: "1.circle")
                    Label("Tap the downloaded file and choose Open in Clamshell, or use Import Games in the Library.", systemImage: "2.circle")
                }
            }
        }
        .overlay {
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, prompt: "Games, authors or genres")
        .navigationTitle("Find Homebrew")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct GenreFilter: View {
    let genres: [String]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", selected: selection == nil) { selection = nil }
                ForEach(genres, id: \.self) { genre in
                    chip(genre, selected: selection == genre) { selection = selection == genre ? nil : genre }
                }
            }
            .padding(.horizontal)
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selected ? Color.accentColor : Color(.secondarySystemGroupedBackground), in: .capsule)
                .foregroundStyle(selected ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct HomebrewRow: View {
    let game: HomebrewGame

    var body: some View {
        Link(destination: game.page) {
            HStack(alignment: .top, spacing: 14) {
                icon
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(game.title)
                            .font(.headline)
                        Spacer(minLength: 4)
                        Image(systemName: "arrow.up.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                    Text(game.author)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(game.summary)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        Tag(text: game.genre)
                        Tag(text: game.licence)
                    }
                    .padding(.top, 2)
                    if let note = game.note {
                        Text(note)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the author’s page in Safari")
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
            if let image = game.iconImage {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .padding(6)
            } else {
                Image(systemName: game.genreSymbol)
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 60, height: 60)
        .accessibilityHidden(true)
    }
}

private struct Tag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.fill.tertiary, in: .capsule)
            .foregroundStyle(.secondary)
    }
}
