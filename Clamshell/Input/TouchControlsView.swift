// SPDX-License-Identifier: GPL-3.0-or-later

import ClamshellCore
import SwiftUI
import UIKit

/// On-screen buttons. Multi-touch: every finger contributes, and sliding a finger across
/// the D-pad or face buttons changes the pressed button without lifting.
struct TouchControls: UIViewRepresentable {
    let layout: ControlsLayout
    let router: InputRouter
    /// Called when the Blow control is pressed (true) or released (false).
    var onBlow: (Bool) -> Void = { _ in }

    func makeUIView(context: Context) -> TouchControlsView {
        let view = TouchControlsView()
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: TouchControlsView, context: Context) {
        view.router = router
        view.layout = layout
        view.onBlow = onBlow
    }

    static func dismantleUIView(_ view: TouchControlsView, coordinator: ()) {
        view.router?.set([], from: .touchControls)
        view.onBlow(false)
    }
}

final class TouchControlsView: UIView {
    var router: InputRouter?
    var onBlow: (Bool) -> Void = { _ in }
    var layout: ControlsLayout? {
        didSet {
            guard layout != oldValue else { return }
            setNeedsDisplay()
        }
    }

    private var pressed: EmulatorKeys = [] {
        didSet {
            guard pressed != oldValue else { return }
            if !pressed.subtracting(oldValue).isEmpty { feedback.impactOccurred() }
            router?.set(pressed, from: .touchControls)
            setNeedsDisplay()
        }
    }

    private let feedback = UIImpactFeedbackGenerator(style: .light)

    private var blowing = false {
        didSet {
            guard blowing != oldValue else { return }
            if blowing { feedback.impactOccurred() }
            onBlow(blowing)
            setNeedsDisplay()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        isMultipleTouchEnabled = true
        contentMode = .redraw
        isAccessibilityElement = true
        accessibilityLabel = String(localized: "Game controls")
        accessibilityTraits = .allowsDirectInteraction
        // Switch Control, Voice Control and VoiceOver users can press each button as an action.
        let buttons: [(String, EmulatorKeys)] = [
            (String(localized: "Press A"), .a), (String(localized: "Press B"), .b),
            (String(localized: "Press X"), .x), (String(localized: "Press Y"), .y),
            (String(localized: "Press L"), .l), (String(localized: "Press R"), .r),
            (String(localized: "Press Start"), .start), (String(localized: "Press Select"), .select),
            (String(localized: "Press Up"), .up), (String(localized: "Press Down"), .down),
            (String(localized: "Press Left"), .left), (String(localized: "Press Right"), .right),
        ]
        accessibilityCustomActions = buttons.map { name, key in
            UIAccessibilityCustomAction(name: name) { [weak self] _ in
                self?.tap(key)
                return true
            }
        }
    }

    /// Presses and releases a button long enough for every game to notice (~6 frames).
    private func tap(_ key: EmulatorKeys) {
        router?.set(key, from: .accessibility)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in
            self?.router?.set([], from: .accessibility)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // Only the controls themselves take touches; everything else (the touch screen) passes through.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        layout?.frames.values.contains { $0.insetBy(dx: -8, dy: -8).contains(point) } ?? false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        feedback.prepare()
        update(event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { update(event) }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { update(event) }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { update(event) }

    private func update(_ event: UIEvent?) {
        guard let layout else { return }
        let active = (event?.allTouches ?? []).filter {
            $0.view === self && $0.phase != .ended && $0.phase != .cancelled
        }
        pressed = active.reduce(into: EmulatorKeys()) { keys, touch in
            keys.formUnion(layout.keys(at: touch.location(in: self)))
        }
        blowing = active.contains { layout.control(at: $0.location(in: self)) == .blow }
    }

    // MARK: Drawing

    override func draw(_ rect: CGRect) {
        guard let layout else { return }
        let base: CGFloat = layout.placement == .overlay ? 0.18 : 0.28
        let fill = UIColor.white.withAlphaComponent(base)
        let lit = UIColor.white.withAlphaComponent(base + 0.35)
        let ink = UIColor.white.withAlphaComponent(0.9)
        func color(_ keys: EmulatorKeys) -> UIColor { pressed.isDisjoint(with: keys) ? fill : lit }

        for (control, frame) in layout.frames {
            switch control {
            case .dpad:
                drawDpad(in: frame, color: color)
            case .faceButtons:
                drawFaceButtons(in: frame, color: color, ink: ink)
            case .blow:
                (blowing ? lit : fill).setFill()
                UIBezierPath(roundedRect: frame, cornerRadius: frame.height / 2).fill()
                drawLabel(String(localized: "BLOW"), centeredIn: frame, size: 11, ink: ink)
            case .l, .r, .select, .start:
                let (key, title): (EmulatorKeys, String) = switch control {
                case .l: (.l, "L")
                case .r: (.r, "R")
                case .select: (.select, String(localized: "SELECT"))
                default: (.start, String(localized: "START"))
                }
                color(key).setFill()
                UIBezierPath(roundedRect: frame, cornerRadius: frame.height / 2).fill()
                drawLabel(title, centeredIn: frame, size: control == .l || control == .r ? 17 : 11, ink: ink)
            }
        }
    }

    private func drawDpad(in frame: CGRect, color: (EmulatorKeys) -> UIColor) {
        let arm = frame.width / 3
        let arms: [(EmulatorKeys, CGRect)] = [
            (.up, CGRect(x: frame.minX + arm, y: frame.minY, width: arm, height: arm + 1)),
            (.down, CGRect(x: frame.minX + arm, y: frame.maxY - arm - 1, width: arm, height: arm + 1)),
            (.left, CGRect(x: frame.minX, y: frame.minY + arm, width: arm + 1, height: arm)),
            (.right, CGRect(x: frame.maxX - arm - 1, y: frame.minY + arm, width: arm + 1, height: arm)),
        ]
        for (key, armFrame) in arms {
            color(key).setFill()
            UIBezierPath(roundedRect: armFrame, cornerRadius: 6).fill()
        }
        color([]).setFill()
        UIBezierPath(rect: CGRect(x: frame.minX + arm, y: frame.minY + arm, width: arm, height: arm)).fill()
    }

    private func drawFaceButtons(in frame: CGRect, color: (EmulatorKeys) -> UIColor, ink: UIColor) {
        let size = frame.width * 0.36
        let buttons: [(EmulatorKeys, String, CGPoint)] = [
            (.x, "X", CGPoint(x: frame.midX, y: frame.minY + size / 2)),
            (.b, "B", CGPoint(x: frame.midX, y: frame.maxY - size / 2)),
            (.y, "Y", CGPoint(x: frame.minX + size / 2, y: frame.midY)),
            (.a, "A", CGPoint(x: frame.maxX - size / 2, y: frame.midY)),
        ]
        for (key, title, center) in buttons {
            let circle = CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
            color(key).setFill()
            UIBezierPath(ovalIn: circle).fill()
            drawLabel(title, centeredIn: circle, size: 18, ink: ink)
        }
    }

    private func drawLabel(_ text: String, centeredIn frame: CGRect, size: CGFloat, ink: UIColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: ink,
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: frame.midX - textSize.width / 2, y: frame.midY - textSize.height / 2),
                                withAttributes: attributes)
    }
}
