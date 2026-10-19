// SPDX-License-Identifier: GPL-3.0-or-later

import ClamshellCore
import SwiftUI

/// Plays the current game, arranging the two screens for the device's posture.
struct GameView: View {
    let model: EmulatorModel
    @Environment(\.displayScale) private var displayScale
    @State private var hingeClosed = false
    @State private var isShowingStates = false

    var body: some View {
        GeometryReader { proxy in
            let container = CGRect(origin: .zero, size: proxy.size)
            let layout = GameLayout(container: container, posture: posture(in: proxy),
                                    displayScale: displayScale,
                                    showsControls: !model.controllers.isUsingGamepad)
            ZStack {
                // Touching the screen brings the on-screen controls back after gamepad play.
                GameScreenView(session: model.session, layout: layout.screens) {
                    model.controllers.isUsingGamepad = false
                }
                if let controls = layout.controls {
                    TouchControls(layout: controls, router: model.router)
                }
            }
        }
        .background(.black)
        .modifier(HingeObserver(isClosed: $hingeClosed) { degrees in
            model.hingeAngleChanged(degrees: degrees)
        })
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") { model.closeGame() }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("Game", systemImage: "ellipsis") {
                    Button("Save States…", systemImage: "square.stack") { isShowingStates = true }
                    Button(model.isLidClosedManually ? "Open Lid" : "Close Lid",
                           systemImage: model.isLidClosedManually ? "laptopcomputer" : "laptopcomputer.slash") {
                        model.isLidClosedManually.toggle()
                    }
                    Toggle("Folding Closes Lid", systemImage: "iphone.gen3",
                           isOn: Binding(get: { model.foldClosesLid }, set: { model.foldClosesLid = $0 }))
                }
            }
        }
        .sheet(isPresented: $isShowingStates) {
            SaveStatesView(model: model)
        }
        .onChange(of: isShowingStates) { _, showing in
            model.session.isPaused = showing
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

/// Tracks a foldable device's hinge (iOS 27.1+; never closed elsewhere).
private struct HingeObserver: ViewModifier {
    @Binding var isClosed: Bool
    /// Hinge angle in degrees (180 = fully open, 0 = closed).
    let onAngle: (Double) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, new in
                isClosed = new.hinge?.status == .closed
                if let hinge = new.hinge { onAngle(hinge.angle.degrees) }
            }
        } else {
            content
        }
    }
}
