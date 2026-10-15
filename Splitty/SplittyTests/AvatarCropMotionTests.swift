import CoreGraphics
import Testing
@testable import Splitty

struct AvatarCropMotionTests {
    @Test func valuesInsideTheBoundsPassThrough() {
        #expect(AvatarCropMotion.rubberBand(30, in: -50...50, dimension: 300) == 30)
        #expect(AvatarCropMotion.rubberBand(-50, in: -50...50, dimension: 300) == -50)
    }

    @Test func overshootIsResistedOnBothSides() {
        let past = AvatarCropMotion.rubberBand(150, in: -50...50, dimension: 300)
        let before = AvatarCropMotion.rubberBand(-150, in: -50...50, dimension: 300)

        #expect(past > 50 && past < 150)
        #expect(before == -past)
    }

    @Test func overshootNeverPassesTheLimit() {
        let limit: CGFloat = 300
        let far = AvatarCropMotion.rubberBand(1_000_000, in: 0...0, dimension: 300)

        #expect(far < limit)
        #expect(far > limit - 1)
    }

    @Test func aFlickCarriesInItsDirection() {
        #expect(AvatarCropMotion.projectedDistance(0) == 0)
        #expect(abs(AvatarCropMotion.projectedDistance(1_000) - 499) < 0.5)
        #expect(AvatarCropMotion.projectedDistance(-1_000) == -AvatarCropMotion.projectedDistance(1_000))
    }
}
