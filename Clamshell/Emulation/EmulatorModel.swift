// SPDX-License-Identifier: GPL-3.0-or-later

import ClamshellCore
import Foundation
import Observation
import OSLog
import UIKit

/// A game file the user imported into the app's library.
struct GameFile: Identifiable, Hashable {
    let url: URL
    /// The icon and title stored in the game file, if it has a banner.
    var banner: GameBanner?

    var id: URL { url }
    /// File name without extension (also what `-ClamshellAutoplay` matches).
    var name: String { url.deletingPathExtension().lastPathComponent }
    /// The game's own title when it has one, otherwise the file name.
    var displayTitle: String { banner?.titleLines.first ?? name }
    /// Remaining banner lines (usually subtitle and author).
    var subtitle: String? {
        guard let lines = banner?.titleLines, lines.count > 1 else { return nil }
        return lines.dropFirst().joined(separator: " · ")
    }

    static func == (lhs: GameFile, rhs: GameFile) -> Bool { lhs.url == rhs.url }
    func hash(into hasher: inout Hasher) { hasher.combine(url) }
}

/// Owns the emulation session and the user's game library.
@Observable
final class EmulatorModel {
    private static let logger = Logger(subsystem: "com.foldingduo.Clamshell", category: "Emulator")

    let session: EmulationSession
    let router: InputRouter
    let controllers: GameControllerInput
    let settings: AppSettings
    private(set) var library: [GameFile] = []
    private(set) var currentGame: GameFile?
    var errorMessage: String?

    /// Lid closed by the player's button.
    var isLidClosedManually = false { didSet { applyLid() } }
    private(set) var isLidClosed = false
    /// True while the running game has its microphone open (the Blow button shows then).
    private(set) var isMicrophoneActive = false
    @ObservationIgnored private let microphone: MicrophoneInput
    @ObservationIgnored private var hingeLid = HingeLidTracker()
    @ObservationIgnored private var hasExplainedMicrophoneDenial = false

    /// SHA-1 of the running game, used for saves and save states.
    @ObservationIgnored private var romID: String?
    static let saveStateSlotCount = 4
    /// Hidden slot holding "where you left off" (written on background and on close).
    private static let resumeSlot = 99

    /// The game to offer under "Continue", if its resume state and file still exist.
    private(set) var resumeGame: GameFile?
    private(set) var resumeDate: Date?
    /// True while a game is being closed (its resume state is being written).
    private(set) var isClosing = false

    private struct ResumeInfo: Codable {
        var fileName: String
        var romID: String
    }
    private static let resumeKey = "resume"

    @ObservationIgnored private var audioOutput: AudioOutput?

