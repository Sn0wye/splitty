import Foundation
import Testing
@testable import Splitty

struct SettledCoinMotionTests {
    private let frames = stride(from: 0.0, through: 1.5, by: 1.0 / 240)

    @Test func theHalvesNeverTravelPastTheJoinedPosition() {
        for time in frames {
            if let progress = SettledCoinMotion.closeProgress(at: time) {
                #expect(progress >= 0 && progress <= 1)
            }
        }
    }

    @Test func theHalvesStopAtFirstContact() {
        let contact = frames.first { SettledCoinMotion.closeProgress(at: $0) == nil }
        // A 0.5 response at 0.55 damping first reaches its target after about 0.2 s.
        #expect(contact.map { $0 > 0.15 && $0 < 0.25 } == true)
        #expect(frames.filter { $0 > contact! }.allSatisfy { SettledCoinMotion.closeProgress(at: $0) == nil })
    }

    @Test func theCoinSwellsOnceDipsAndSettles() {
        let scales = frames.map { SettledCoinMotion.wobbleScale(at: $0) }
        #expect(scales.first == 1)
        #expect(abs(scales.max()! - 1.045) < 0.005)
        #expect(abs(scales.min()! - 0.99) < 0.003)
        #expect(abs(SettledCoinMotion.wobbleScale(at: SettledCoinMotion.wobbleDuration) - 1) < 0.001)
    }
}
