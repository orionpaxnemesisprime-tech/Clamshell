// SPDX-License-Identifier: GPL-3.0-or-later

@testable import ClamshellCore
import CoreGraphics
import Foundation
import GameController
import Testing

@Suite struct ControlsLayoutTests {
    private func expectValid(_ controls: ControlsLayout, container: CGRect, screens: ScreenLayout) {
        let frames = Array(controls.frames.values)
        for (i, a) in frames.enumerated() {
            #expect(container.contains(a), "control inside the container")
            for b in frames[(i + 1)...] { #expect(!a.intersects(b), "controls don't overlap") }
        }
        if controls.placement != .overlay {
            for frame in frames {
                #expect(!frame.intersects(screens.top) && !frame.intersects(screens.bottom),
                        "dedicated controls never cover the screens")
            }
        }
    }

    @Test func wideClamshellPutsControlsBesideTheTouchScreen() {
        let container = CGRect(x: 0, y: 0, width: 951, height: 669)
        let fold = CGRect(x: 0, y: 325, width: 951, height: 20)
        let screens = ScreenLayout(container: container, posture: .clamshell(fold: fold), displayScale: 3)
        let controls = ControlsLayout(container: container, screens: screens)
        #expect(controls.placement == .beside)
        #expect(controls.frames[.dpad]!.maxX <= screens.bottom.minX)
        #expect(controls.frames[.faceButtons]!.minX >= screens.bottom.maxX)
        expectValid(controls, container: container, screens: screens)
    }

    @Test func sideBySideMakesRoomForABandBelow() throws {
        // iPhone Duo inner display, landscape: centred screens leave too little room below,
        // so GameLayout reserves a band instead of covering the screens.
        let container = CGRect(x: 0, y: 0, width: 951, height: 669)
        let centred = ScreenLayout(container: container, posture: .sideBySide, displayScale: 3)
        #expect(ControlsLayout(container: container, screens: centred).placement == .overlay)

        let layout = GameLayout(container: container, posture: .sideBySide, displayScale: 3, showsControls: true)
        let controls = try #require(layout.controls)
        #expect(controls.placement == .below)
        #expect(layout.screens.top.size == centred.top.size, "screens keep their size")
        expectValid(controls, container: container, screens: layout.screens)
    }

    @Test func hiddenControlsLeaveScreensAlone() {
        let container = CGRect(x: 0, y: 0, width: 951, height: 669)
        let layout = GameLayout(container: container, posture: .sideBySide, displayScale: 3, showsControls: false)
        #expect(layout.controls == nil)
        #expect(layout.screens == ScreenLayout(container: container, posture: .sideBySide, displayScale: 3))
    }

    @Test func crampedSpaceFallsBackToOverlay() {
        let container = CGRect(x: 0, y: 0, width: 400, height: 640)
        let screens = ScreenLayout(container: container, posture: .stacked, displayScale: 3)
        let controls = ControlsLayout(container: container, screens: screens)
        #expect(controls.placement == .overlay)
        expectValid(controls, container: container, screens: screens)
    }

    static let shoulderCases: [(CGRect, ScreenPosture)] = [
        (CGRect(x: 0, y: 0, width: 951, height: 669), .clamshell(fold: CGRect(x: 0, y: 325, width: 951, height: 20))),
        (CGRect(x: 0, y: 0, width: 951, height: 669), .sideBySide),
        (CGRect(x: 0, y: 0, width: 669, height: 951), .stacked),
        (CGRect(x: 0, y: 0, width: 400, height: 640), .stacked),
    ]

    @Test(arguments: shoulderCases)
    func shouldersSitAboveTheirClusters(container: CGRect, posture: ScreenPosture) throws {
        let layout = GameLayout(container: container, posture: posture, displayScale: 3, showsControls: true)
        let controls = try #require(layout.controls)
        let l = try #require(controls.frames[.l]), r = try #require(controls.frames[.r])
        let dpad = try #require(controls.frames[.dpad]), face = try #require(controls.frames[.faceButtons])
        #expect(l.midX == dpad.midX && r.midX == face.midX, "each shoulder is centred on its cluster")
        #expect(l.minY == r.minY, "shoulders are level")
        #expect(l.maxY <= dpad.minY && r.maxY <= face.minY, "shoulders are above their clusters")
        #expect(face.minY - r.maxY <= 12, "and right next to them")
        if case .clamshell(let fold) = posture {
            #expect(l.minY >= fold.maxY, "shoulders stay on the touch-screen side of the fold")
        }
        expectValid(controls, container: container, screens: layout.screens)
    }

    static let dpadCases: [(CGPoint, EmulatorKeys)] = [
        (CGPoint(x: 0, y: -50), .up), (CGPoint(x: 0, y: 50), .down),
        (CGPoint(x: -50, y: 0), .left), (CGPoint(x: 50, y: 0), .right),
        (CGPoint(x: 40, y: -40), [.up, .right]), (CGPoint(x: -40, y: 40), [.down, .left]),
        (CGPoint(x: 3, y: 3), []),
    ]

