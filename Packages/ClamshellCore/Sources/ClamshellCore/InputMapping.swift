// SPDX-License-Identifier: GPL-3.0-or-later

import GameController

/// Default mappings from Apple game controllers and keyboards to the handheld's buttons.
public enum InputMapping {
    /// Face buttons map by *position*, so the button at the bottom of the diamond is always
    /// the handheld's bottom button (B), whatever the controller labels it.
    public static func keys(from gamepad: GCExtendedGamepad) -> EmulatorKeys {
        var keys: EmulatorKeys = []
        func add(_ key: EmulatorKeys, if pressed: Bool) { if pressed { keys.insert(key) } }

        add(.b, if: gamepad.buttonA.isPressed)       // bottom
        add(.a, if: gamepad.buttonB.isPressed)       // right
        add(.y, if: gamepad.buttonX.isPressed)       // left
        add(.x, if: gamepad.buttonY.isPressed)       // top
        add(.l, if: gamepad.leftShoulder.isPressed || gamepad.leftTrigger.isPressed)
        add(.r, if: gamepad.rightShoulder.isPressed || gamepad.rightTrigger.isPressed)
        add(.start, if: gamepad.buttonMenu.isPressed)
        add(.select, if: gamepad.buttonOptions?.isPressed ?? false)

        let stick = gamepad.leftThumbstick
        let threshold: Float = 0.5
        add(.up, if: gamepad.dpad.up.isPressed || stick.yAxis.value > threshold)
        add(.down, if: gamepad.dpad.down.isPressed || stick.yAxis.value < -threshold)
        add(.left, if: gamepad.dpad.left.isPressed || stick.xAxis.value < -threshold)
        add(.right, if: gamepad.dpad.right.isPressed || stick.xAxis.value > threshold)
        return keys
    }

    /// Keyboard layout used by most handheld emulators: arrows, X/Z for A/B, S/A for X/Y,
    /// Q/W for the shoulders, Return for Start and right Shift for Select.
    public static let keyboard: [GCKeyCode: EmulatorKeys] = [
        .upArrow: .up, .downArrow: .down, .leftArrow: .left, .rightArrow: .right,
        .keyX: .a, .keyZ: .b, .keyS: .x, .keyA: .y,
        .keyQ: .l, .keyW: .r,
        .returnOrEnter: .start, .rightShift: .select,
    ]

    public static func keys(from keyboard: GCKeyboardInput) -> EmulatorKeys {
        Self.keyboard.reduce(into: EmulatorKeys()) { keys, entry in
            if keyboard.button(forKeyCode: entry.key)?.isPressed == true { keys.insert(entry.value) }
        }
    }
}
