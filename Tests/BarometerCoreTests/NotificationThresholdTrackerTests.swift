import Foundation
import XCTest
@testable import BarometerCore

final class NotificationThresholdTrackerTests: XCTestCase {
    private let tracker = NotificationThresholdTracker()

    func testThresholdsFireOncePerResetWindow() {
        let first = tracker.evaluate(snapshot: snapshot(usage: 72, reset: 1_000), sentTokens: [])
        XCTAssertEqual(first.events.map(\.threshold), [70])

        let repeated = tracker.evaluate(snapshot: snapshot(usage: 75, reset: 1_000), sentTokens: first.sentTokens)
        XCTAssertTrue(repeated.events.isEmpty)

        let high = tracker.evaluate(snapshot: snapshot(usage: 91, reset: 1_000), sentTokens: repeated.sentTokens)
        XCTAssertEqual(high.events.map(\.threshold), [90])

        let reset = tracker.evaluate(snapshot: snapshot(usage: 91, reset: 2_000), sentTokens: high.sentTokens)
        XCTAssertEqual(reset.events.map(\.threshold), [70, 90])
    }

    func testMissingResetDoesNotNotifyOnEveryCapture() {
        let first = tracker.evaluate(snapshot: snapshot(usage: 72, reset: nil), sentTokens: [])
        let repeated = tracker.evaluate(snapshot: snapshot(usage: 73, reset: nil), sentTokens: first.sentTokens)
        XCTAssertEqual(first.events.count, 1)
        XCTAssertTrue(repeated.events.isEmpty)
    }

    func testDroppingBelowThresholdDoesNotRearmSameWindow() {
        let first = tracker.evaluate(snapshot: snapshot(usage: 72, reset: nil), sentTokens: [])
        let low = tracker.evaluate(snapshot: snapshot(usage: 20, reset: nil), sentTokens: first.sentTokens)
        let crossedAgain = tracker.evaluate(snapshot: snapshot(usage: 71, reset: nil), sentTokens: low.sentTokens)
        XCTAssertTrue(crossedAgain.events.isEmpty)
    }

    func testTemporarilyMissingWindowDoesNotLoseDeduplicationState() {
        let first = tracker.evaluate(snapshot: snapshot(usage: 72, reset: 1_000), sentTokens: [])
        let missing = tracker.evaluate(
            snapshot: UsageSnapshot(capturedAt: Date(), fiveHour: nil, sevenDay: nil),
            sentTokens: first.sentTokens
        )
        let returned = tracker.evaluate(snapshot: snapshot(usage: 74, reset: 1_000), sentTokens: missing.sentTokens)

        XCTAssertTrue(returned.events.isEmpty)
    }

    private func snapshot(usage: Double, reset: TimeInterval?) -> UsageSnapshot {
        UsageSnapshot(
            capturedAt: Date(timeIntervalSince1970: 100),
            fiveHour: RateLimitWindow(
                usedPercentage: usage,
                resetsAt: reset.map { Date(timeIntervalSince1970: $0) }
            ),
            sevenDay: nil
        )
    }
}
