// SPDX-License-Identifier: GPL-3.0-or-later

import ClamshellCore
import Foundation
import Observation
import OSLog

/// A game file the user imported into the app's library.
struct GameFile: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

/// Owns the emulation session and the user's game library.
@Observable
final class EmulatorModel {
    private static let logger = Logger(subsystem: "com.foldingduo.Clamshell", category: "Emulator")

    let session = EmulationSession()
    private(set) var library: [GameFile] = []
    private(set) var currentGame: GameFile?
    var errorMessage: String?

    @ObservationIgnored private var audioOutput: AudioOutput?

    /// Imported games live in Documents/Games (visible in the Files app).
    static let gamesDirectory = URL.documentsDirectory.appending(path: "Games", directoryHint: .isDirectory)

    func refreshLibrary() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: Self.gamesDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        library = files
            .filter { $0.pathExtension.lowercased() == "nds" }
            .map(GameFile.init)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Copies a user-selected file into the library. Clamshell never downloads games.
    func importGame(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try FileManager.default.createDirectory(at: Self.gamesDirectory, withIntermediateDirectories: true)
            let destination = Self.gamesDirectory.appending(path: url.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            refreshLibrary()
        } catch {
            Self.logger.error("Import failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = String(localized: "The file couldn’t be imported.")
        }
    }

    func play(_ game: GameFile) {
        do {
            let rom = Array(try Data(contentsOf: game.url))
            try session.start(rom: rom, name: game.url.lastPathComponent)
            currentGame = game
            startAudio()
        } catch {
            Self.logger.error("Couldn't start game: \(String(describing: error), privacy: .public)")
            errorMessage = String(localized: "This file isn’t a game Clamshell can run.")
        }
    }

    func closeGame() {
        session.stop()
        audioOutput?.stop()
        currentGame = nil
    }

    /// Pauses emulation and audio while the scene is inactive.
    func setSceneActive(_ active: Bool) {
        guard currentGame != nil else { return }
        session.isPaused = !active
        if active {
            startAudio()
        } else {
            audioOutput?.stop()
        }
    }

    private func startAudio() {
        if audioOutput == nil {
            audioOutput = AudioOutput(ring: session.audio, sampleRate: session.audioSampleRate)
        }
        session.audio.flush()
        do {
            try audioOutput?.start()
        } catch {
            // Games still run without sound.
            Self.logger.error("Audio unavailable: \(error.localizedDescription, privacy: .public)")
        }
    }
}
