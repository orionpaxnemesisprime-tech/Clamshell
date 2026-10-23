// SPDX-License-Identifier: GPL-3.0-or-later

import ClamshellCore
import SwiftUI

/// Plays the current game, arranging the two screens for the device's posture.
struct GameView: View {
    let model: EmulatorModel
    @Environment(\.displayScale) private var displayScale
    @State private var hingeClosed = false
    @State private var hingeFullyOpen = false
    @State private var isShowingStates = false
    @State private var isShowingSettings = false

    var body: some View {
        GeometryReader { proxy in
            let container = CGRect(origin: .zero, size: proxy.size)
            let layout = GameLayout(container: container, posture: posture(in: proxy),
                                    displayScale: displayScale,
                                    showsControls: !model.controllers.isUsingGamepad
                                        || model.settings.alwaysShowTouchControls,
                                    showsBlow: model.isMicrophoneActive)
            ZStack {
                // Touching the screen brings the on-screen controls back after gamepad play.
                GameScreenView(session: model.session, layout: layout.screens,
                               smoothScaling: model.settings.smoothScaling,
                               background: model.settings.controlsTheme.background) {
                    model.controllers.isUsingGamepad = false
                }
                if let controls = layout.controls {
                    TouchControls(layout: controls, router: model.router,
                                  theme: model.settings.controlsTheme,
                                  directionalControl: model.settings.directionalControl) { blowing in
                        model.setBlowing(blowing)
                    }
                }
            }
        }
        .background(Color(uiColor: model.settings.controlsTheme.background))
        .modifier(HingeObserver(isClosed: $hingeClosed, isFullyOpen: $hingeFullyOpen) { degrees in
            model.hingeAngleChanged(degrees: degrees)
        })
        // Fully open, the inner display plays best upright: screens stacked, controls below.
        .portraitLocked(hingeFullyOpen)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") {
                    Task { await model.closeGame() }
                }
                .disabled(model.isClosing)
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("Game", systemImage: "ellipsis") {
                    Button("Save States…", systemImage: "square.stack") { isShowingStates = true }
                    Button(model.isLidClosedManually ? "Open Lid" : "Close Lid",
                           systemImage: model.isLidClosedManually ? "laptopcomputer" : "laptopcomputer.slash") {
                        model.isLidClosedManually.toggle()
                    }
                    Button("Settings…", systemImage: "gearshape") { isShowingSettings = true }
                }
            }
        }
        .sheet(isPresented: $isShowingStates) {
            SaveStatesView(model: model)
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(model: model)
        }
        .onChange(of: isShowingStates || isShowingSettings) { _, showing in
            model.session.isPaused = showing
        }
        .navigationTitle(model.currentGame?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(model.settings.controlsTheme.colorScheme, for: .navigationBar)
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
    @Binding var isFullyOpen: Bool
    /// Hinge angle in degrees (180 = fully open, 0 = closed).
    let onAngle: (Double) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 27.1, *) {
            content.onHingeChange { _, new in
                isClosed = new.hinge?.status == .closed
                isFullyOpen = new.hinge?.status == .fullyOpen
                if let hinge = new.hinge { onAngle(hinge.angle.degrees) }
            }
        } else {
            content
        }
    }
}
