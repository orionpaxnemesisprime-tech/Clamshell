// SPDX-License-Identifier: GPL-3.0-or-later

import Synchronization

/// Where a button press came from. Each source reports its own complete state; the
/// emulator sees the union, so releasing a key on one device doesn't cancel another.
public enum InputSource: Sendable, Hashable, CaseIterable {
    case touchControls
    case gamepad
    case keyboard
}

/// Merges button state from every input source into one key mask for the session.
public final class InputRouter: Sendable {
    private let session: EmulationSession
    private let state = Mutex<[InputSource: EmulatorKeys]>([:])

    public init(session: EmulationSession) {
        self.session = session
    }

    /// Replaces the full set of keys held on `source`.
    public func set(_ keys: EmulatorKeys, from source: InputSource) {
        let merged = state.withLock { state in
            state[source] = keys
            return state.values.reduce(into: EmulatorKeys()) { $0.formUnion($1) }
        }
        session.setKeys(merged)
    }

    /// The merged keys currently held.
    public var keys: EmulatorKeys {
        state.withLock { $0.values.reduce(into: EmulatorKeys()) { $0.formUnion($1) } }
    }

    public func releaseAll() {
        state.withLock { $0.removeAll() }
        session.setKeys([])
    }
}
