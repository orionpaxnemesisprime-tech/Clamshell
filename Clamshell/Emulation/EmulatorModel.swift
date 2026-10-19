// SPDX-License-Identifier: GPL-3.0-or-later

import ClamshellCore
import Foundation
import Observation
import OSLog
import UIKit

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
    let router: InputRouter
    let controllers: GameControllerInput
    private(set) var library: [GameFile] = []
    private(set) var currentGame: GameFile?
    var errorMessage: String?

    @ObservationIgnored private var audioOutput: AudioOutput?

    /// Imported games live in Documents/Games (visible in the Files app).
    static let gamesDirectory = URL.documentsDirectory.appending(path: "Games", directoryHint: .isDirectory)
    /// Battery saves live in Documents/Saves, so players can back them up through Files.
    private static let saveStore = SaveStore(directory: URL.documentsDirectory.appending(path: "Saves"))
    /// Serial so saves for one game are written in order; off the emulation thread.
    private static let saveQueue = DispatchQueue(label: "com.foldingduo.Clamshell.saves", qos: .utility)

    init() {
        router = InputRouter(session: session)
        controllers = GameControllerInput(router: router)
    }

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
            let saveID = SaveStore.identifier(for: rom)
            let store = Self.saveStore
            let queue = Self.saveQueue
            try session.start(rom: rom, save: store.load(identifier: saveID),
                              name: game.url.lastPathComponent) { memory in
                queue.async {
                    do {
                        try store.write(memory, identifier: saveID)
                    } catch {
                        Self.logger.error("Save failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
            currentGame = game
            startAudio()
        } catch {
            Self.logger.error("Couldn't start game: \(String(describing: error), privacy: .public)")
            errorMessage = String(localized: "This file isn’t a game Clamshell can run.")
        }
    }

    func closeGame() {
        router.releaseAll()
        session.stop() // flushes any pending save to the save queue
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
            router.releaseAll()
            audioOutput?.stop()
            protectPendingSave()
        }
    }

    /// Keeps the app alive long enough for the paused session to hand over its save and for
    /// the save queue to write it (the session flushes within one pause poll, ~100 ms).
    private func protectPendingSave() {
        // Ended after 250 ms, long before the system's expiry, so no expiration handler.
        let task = UIApplication.shared.beginBackgroundTask(withName: "Write save", expirationHandler: nil)
        // Runs after any save the flush enqueued, because the queue is serial.
        Self.saveQueue.asyncAfter(deadline: .now() + .milliseconds(250)) {
            Task { @MainActor in UIApplication.shared.endBackgroundTask(task) }
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
