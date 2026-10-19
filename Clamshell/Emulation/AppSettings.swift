// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// User preferences, persisted in UserDefaults.
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    /// Keep on-screen controls visible even while a game controller is in use.
    var alwaysShowTouchControls: Bool { didSet { defaults.set(alwaysShowTouchControls, forKey: Keys.alwaysShowTouchControls) } }
    /// Bilinear filtering instead of crisp pixels.
    var smoothScaling: Bool { didSet { defaults.set(smoothScaling, forKey: Keys.smoothScaling) } }
    /// Insert a Rumble Pak so games that support it can vibrate the device. Applies when a game starts.
    var rumblePak: Bool { didSet { defaults.set(rumblePak, forKey: Keys.rumblePak) } }
    /// Folding the device shut (below ~10°) closes the emulated lid.
    var foldClosesLid: Bool { didSet { defaults.set(foldClosesLid, forKey: Keys.foldClosesLid) } }

    private enum Keys {
        static let alwaysShowTouchControls = "alwaysShowTouchControls"
        static let smoothScaling = "smoothScaling"
        static let rumblePak = "rumblePak"
        static let foldClosesLid = "foldClosesLid"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Keys.rumblePak: true])
        alwaysShowTouchControls = defaults.bool(forKey: Keys.alwaysShowTouchControls)
        smoothScaling = defaults.bool(forKey: Keys.smoothScaling)
        rumblePak = defaults.bool(forKey: Keys.rumblePak)
        foldClosesLid = defaults.bool(forKey: Keys.foldClosesLid)
    }
}
