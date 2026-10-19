// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation

/// Battery saves on disk, one per game, keyed by the ROM's SHA-1 so renaming or moving a
/// game file keeps its save.
///
/// Each write is atomic and keeps the previous save as `<id>.sav.bak`, so a crash or a bad
/// write can never leave the player with nothing.
public struct SaveStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Stable identifier for a ROM image (lowercase hex SHA-1).
    public static func identifier(for rom: [UInt8]) -> String {
        Insecure.SHA1.hash(data: rom).map { String(format: "%02x", $0) }.joined()
    }

    public func saveURL(for identifier: String) -> URL {
        directory.appending(path: "\(identifier).sav")
    }

    public func backupURL(for identifier: String) -> URL {
        directory.appending(path: "\(identifier).sav.bak")
    }

    /// The stored save, or nil if the game has never saved.
    public func load(identifier: String) -> [UInt8]? {
        (try? Data(contentsOf: saveURL(for: identifier))).map(Array.init)
    }

    public func write(_ save: [UInt8], identifier: String) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = saveURL(for: identifier)
        let backup = backupURL(for: identifier)

        if let existing = try? Data(contentsOf: url) {
            if existing.elementsEqual(save) { return }
            try existing.write(to: backup, options: .atomic)
        }
        try Data(save).write(to: url, options: .atomic)
    }
}
