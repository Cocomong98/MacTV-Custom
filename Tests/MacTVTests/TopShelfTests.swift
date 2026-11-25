import AppKit
import Testing
@testable import MacTV

@MainActor
struct TopShelfTests {
    @Test func usesFullBleedOnlyWhenAnImageCanFillTheScreen() {
        let screen = CGSize(width: 3840, height: 2160)
        #expect(ShelfArtwork.fillsScreen(screen, viewport: screen))
        #expect(!ShelfArtwork.fillsScreen(CGSize(width: 1920, height: 1080), viewport: screen))
        #expect(!ShelfArtwork.fillsScreen(CGSize(width: 3840, height: 1440), viewport: screen))
        #expect(!ShelfArtwork.fillsScreen(CGSize(width: 3840, height: 4800), viewport: screen))
    }

    @Test func movesBetweenTheDockAndTheSelectedAppBanner() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("work/tests/top-shelf-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let tv = TVController(library: AppLibrary(folder: folder))
        tv.setFocus(.app(0))
        _ = tv.setPinned("netflix", false)
        tv.handle(.move(.right), from: .remote)
        let selected = tv.shelfService.id
        let selectedIndex = tv.shelfAppIndex
        #expect(selectedIndex == 1)
        #expect(tv.shelfCount == 1)
        tv.handle(.move(.up), from: .remote)
        #expect(tv.focus == .shelf(0))
        tv.handle(.move(.right), from: .remote)
        #expect(tv.focus == .shelf(0))
        #expect(tv.shelfService.id == selected)
        tv.handle(.back, from: .remote)
        #expect(tv.focus == .app(selectedIndex))
    }

    @Test func mapsTheRetiredSaverPreferenceToColours() {
        #expect(ScreenSaverSettings.resolveWallpaper("topShelf", aerialsAvailable: true) == .colour)
        #expect(ScreenSaverSettings.resolveWallpaper("photos", aerialsAvailable: false) == .photos)
        #expect(ScreenSaverSettings.resolveWallpaper(nil, aerialsAvailable: false) == .colour)
        #expect(ScreenSaverSettings.resolveWallpaper(nil, aerialsAvailable: true) == .aerials)
    }
}
