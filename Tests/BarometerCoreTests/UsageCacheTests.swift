import Foundation
import XCTest
@testable import BarometerCore

final class UsageCacheTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("BarometerCoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
    }

    func testRoundTripUsesRestrictedPermissionsAndDropsSensitiveInput() throws {
        let file = temporaryDirectory.appendingPathComponent("cache/usage.json")
        let cache = UsageCache(fileURL: file)
        let sensitive = "SENSITIVE-PROMPT-SENTINEL"
        let input = Data("{\"prompt\":\"\(sensitive)\",\"model\":{\"display_name\":\"Sonnet\"},\"context_window\":{\"remaining_percentage\":64},\"rate_limits\":{\"five_hour\":{\"used_percentage\":75}}}".utf8)
        let snapshot = try RateLimitParser().parse(input, capturedAt: Date(timeIntervalSince1970: 100))

        try cache.write(snapshot)

        XCTAssertEqual(try cache.read(), snapshot)
        let persisted = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        XCTAssertFalse(persisted.contains(sensitive))
        XCTAssertFalse(persisted.contains("Sonnet"))
        XCTAssertFalse(persisted.contains("remaining_percentage"))
        let fileMode = (try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue
        let directoryMode = (try FileManager.default.attributesOfItem(atPath: file.deletingLastPathComponent().path)[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(fileMode, 0o600)
        XCTAssertEqual(directoryMode, 0o700)
    }

    func testRejectsSymbolicLinkCache() throws {
        let target = temporaryDirectory.appendingPathComponent("target.json")
        try Data("{}".utf8).write(to: target)
        let link = temporaryDirectory.appendingPathComponent("usage.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        XCTAssertThrowsError(try UsageCache(fileURL: link).read()) {
            XCTAssertEqual($0 as? UsageCacheError, .symbolicLinkRejected)
        }
    }

    func testStalenessAndHighestUsage() {
        let snapshot = UsageSnapshot(
            capturedAt: Date(timeIntervalSince1970: 100),
            fiveHour: RateLimitWindow(usedPercentage: 20, resetsAt: nil),
            sevenDay: RateLimitWindow(usedPercentage: 80, resetsAt: nil)
        )
        XCTAssertFalse(snapshot.isStale(at: Date(timeIntervalSince1970: 699)))
        XCTAssertTrue(snapshot.isStale(at: Date(timeIntervalSince1970: 701)))
        XCTAssertEqual(snapshot.highestUsage, 80)
    }

    func testExpiredWindowNormalizesToZero() {
        let snapshot = UsageSnapshot(
            capturedAt: Date(timeIntervalSince1970: 100),
            fiveHour: RateLimitWindow(
                usedPercentage: 65,
                resetsAt: Date(timeIntervalSince1970: 200)
            ),
            sevenDay: RateLimitWindow(
                usedPercentage: 11,
                resetsAt: Date(timeIntervalSince1970: 500)
            )
        )

        let normalized = snapshot.normalized(at: Date(timeIntervalSince1970: 300))

        XCTAssertEqual(normalized.fiveHour?.usedPercentage, 0)
        XCTAssertEqual(normalized.fiveHour?.resetsAt?.timeIntervalSince1970, 200)
        XCTAssertEqual(normalized.sevenDay?.usedPercentage, 11)
    }

    func testNewResetPeriodWinsAndCannotBeOverwrittenByOldSession() {
        let oldPeriod = UsageSnapshot(
            capturedAt: Date(timeIntervalSince1970: 100),
            fiveHour: RateLimitWindow(
                usedPercentage: 65,
                resetsAt: Date(timeIntervalSince1970: 200)
            ),
            sevenDay: nil
        )
        let newPeriod = UsageSnapshot(
            capturedAt: Date(timeIntervalSince1970: 210),
            fiveHour: RateLimitWindow(
                usedPercentage: 0,
                resetsAt: Date(timeIntervalSince1970: 400)
            ),
            sevenDay: nil
        )
        let replayedOldPeriod = UsageSnapshot(
            capturedAt: Date(timeIntervalSince1970: 220),
            fiveHour: RateLimitWindow(
                usedPercentage: 65,
                resetsAt: Date(timeIntervalSince1970: 200)
            ),
            sevenDay: nil
        )

        let merged = oldPeriod.merging(newPeriod).merging(replayedOldPeriod)

        XCTAssertEqual(merged.fiveHour?.usedPercentage, 0)
        XCTAssertEqual(merged.fiveHour?.resetsAt?.timeIntervalSince1970, 400)
        XCTAssertEqual(merged.capturedAt.timeIntervalSince1970, 210)
    }

    func testSameResetPeriodDoesNotRegressFromIdleSessionReplay() {
        let current = UsageSnapshot(
            capturedAt: Date(timeIntervalSince1970: 100),
            fiveHour: RateLimitWindow(
                usedPercentage: 75,
                resetsAt: Date(timeIntervalSince1970: 400)
            ),
            sevenDay: nil
        )
        let replayed = UsageSnapshot(
            capturedAt: Date(timeIntervalSince1970: 110),
            fiveHour: RateLimitWindow(
                usedPercentage: 65,
                resetsAt: Date(timeIntervalSince1970: 400)
            ),
            sevenDay: nil
        )

        let merged = current.merging(replayed)

        XCTAssertEqual(merged.fiveHour?.usedPercentage, 75)
        XCTAssertEqual(merged.capturedAt.timeIntervalSince1970, 100)
    }

    func testLockedUpdateReadsAndReplacesCurrentSnapshot() throws {
        let file = temporaryDirectory.appendingPathComponent("locked/usage.json")
        let cache = UsageCache(fileURL: file)
        let first = UsageSnapshot(
            capturedAt: Date(timeIntervalSince1970: 100),
            fiveHour: RateLimitWindow(usedPercentage: 20, resetsAt: nil),
            sevenDay: nil
        )
        try cache.write(first)

        try cache.update { existing in
            XCTAssertEqual(existing, first)
            return UsageSnapshot(
                capturedAt: Date(timeIntervalSince1970: 110),
                fiveHour: RateLimitWindow(usedPercentage: 25, resetsAt: nil),
                sevenDay: nil
            )
        }

        XCTAssertEqual(try cache.read()?.fiveHour?.usedPercentage, 25)
        let lock = file.deletingLastPathComponent().appendingPathComponent(".usage.lock")
        let lockMode = (try FileManager.default.attributesOfItem(atPath: lock.path)[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(lockMode, 0o600)
    }

    func testEraseRemovesPersistedSnapshot() throws {
        let file = temporaryDirectory.appendingPathComponent("erase/usage.json")
        let cache = UsageCache(fileURL: file)
        try cache.write(UsageSnapshot(
            capturedAt: Date(timeIntervalSince1970: 100),
            fiveHour: RateLimitWindow(usedPercentage: 20, resetsAt: nil),
            sevenDay: nil
        ))
        XCTAssertNotNil(try cache.read())

        try cache.erase()

        XCTAssertNil(try cache.read())
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testEraseOnMissingCacheIsNoop() throws {
        let file = temporaryDirectory.appendingPathComponent("missing/usage.json")
        XCTAssertNoThrow(try UsageCache(fileURL: file).erase())
    }

    func testReadsCacheWrittenBeforeSessionDetailsWereRemoved() throws {
        let file = temporaryDirectory.appendingPathComponent("legacy/usage.json")
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"capturedAt":100,"fiveHour":{"usedPercentage":20},"latestSession":{"contextRemainingPercentage":73,"modelDisplayName":"Sonnet"},"schemaVersion":1,"sevenDay":null}"#.utf8).write(to: file)

        let snapshot = try UsageCache(fileURL: file).readSanitized()

        XCTAssertEqual(snapshot?.fiveHour?.usedPercentage, 20)
        let persisted = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        XCTAssertFalse(persisted.contains("latestSession"))
        XCTAssertFalse(persisted.contains("Sonnet"))
    }
}
