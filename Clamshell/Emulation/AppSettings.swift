// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Observation

/// User preferences, persisted in UserDefaults.
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    /// Keep on-screen controls visible even while a game controller is in use.
    var alwaysShowTouchControls: Bool { didSet { defaults.set(alwaysShowTouchControls, forKey: Keys.alwaysShowTouchControls) } }
    /// On-screen D-pad or analog stick.
    var directionalControl: DirectionalControl {
        didSet { defaults.set(directionalControl.rawValue, forKey: Keys.directionalControl) }
    }
    /// Colours of the game screen's background and on-screen controls.
    var controlsTheme: ControlsTheme { didSet { defaults.set(controlsTheme.rawValue, forKey: Keys.controlsTheme) } }
    /// Bilinear filtering instead of crisp pixels.
    var smoothScaling: Bool { didSet { defaults.set(smoothScaling, forKey: Keys.smoothScaling) } }
    /// Insert a Rumble Pak so games that support it can vibrate the device. Applies when a game starts.
    var rumblePak: Bool { didSet { defaults.set(rumblePak, forKey: Keys.rumblePak) } }
    /// Folding the device shut (below ~10°) closes the emulated lid.
    var foldClosesLid: Bool { didSet { defaults.set(foldClosesLid, forKey: Keys.foldClosesLid) } }

    private enum Keys {
        static let alwaysShowTouchControls = "alwaysShowTouchControls"
        static let directionalControl = "directionalControl"
        static let controlsTheme = "controlsTheme"
        static let smoothScaling = "smoothScaling"
        static let rumblePak = "rumblePak"
        static let foldClosesLid = "foldClosesLid"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [Keys.rumblePak: true])
        alwaysShowTouchControls = defaults.bool(forKey: Keys.alwaysShowTouchControls)
        directionalControl = defaults.string(forKey: Keys.directionalControl)
            .flatMap(DirectionalControl.init(rawValue:)) ?? .dpad
        controlsTheme = defaults.string(forKey: Keys.controlsTheme).flatMap(ControlsTheme.init(rawValue:)) ?? .midnight
        smoothScaling = defaults.bool(forKey: Keys.smoothScaling)
        rumblePak = defaults.bool(forKey: Keys.rumblePak)
        foldClosesLid = defaults.bool(forKey: Keys.foldClosesLid)
    }
}
