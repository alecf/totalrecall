import Testing
import CoreGraphics
@testable import TotalRecallCore

@Suite("Sparkline Layout")
struct SparklineLayoutTests {
    let size = CGSize(width: 56, height: 16)
    let lineWidth: CGFloat = 1.5

    func points(_ history: [UInt64]) -> [CGPoint] {
        SparklineLayout.points(history: history, size: size, lineWidth: lineWidth)
    }

    @Test("Empty history yields no points")
    func emptyHistory() {
        #expect(points([]).isEmpty)
    }

    @Test("Zero-area rect yields no points")
    func zeroSize() {
        let result = SparklineLayout.points(
            history: [1, 2, 3], size: CGSize(width: 0, height: 16), lineWidth: lineWidth
        )
        #expect(result.isEmpty)
    }

    @Test("One sample pins to the right edge at vertical center")
    func singleSample() {
        let result = points([100])
        #expect(result.count == 1)
        #expect(result[0].x == size.width)
        #expect(abs(result[0].y - size.height / 2) < 0.001)
    }

    @Test("Points span the full width, left to right, newest last")
    func spansWidth() {
        let result = points([10, 20, 30])
        #expect(result.count == 3)
        #expect(abs(result.first!.x - 0) < 0.001)
        #expect(abs(result.last!.x - size.width) < 0.001)
        // X strictly increasing.
        #expect(zip(result, result.dropFirst()).allSatisfy { $0.x < $1.x })
    }

    @Test("Larger values map to smaller y (drawn higher)")
    func largerValuesGoUp() {
        let result = points([10, 30])
        // First (smaller) sample sits lower on screen than the second (larger).
        #expect(result[0].y > result[1].y)
    }

    @Test("Min and max pin to the inset top and bottom of the rect")
    func extremesPinToEdges() {
        let result = points([10, 30])
        let inset = lineWidth / 2
        #expect(abs(result[1].y - inset) < 0.001)               // max → top inset
        #expect(abs(result[0].y - (size.height - inset)) < 0.001) // min → bottom inset
    }

    @Test("Flat series draws through the vertical center")
    func flatSeries() {
        let result = points([50, 50, 50])
        for point in result {
            #expect(abs(point.y - size.height / 2) < 0.001)
        }
    }

    @Test("All points stay within the drawing rect")
    func staysInBounds() {
        let result = points([5, 900, 30, 1, 400, 250])
        let inset = lineWidth / 2
        for point in result {
            #expect(point.x >= 0 && point.x <= size.width)
            #expect(point.y >= inset - 0.001 && point.y <= size.height - inset + 0.001)
        }
    }
}
