import Foundation
import XCTest
@testable import BarometerCore

final class StatusDisplayFormatterTests: XCTestCase {
    let snapshot = UsageSnapshot(
        capturedAt: Date(),
        fiveHour: RateLimitWindow(usedPercentage: 42.2, resetsAt: nil),
        sevenDay: RateLimitWindow(usedPercentage: 67.8, resetsAt: nil)
    )

    func testAllMetricModes() {
        let formatter = StatusDisplayFormatter()
        XCTAssertEqual(formatter.title(snapshot: snapshot, metricMode: .both), "5h 42% · 7d 68%")
        XCTAssertEqual(formatter.title(snapshot: snapshot, metricMode: .fiveHour), "5h 42%")
        XCTAssertEqual(formatter.title(snapshot: snapshot, metricMode: .sevenDay), "7d 68%")
        XCTAssertEqual(formatter.title(snapshot: snapshot, metricMode: .highest), "Max 68%")
    }

    func testMissingSnapshot() {
        XCTAssertEqual(StatusDisplayFormatter().title(snapshot: nil, metricMode: .both), "—")
    }

    func testPercentageFollowsSelectedMetric() {
        let formatter = StatusDisplayFormatter()
        XCTAssertEqual(formatter.percentage(snapshot: snapshot, metricMode: .both), 67.8)
        XCTAssertEqual(formatter.percentage(snapshot: snapshot, metricMode: .highest), 67.8)
        XCTAssertEqual(formatter.percentage(snapshot: snapshot, metricMode: .fiveHour), 42.2)
        XCTAssertEqual(formatter.percentage(snapshot: snapshot, metricMode: .sevenDay), 67.8)
        XCTAssertNil(formatter.percentage(snapshot: nil, metricMode: .highest))
    }

    func testResetCountdownFormatsCompactDurations() {
        let formatter = ResetCountdownFormatter()
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(formatter.duration(until: now.addingTimeInterval(2 * 3_600 + 18 * 60), now: now), "2h 18m")
        XCTAssertEqual(formatter.duration(until: now.addingTimeInterval(6 * 86_400 + 5 * 3_600), now: now), "6d 5h")
        XCTAssertEqual(formatter.duration(until: now, now: now), "now")
    }

    func testResetCountdownFollowsMetricSelection() {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = UsageSnapshot(
            capturedAt: now,
            fiveHour: RateLimitWindow(usedPercentage: 20, resetsAt: now.addingTimeInterval(7_200)),
            sevenDay: RateLimitWindow(usedPercentage: 80, resetsAt: now.addingTimeInterval(172_800))
        )
        let formatter = ResetCountdownFormatter()

        XCTAssertEqual(formatter.menuBarText(snapshot: snapshot, metricMode: .both, now: now), "5h↻2:00")
        XCTAssertEqual(formatter.menuBarText(snapshot: snapshot, metricMode: .fiveHour, now: now), "↻2:00")
        XCTAssertEqual(formatter.menuBarText(snapshot: snapshot, metricMode: .sevenDay, now: now), "↻2d")
        XCTAssertEqual(formatter.menuBarText(snapshot: snapshot, metricMode: .highest, now: now), "7d↻2d")
    }
}
