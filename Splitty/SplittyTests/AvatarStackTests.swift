import Foundation
import Testing
@testable import Splitty

struct AvatarStackTests {

    @Test func aSmallGroupShowsEveryFace() {
        let urls = faces(4)
        let stack = AvatarStack.from(urls)

        #expect(stack.urls == urls)
        #expect(stack.overflow == 0)
    }

    @Test func aFifthFaceGivesWayToAnOverflowCount() {
        let urls = faces(5)
        let stack = AvatarStack.from(urls)

        #expect(stack.urls == Array(urls.prefix(3)))
        #expect(stack.overflow == 2)
    }

    @Test func aFiftyMemberGroupStillFitsFourSlots() {
        let urls = faces(50)
        let stack = AvatarStack.from(urls)

        #expect(stack.urls.count == 3)
        #expect(stack.overflow == 47)
        #expect(stack.urls == Array(urls.prefix(3)))
    }

    @Test func overflowCountsPeopleNotJustLoadedPhotos() {
        let urls = faces(2)
        let stack = AvatarStack.from(urls, total: 50)

        #expect(stack.urls == urls)
        #expect(stack.overflow == 48)
    }

    private func faces(_ count: Int) -> [URL] {
        (1...count).map { URL(string: "https://example.com/\($0).png")! }
    }
}
