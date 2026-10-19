// SPDX-License-Identifier: GPL-3.0-or-later

import ClamshellCore
import SwiftUI

/// Plays the current game, arranging the two screens for the device's posture.
struct GameView: View {
    let model: EmulatorModel
    @Environment(\.displayScale) private var displayScale
    @State private var hingeClosed = false

    var body: some View {
        GeometryReader { proxy in
            let container = CGRect(origin: .zero, size: proxy.size)
            let layout = ScreenLayout(container: container, posture: posture(in: proxy),
                                      displayScale: displayScale)
            GameScreenView(session: model.session, layout: layout)
        }
        .background(.black)
        .modifier(HingeObserver(isClosed: $hingeClosed))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") { model.closeGame() }
            }
        }
        .navigationTitle(model.currentGame?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .persistentSystemOverlays(.hidden)
    }

    private func posture(in proxy: GeometryProxy) -> ScreenPosture {
        if #available(iOS 27.1, *),
           let fold = proxy.reservedRegions(kind: .division).first(where: \.isActive) {
            return .clamshell(fold: fold.frame)
        }
        // Closed (cover display) always stacks; otherwise follow the window's shape.
        if hingeClosed { return .stacked }
        return proxy.size.width > proxy.size.height * 1.2 ? .sideBySide : .stacked
    }
}

/// Tracks whether a foldable device is closed (iOS 27.1+; never closed elsewhere).
private struct HingeObserver: ViewModifier {
    @Binding var isClosed: Bool

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, new in
                isClosed = new.hinge?.status == .closed
            }
        } else {
            content
        }
    }
}
