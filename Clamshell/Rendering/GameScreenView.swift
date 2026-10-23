// SPDX-License-Identifier: GPL-3.0-or-later

import ClamshellCore
import MetalKit
import SwiftUI

/// Metal view showing both emulated screens; touches on the bottom screen drive the stylus.
struct GameScreenView: UIViewRepresentable {
    let session: EmulationSession
    let layout: ScreenLayout
    var smoothScaling = false
    /// Fills the area around the screens.
    var background = UIColor.black
    /// Called when any touch begins on the view.
    var onTouch: () -> Void = {}

    func makeUIView(context: Context) -> GameMTKView {
        let view = GameMTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: GameMTKView, context: Context) {
        view.session = session
        view.layout = layout
        view.smoothScaling = smoothScaling
        view.background = background
        view.onTouch = onTouch
    }
}

final class GameMTKView: MTKView {
    var session: EmulationSession? {
        didSet { renderer?.frames = session?.frames }
    }

    var layout = ScreenLayout(top: .zero, bottom: .zero) {
        didSet { renderer?.layout = layout }
    }

    var onTouch: () -> Void = {}

    var smoothScaling = false {
        didSet { renderer?.smoothScaling = smoothScaling }
    }

    var background = UIColor.black {
        didSet {
            guard background != oldValue else { return }
            backgroundColor = background
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            background.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            clearColor = MTLClearColor(red: red, green: green, blue: blue, alpha: 1)
        }
    }

    private var renderer: DualScreenRenderer?
    /// The one touch currently acting as the stylus.
    private weak var stylus: UITouch?

    override init(frame: CGRect, device: MTLDevice?) {
        super.init(frame: frame, device: device)
        renderer = DualScreenRenderer(view: self)
        delegate = renderer
        preferredFramesPerSecond = 60
        isMultipleTouchEnabled = true
        isOpaque = true
        backgroundColor = .black
        isAccessibilityElement = true
        accessibilityLabel = String(localized: "Game screens")
        accessibilityTraits = .allowsDirectInteraction
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: Touch → stylus

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        onTouch()
        guard stylus == nil else { return }
        // Apple Pencil takes priority over fingers.
        let ordered = touches.sorted { ($0.type == .pencil ? 0 : 1) < ($1.type == .pencil ? 0 : 1) }
        for touch in ordered {
            if let location = layout.touchLocation(at: touch.location(in: self)) {
                stylus = touch
                session?.touch(x: location.x, y: location.y)
                return
            }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let stylus, touches.contains(stylus) else { return }
        let location = layout.clampedTouchLocation(at: stylus.location(in: self))
        session?.touch(x: location.x, y: location.y)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        endStylus(ifIn: touches)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        endStylus(ifIn: touches)
    }

    private func endStylus(ifIn touches: Set<UITouch>) {
        guard let stylus, touches.contains(stylus) else { return }
        self.stylus = nil
        session?.releaseTouch()
    }
}
