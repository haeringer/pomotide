import CoreGraphics
import Testing
@testable import PomoTide

struct RingDragTests {
    let center = CGPoint(x: 100, y: 100)

    /// View coordinates, y pointing down: top is the start, clockwise from there.
    @Test(arguments: [
        (CGPoint(x: 100, y: 0), 0.0),
        (CGPoint(x: 200, y: 100), 0.25),
        (CGPoint(x: 100, y: 200), 0.5),
        (CGPoint(x: 0, y: 100), 0.75),
    ])
    func angleToProgress(point: CGPoint, expected: Double) {
        #expect(abs(RingDrag.progress(at: point, center: center, last: expected) - expected) < 1e-9)
    }

    @Test func crossingTheTopStopsAtTheNearerEnd() {
        let justLeftOfTop = CGPoint(x: 99, y: 0)
        let justRightOfTop = CGPoint(x: 101, y: 0)
        #expect(RingDrag.progress(at: justRightOfTop, center: center, last: 0.98) == 1)
        #expect(RingDrag.progress(at: justLeftOfTop, center: center, last: 0.02) == 0)
    }
}