    @Test(arguments: dpadCases)
    func dpadDirections(offset: CGPoint, expected: EmulatorKeys) {
        let frame = CGRect(x: 0, y: 0, width: 132, height: 132)
        let point = CGPoint(x: frame.midX + offset.x, y: frame.midY + offset.y)
        #expect(ControlsLayout.dpadKeys(at: point, in: frame) == expected)
    }

    static let stickCases: [(CGPoint, EmulatorKeys)] = [
        (CGPoint(x: 0, y: -30), .up), (CGPoint(x: 30, y: 30), [.down, .right]),
        // Within a quarter of the 66-point radius: dead zone.
        (CGPoint(x: 10, y: -10), []),
        // Thumb slid well past the stick's base: still steering.
        (CGPoint(x: -200, y: 0), .left), (CGPoint(x: 150, y: -160), [.up, .right]),
    ]

    @Test(arguments: stickCases)
    func stickDirections(offset: CGPoint, expected: EmulatorKeys) {
        let frame = CGRect(x: 0, y: 0, width: 132, height: 132)
        let point = CGPoint(x: frame.midX + offset.x, y: frame.midY + offset.y)
        #expect(ControlsLayout.stickKeys(at: point, in: frame) == expected)
    }

    @Test func stickKnobStaysWithinItsTravel() {
        let frame = CGRect(x: 0, y: 0, width: 132, height: 132)
        #expect(ControlsLayout.stickKnobCenter(for: CGPoint(x: 80, y: 66), in: frame, travel: 40)
            == CGPoint(x: 80, y: 66))
        #expect(ControlsLayout.stickKnobCenter(for: CGPoint(x: 366, y: 66), in: frame, travel: 40)
            == CGPoint(x: 106, y: 66))
    }

    @Test func faceButtonsFollowTheDiamond() {
        let frame = CGRect(x: 0, y: 0, width: 140, height: 140)
        #expect(ControlsLayout.faceKey(at: CGPoint(x: 70, y: 10), in: frame) == .x)
        #expect(ControlsLayout.faceKey(at: CGPoint(x: 70, y: 130), in: frame) == .b)
        #expect(ControlsLayout.faceKey(at: CGPoint(x: 10, y: 70), in: frame) == .y)
        #expect(ControlsLayout.faceKey(at: CGPoint(x: 130, y: 70), in: frame) == .a)
    }

    @Test func touchesOutsideControlsPressNothing() {
        let container = CGRect(x: 0, y: 0, width: 951, height: 669)
        let screens = ScreenLayout(container: container, posture: .sideBySide, displayScale: 3)
        let controls = ControlsLayout(container: container, screens: screens)
        #expect(controls.keys(at: CGPoint(x: screens.bottom.midX, y: screens.bottom.midY)).isEmpty)
        #expect(controls.keys(at: CGPoint(x: controls.frames[.start]!.midX, y: controls.frames[.start]!.midY)) == .start)
    }
}

@Suite struct InputMappingTests {
    @Test func gamepadMapsFaceButtonsByPosition() throws {
        let controller = GCController.withExtendedGamepad()
        let gamepad = try #require(controller.extendedGamepad)
        #expect(InputMapping.keys(from: gamepad).isEmpty)

        gamepad.buttonA.setValue(1)   // bottom of the diamond
        gamepad.buttonB.setValue(1)   // right
        gamepad.leftShoulder.setValue(1)
        gamepad.dpad.setValueForXAxis(0, yAxis: 1)
        #expect(InputMapping.keys(from: gamepad) == [.b, .a, .l, .up])

        gamepad.buttonA.setValue(0)
        gamepad.buttonB.setValue(0)
        gamepad.leftShoulder.setValue(0)
        gamepad.dpad.setValueForXAxis(0, yAxis: 0)
        gamepad.leftThumbstick.xAxis.setValue(-0.9)
        #expect(InputMapping.keys(from: gamepad) == .left, "left stick drives the D-pad")
    }

    @Test func keyboardMapCoversEveryButton() {
        let mapped = InputMapping.keyboard.values.reduce(into: EmulatorKeys()) { $0.formUnion($1) }
        let all: EmulatorKeys = [.a, .b, .x, .y, .l, .r, .start, .select, .up, .down, .left, .right]
        #expect(mapped == all)
    }
}

@Suite(.serialized, .timeLimit(.minutes(1)))
struct InputRouterTests {
    @Test func sourcesAreMergedAndReleasedIndependently() throws {
        let url = try #require(Bundle.module.url(forResource: "iotest", withExtension: "nds", subdirectory: "ROMs"))
        let session = EmulationSession()
        try session.start(rom: Array(try Data(contentsOf: url)), name: "iotest.nds")
        defer { session.stop() }
        let router = InputRouter(session: session)

        router.set(.a, from: .touchControls)
        router.set([.a, .up], from: .gamepad)
        #expect(router.keys == [.a, .up])
        router.set([], from: .gamepad)
        #expect(router.keys == .a, "touch still holds A after the gamepad lets go")

        Thread.sleep(forTimeInterval: 0.3)
        let top = session.frames.withLatestFrame { top, _, _ in top[0] }
        #expect(top.map { ($0 >> 16) & 0xFF > 0xF0 && ($0 >> 8) & 0xFF == 0 } == true,
                "iotest turns the top screen red while a button is held")

        router.releaseAll()
        #expect(router.keys.isEmpty)
    }
}
