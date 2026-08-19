import Foundation
import SwiftUI
import AppKit
import Testing
@testable import Ascend

/// The badge has to be exactly the size it was asked for whether it is showing
/// a picture or a symbol. Rendering it and measuring is the only way to catch a
/// picture escaping its frame without launching the app.
@MainActor
@Suite("Profile badge")
struct ProfileBadgeTests {

    /// A plain coloured square, then squeezed through the same thumbnail step
    /// an uploaded picture goes through.
    private func pictureData(width: CGFloat, height: CGFloat) -> Data {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.systemRed.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        image.unlockFocus()
        return AccountIconStyle.thumbnailData(from: image)!
    }

    private func renderedSize(_ profile: Profile, size: CGFloat) throws -> CGSize {
        let renderer = ImageRenderer(content: ProfileBadge(profile: profile, size: size))
        let rendered = try #require(renderer.nsImage)
        return rendered.size
    }

    @Test("A symbol badge is exactly the size it was asked for")
    func symbolBadgeSize() throws {
        let profile = Profile(name: "Personal")
        #expect(try renderedSize(profile, size: Theme.Size.avatar) == CGSize(width: Theme.Size.avatar, height: Theme.Size.avatar))
    }

    @Test("A square picture does not enlarge the badge")
    func squarePictureSize() throws {
        let profile = Profile(name: "Personal", imageData: pictureData(width: 512, height: 512))
        #expect(try renderedSize(profile, size: Theme.Size.avatar) == CGSize(width: Theme.Size.avatar, height: Theme.Size.avatar))
    }

    @Test("A wide picture does not enlarge the badge")
    func widePictureSize() throws {
        let profile = Profile(name: "Personal", imageData: pictureData(width: 1200, height: 400))
        #expect(try renderedSize(profile, size: Theme.Size.avatar) == CGSize(width: Theme.Size.avatar, height: Theme.Size.avatar))
    }

    @Test("A tall picture does not enlarge the badge")
    func tallPictureSize() throws {
        let profile = Profile(name: "Personal", imageData: pictureData(width: 400, height: 1200))
        #expect(try renderedSize(profile, size: Theme.Size.avatar) == CGSize(width: Theme.Size.avatar, height: Theme.Size.avatar))
    }

    @Test("The small sidebar badge holds its size too")
    func smallBadgeSize() throws {
        let profile = Profile(name: "Personal", imageData: pictureData(width: 1200, height: 400))
        #expect(try renderedSize(profile, size: Theme.Size.iconMedium + 6) == CGSize(width: Theme.Size.iconMedium + 6, height: Theme.Size.iconMedium + 6))
    }
}