    /// Imported games live in Documents/Games (visible in the Files app).
    static let gamesDirectory = URL.documentsDirectory.appending(path: "Games", directoryHint: .isDirectory)
    /// Battery saves live in Documents/Saves, so players can back them up through Files.
    private static let saveStore = SaveStore(directory: URL.documentsDirectory.appending(path: "Saves"))
    /// Serial so saves for one game are written in order; off the emulation thread.
    private static let saveQueue = DispatchQueue(label: "com.foldingduo.Clamshell.saves", qos: .utility)
    /// Save states live in Documents/States/<rom id>/slot-N.state (+ .png thumbnail).
    private static let stateStore = StateStore(directory: URL.documentsDirectory.appending(path: "States"))
    /// Per-game SD card images for homebrew (DLDI). Large but sparse, so kept out of Documents.
    private static let sdCardDirectory = URL.applicationSupportDirectory.appending(path: "SDCards", directoryHint: .isDirectory)

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
        let microphone = MicrophoneInput()
        self.microphone = microphone
        session = EmulationSession(microphone: microphone, rumble: RumbleOutput())
        router = InputRouter(session: session)
        controllers = GameControllerInput(router: router)
        microphone.onPermissionDenied = { [weak self] in
            Task { @MainActor in
                guard let self, !self.hasExplainedMicrophoneDenial else { return }
                self.hasExplainedMicrophoneDenial = true
                self.errorMessage = String(localized: "Microphone access is off, so the game hears silence. Use the Blow button, or turn access on in Settings.")
            }
        }
        microphone.onActiveChanged = { [weak self] active in
            Task { @MainActor in
                self?.isMicrophoneActive = active
                if !active { self?.setBlowing(false) }
            }
        }
    }

    /// While true, the game hears a recorded blow instead of the microphone.
    func setBlowing(_ blowing: Bool) {
        microphone.isBlowing = blowing
    }

    /// Re-applies the lid after the "Folding Closes Lid" setting changes.
    func foldSettingChanged() {
        applyLid()
    }

    func refreshLibrary() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: Self.gamesDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        // Banners are ~1 KB reads each, so this stays fast for large libraries.
        library = files
            .filter { $0.pathExtension.lowercased() == "nds" }
            .map { GameFile(url: $0, banner: GameBanner.read(from: $0)) }
            .sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
        refreshResume()
    }

    private func refreshResume() {
        guard let data = UserDefaults.standard.data(forKey: Self.resumeKey),
              let info = try? JSONDecoder().decode(ResumeInfo.self, from: data),
              let game = library.first(where: { $0.url.lastPathComponent == info.fileName }),
              case let slot = Self.stateStore.slot(romID: info.romID, index: Self.resumeSlot),
              !slot.isEmpty
        else {
            resumeGame = nil
            resumeDate = nil
            return
        }
        resumeGame = game
        resumeDate = slot.date
    }

    /// Removes the game file. Its battery save and save states stay, so re-importing the same
    /// game picks them up again.
    func deleteGame(_ game: GameFile) {
        if resumeGame == game { UserDefaults.standard.removeObject(forKey: Self.resumeKey) }
        do {
            try FileManager.default.removeItem(at: game.url)
        } catch {
            Self.logger.error("Delete failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = String(localized: "The game couldn’t be deleted.")
        }
        refreshLibrary()
    }

    /// A game opened from Files or the share sheet: import it, then play it.
    func openExternalGame(_ url: URL) async {
        guard url.pathExtension.lowercased() == "nds" else { return }
        if currentGame != nil { await closeGame() }
        importGame(from: url)
        if let game = library.first(where: { $0.url.lastPathComponent == url.lastPathComponent }) {
            play(game)
        }
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
            try? FileManager.default.createDirectory(at: Self.sdCardDirectory, withIntermediateDirectories: true)
            try session.start(rom: rom, save: store.load(identifier: saveID),
                              name: game.url.lastPathComponent,
                              sdCard: Self.sdCardDirectory.appending(path: "\(saveID).img"),
                              rumblePak: settings.rumblePak) { memory in
                queue.async {
                    do {
                        try store.write(memory, identifier: saveID)
                    } catch {
                        Self.logger.error("Save failed: \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
            currentGame = game
            romID = saveID
            hingeLid.reset()
            isLidClosedManually = false
            startAudio()
        } catch {
            Self.logger.error("Couldn't start game: \(String(describing: error), privacy: .public)")
            errorMessage = String(localized: "This file isn’t a game Clamshell can run.")
        }
    }

    /// Writes "where you left off", then stops the game (which also flushes its battery save).
    func closeGame() async {
        guard currentGame != nil, !isClosing else { return }
        isClosing = true
        defer { isClosing = false }
        router.releaseAll()
        audioOutput?.stop()
        await saveResumeState()
        session.stop()
        currentGame = nil
        romID = nil
        refreshResume()
    }

    /// Continues the "Continue" game from its resume state.
    func resume() async {
        guard let game = resumeGame else { return }
        play(game)
        guard let romID, currentGame == game else { return }
        do {
            let state = try Self.stateStore.read(romID: romID, slot: Self.resumeSlot)
            try await session.loadState(state)
        } catch {
            Self.logger.error("Resume failed: \(String(describing: error), privacy: .public)")
            errorMessage = String(localized: "Couldn’t pick up where you left off, so the game started from the beginning.")
        }
    }

    private func saveResumeState() async {
        guard let romID, let game = currentGame else { return }
        do {
            let state = try await session.saveState()
            let thumbnail = session.frames.latestFrame()?.pngData()
            try Self.stateStore.write(state, thumbnail: thumbnail, romID: romID, slot: Self.resumeSlot)
            let info = ResumeInfo(fileName: game.url.lastPathComponent, romID: romID)
            UserDefaults.standard.set(try JSONEncoder().encode(info), forKey: Self.resumeKey)
        } catch {
            Self.logger.error("Resume save failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Lid

    /// Feed the device hinge angle (iOS 27.1+, foldable devices).
    func hingeAngleChanged(degrees: Double) {
        hingeLid.update(angleDegrees: degrees)
        applyLid()
    }

    private func applyLid() {
        let closed = isLidClosedManually || (settings.foldClosesLid && hingeLid.isClosed)
        guard closed != isLidClosed else { return }
        isLidClosed = closed
        session.setLidClosed(closed)
    }

    // MARK: Save states

    func saveStateSlots() -> [StateStore.Slot] {
        guard let romID else { return [] }
        return Self.stateStore.slots(romID: romID, count: Self.saveStateSlotCount)
    }

    func saveState(slot: Int) async {
        guard let romID else { return }
        do {
            let state = try await session.saveState()
            let thumbnail = session.frames.latestFrame()?.pngData()
            try Self.stateStore.write(state, thumbnail: thumbnail, romID: romID, slot: slot)
        } catch {
            Self.logger.error("Save state failed: \(String(describing: error), privacy: .public)")
            errorMessage = String(localized: "The state couldn’t be saved.")
        }
    }

    func loadState(slot: Int) async {
        guard let romID else { return }
        do {
            let state = try Self.stateStore.read(romID: romID, slot: slot)
            try await session.loadState(state)
        } catch {
            Self.logger.error("Load state failed: \(String(describing: error), privacy: .public)")
            errorMessage = String(localized: "This state couldn’t be loaded. It may be from an older version of Clamshell.")
        }
    }

    func deleteState(slot: Int) {
        guard let romID else { return }
        Self.stateStore.delete(romID: romID, slot: slot)
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
            // Remember where the player is, in case the system ends the app in the background.
            let task = UIApplication.shared.beginBackgroundTask(withName: "Resume state", expirationHandler: nil)
            Task {
                await saveResumeState()
                UIApplication.shared.endBackgroundTask(task)
            }
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
