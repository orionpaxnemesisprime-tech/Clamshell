// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UIKit

/// Per-scene portrait lock, used while a game plays on a fully open foldable.
///
/// iOS 27 asks each scene's delegate for its supported orientations, so the lock is answered
/// by `SceneDelegate`. Scenes that aren't locked keep the Info.plist orientations.
enum OrientationLock {
    private static var portraitScenes: Set<ObjectIdentifier> = []

    static func supportedOrientations(for scene: UIWindowScene) -> UIInterfaceOrientationMask {
        if portraitScenes.contains(ObjectIdentifier(scene)) { return .portrait }
        return scene.traitCollection.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }

    static func setPortraitLocked(_ locked: Bool, in scene: UIWindowScene) {
        let id = ObjectIdentifier(scene)
        guard locked != portraitScenes.contains(id) else { return }
        if locked { portraitScenes.insert(id) } else { portraitScenes.remove(id) }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        // Rotates right away rather than waiting for the next device rotation.
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: supportedOrientations(for: scene)))
    }
}

/// Installs `SceneDelegate` for every window scene.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func supportedInterfaceOrientations(for windowScene: UIWindowScene) -> UIInterfaceOrientationMask {
        OrientationLock.supportedOrientations(for: windowScene)
    }
}

extension View {
    /// Locks this view's scene to portrait while `isLocked` is true and the view is on screen.
    func portraitLocked(_ isLocked: Bool) -> some View {
        modifier(PortraitLock(isLocked: isLocked))
    }
}

private struct PortraitLock: ViewModifier {
    let isLocked: Bool
    @State private var scene: UIWindowScene?

    func body(content: Content) -> some View {
        content
            .background(WindowSceneReader(scene: $scene))
            .onChange(of: isLocked, initial: true) { apply() }
            .onChange(of: scene) { old, _ in
                if let old { OrientationLock.setPortraitLocked(false, in: old) }
                apply()
            }
            .onDisappear {
                if let scene { OrientationLock.setPortraitLocked(false, in: scene) }
            }
    }

    private func apply() {
        if let scene { OrientationLock.setPortraitLocked(isLocked, in: scene) }
    }
}

/// Reports the window scene hosting it.
private struct WindowSceneReader: UIViewRepresentable {
    @Binding var scene: UIWindowScene?

    func makeUIView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.isUserInteractionEnabled = false
        view.onScene = { [$scene] scene in
            // Deferred: didMoveToWindow can run during a SwiftUI update.
            Task { $scene.wrappedValue = scene }
        }
        return view
    }

    func updateUIView(_ view: ReaderView, context: Context) {}

    final class ReaderView: UIView {
        var onScene: ((UIWindowScene?) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            onScene?(window?.windowScene)
        }
    }
}
