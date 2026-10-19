// SPDX-License-Identifier: GPL-3.0-or-later

@testable import ClamshellCore
import Foundation
import Testing

@Suite struct GameBannerTests {
    /// A banner with a two-line English title and an icon whose first tile is solid colour 1.
    private func syntheticBanner(title: String) -> [UInt8] {
        var banner = [UInt8](repeating: 0, count: GameBanner.bannerLength)
        banner[0] = 1 // version
        for i in 0..<32 { banner[0x20 + i] = 0x11 } // tile 0: every pixel = palette 1
        banner[0x220 + 2] = 0x1F // palette 1 = pure red (BGR555 0x001F)
        for (i, unit) in title.utf16.enumerated() {
            banner[0x340 + i * 2] = UInt8(unit & 0xFF)
            banner[0x340 + i * 2 + 1] = UInt8(unit >> 8)
        }
        return banner
    }

    @Test func parsesTitleLinesAndTiledIcon() throws {
        let banner = try #require(GameBanner.parse(banner: syntheticBanner(title: "Clamshell Test\nA demo\nAuthor")))
        #expect(banner.titleLines == ["Clamshell Test", "A demo", "Author"])

        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            let offset = (y * 32 + x) * 4
            return Array(banner.iconRGBA[offset..<offset + 4])
        }
        #expect(pixel(0, 0) == [255, 0, 0, 255], "tile 0 is red")
        #expect(pixel(7, 7) == [255, 0, 0, 255])
        #expect(pixel(8, 0) == [0, 0, 0, 0], "tile 1 uses colour 0, which is transparent")
        #expect(banner.iconImage()?.width == 32)
    }

    @Test func emptyBannerIsNil() {
        #expect(GameBanner.parse(banner: [UInt8](repeating: 0, count: GameBanner.bannerLength)) == nil)
        #expect(GameBanner.parse(banner: [1, 2, 3]) == nil)
    }

    @Test func readsOnlyTheBannerFromAFile() throws {
        var file = [UInt8](repeating: 0, count: 0x1000)
        let offset = 0x800
        file[0x68] = UInt8(offset & 0xFF)
        file[0x69] = UInt8(offset >> 8)
        file.replaceSubrange(offset..<offset + GameBanner.bannerLength, with: syntheticBanner(title: "On Disk"))
        let url = FileManager.default.temporaryDirectory.appending(path: "banner-\(UUID()).nds")
        try Data(file).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(GameBanner.read(from: url)?.titleLines == ["On Disk"])
    }

    @Test func testROMsWithoutBannersReturnNil() throws {
        let url = try #require(Bundle.module.url(forResource: "smoketest", withExtension: "nds", subdirectory: "ROMs"))
        #expect(GameBanner.read(from: url) == nil)
    }
}
