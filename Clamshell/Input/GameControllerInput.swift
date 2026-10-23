// SPDX-License-Identifier: GPL-3.0-or-later

import ClamshellCore
import GameController
import Observation
import OSLog

/// Feeds game controllers and hardware keyboards into the input router.
@Observable
final class GameControllerInput {
    /// True once a gamepad has actually been used; on-screen controls hide then. Merely being
    /// connected isn't enough: the Simulator, for one, always reports a virtual gamepad.
    var isUsingGamepad = false

    private static let logger = Logger(subsystem: "com.foldingduo.Clamshell", category: "Input")

    @ObservationIgnored private let router: InputRouter
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(router: InputRouter) {
        self.router = router
        let center = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect,
                     .GCKeyboardDidConnect, .GCKeyboardDidDisconnect] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
        refresh()
    }

    private func refresh() {
        let gamepads = GCController.controllers().compactMap(\.extendedGamepad)
        Self.logger.debug("Gamepads: \(gamepads.count), keyboard: \(GCKeyboard.coalesced != nil)")
        let router = router

        for gamepad in gamepads {
            gamepad.valueChangedHandler = { [weak self] gamepad, _ in
                let keys = InputMapping.keys(from: gamepad)
                router.set(keys, from: .gamepad)
                if !keys.isEmpty {
                    MainActor.assumeIsolated { self?.isUsingGamepad = true }
                }
            }
        }
        if gamepads.isEmpty {
            router.set([], from: .gamepad)
            isUsingGamepad = false
        }

        if let keyboard = GCKeyboard.coalesced?.keyboardInput {
            keyboard.keyChangedHandler = { keyboard, _, _, _ in
                router.set(InputMapping.keys(from: keyboard), from: .keyboard)
            }
        } else {
            router.set([], from: .keyboard)
        }
    }
}
