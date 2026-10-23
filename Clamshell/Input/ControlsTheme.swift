// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UIKit

/// Preset colours for the game screen: the background around the two screens and the
/// on-screen controls. Original palettes only, never a console's own colours.
enum ControlsTheme: String, CaseIterable, Identifiable {
    case midnight, ocean, ember, forest, dusk, paper, highContrast

    var id: Self { self }

    var name: LocalizedStringResource {
        switch self {
        case .midnight: "Midnight"
        case .ocean: "Ocean"
        case .ember: "Ember"
        case .forest: "Forest"
        case .dusk: "Dusk"
        case .paper: "Paper"
        case .highContrast: "High Contrast"
        }
    }

    /// Fills the area around the screens.
    var background: UIColor {
        switch self {
        case .midnight, .highContrast: .black
        case .ocean: UIColor(rgb: 0x0B1E33)
        case .ember: UIColor(rgb: 0x1F0F0A)
        case .forest: UIColor(rgb: 0x0E1F14)
        case .dusk: UIColor(rgb: 0x1A1428)
        case .paper: UIColor(rgb: 0xF2EDE3)
        }
    }

    /// Appearance of the navigation bar and status bar over `background`.
    var colorScheme: ColorScheme { self == .paper ? .light : .dark }

    /// Button colour at rest, drawn at `buttonOpacity`.
    var button: UIColor {
        switch self {
        case .midnight, .highContrast: .white
        case .ocean: UIColor(rgb: 0x5FB4E6)
        case .ember: UIColor(rgb: 0xF07A3C)
        case .forest: UIColor(rgb: 0x6CC08B)
        case .dusk: UIColor(rgb: 0xB49CF0)
        case .paper: UIColor(rgb: 0x3A3A3C)
        }
    }

    /// Button colour while pressed, drawn more opaque than at rest.
    var pressed: UIColor {
        switch self {
        case .midnight: .white
        case .ocean: UIColor(rgb: 0x9EE0FF)
        case .ember: UIColor(rgb: 0xFFB347)
        case .forest: UIColor(rgb: 0xB6F0A0)
        case .dusk: UIColor(rgb: 0xE0C8FF)
        case .paper: UIColor(rgb: 0x3A3A3C)
        case .highContrast: UIColor(rgb: 0xFFD60A)
        }
    }

    /// Button labels.
    var ink: UIColor {
        switch self {
        case .paper: UIColor(rgb: 0x1C1C1E).withAlphaComponent(0.9)
        case .highContrast: .black
        default: UIColor.white.withAlphaComponent(0.9)
        }
    }

    /// Opacity of a resting button beside or below the screens. Overlaid on the screens it is
    /// fainter, so the game stays visible.
    var buttonOpacity: CGFloat {
        switch self {
        case .midnight: 0.28
        case .paper: 0.18
        case .highContrast: 0.85
        default: 0.32
        }
    }
}

extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
