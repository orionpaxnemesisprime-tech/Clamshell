// SPDX-License-Identifier: GPL-3.0-or-later

import CoreGraphics

/// Screens and on-screen controls laid out together.
public struct GameLayout: Sendable, Equatable {
    public var screens: ScreenLayout
    /// nil when on-screen controls are hidden (e.g. a game controller is connected).
    public var controls: ControlsLayout?

    /// Screens may shrink to at most this fraction of their size to make room for controls
    /// that would otherwise cover them.
    static let minimumScreenScaleForControls: CGFloat = 0.6

    public init(container: CGRect, posture: ScreenPosture, displayScale: CGFloat, showsControls: Bool) {
        let screens = ScreenLayout(container: container, posture: posture, displayScale: displayScale)
        guard showsControls else {
            self.screens = screens
            controls = nil
            return
        }

        let controls = ControlsLayout(container: container, screens: screens)
        self.screens = screens
        self.controls = controls

        // The fold fixes where the screens go; elsewhere, try reserving a band below.
        guard controls.placement == .overlay, !posture.isClamshell else { return }
        var reserved = container
        reserved.size.height -= ControlsLayout.bandHeight
        guard reserved.height > 0 else { return }
        let smaller = ScreenLayout(container: reserved, posture: posture, displayScale: displayScale)
        guard smaller.top.width >= screens.top.width * Self.minimumScreenScaleForControls else { return }
        let roomier = ControlsLayout(container: container, screens: smaller)
        guard roomier.placement != .overlay else { return }
        self.screens = smaller
        self.controls = roomier
    }
}

extension ScreenPosture {
    var isClamshell: Bool {
        if case .clamshell = self { return true }
        return false
    }
}
