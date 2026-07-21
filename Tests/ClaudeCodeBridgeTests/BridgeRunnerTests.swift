import ClaudeCodeBridge
import Foundation
import BarometerCore
import XCTest

final class BridgeRunnerTests: XCTestCase {
    func testCaptureWritesOnlySanitizedSnapshot() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BridgeRunnerTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let cacheURL = root.appendingPathComponent("cache/usage.json")
        let manager = ClaudeSettingsManager(paths: ClaudeIntegrationPaths(
            settingsURL: root.appendingPathComponent("settings.json"),
            supportDirectoryURL: root.appendingPathComponent("support")
        ))
        let runner = BridgeRunner(cache: UsageCache(fileURL: cacheURL), settingsManager: manager)
        let sentinel = "DO-NOT-PERSIST-THIS-PROMPT"
        let privateModelID = "DO-NOT-PERSIST-MODEL-ID"
        let input = Data("{\"prompt\":\"\(sentinel)\",\"session_id\":\"PRIVATE-SESSION\",\"cost\":{\"total_cost_usd\":99},\"model\":{\"id\":\"\(privateModelID)\",\"display_name\":\"Claude Sonnet\"},\"context_window\":{\"remaining_percentage\":58,\"total_input_tokens\":123456},\"rate_limits\":{\"five_hour\":{\"used_percentage\":34,\"resets_at\":200}}}".utf8)

        XCTAssertTrue(runner.capture(input, now: Date(timeIntervalSince1970: 100)))
        let snapshot = try UsageCache(fileURL: cacheURL).read()
        XCTAssertEqual(snapshot?.fiveHour?.usedPercentage, 34)
        let persisted = String(decoding: try Data(contentsOf: cacheURL), as: UTF8.self)
        XCTAssertFalse(persisted.contains(sentinel))
        XCTAssertFalse(persisted.contains(privateModelID))
        XCTAssertFalse(persisted.contains("Claude Sonnet"))
        XCTAssertFalse(persisted.contains("remaining_percentage"))
        XCTAssertFalse(persisted.contains("total_cost_usd"))
        XCTAssertFalse(persisted.contains("total_input_tokens"))
        XCTAssertFalse(persisted.contains("PRIVATE-SESSION"))
    }

    func testOversizedOrInvalidInputDoesNotWrite() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BridgeRunnerTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = UsageCache(fileURL: root.appendingPathComponent("usage.json"))
        let runner = BridgeRunner(cache: cache, maximumInputSize: 4)

        XCTAssertFalse(runner.capture(Data("12345".utf8)))
        XCTAssertFalse(runner.capture(Data("bad".utf8)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.fileURL.path))
    }

    func testOlderSessionCannotOverwriteNewResetPeriod() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BridgeRunnerTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = UsageCache(fileURL: root.appendingPathComponent("usage.json"))
        let runner = BridgeRunner(cache: cache)

        XCTAssertTrue(runner.capture(
            Data(#"{"rate_limits":{"five_hour":{"used_percentage":65,"resets_at":200}}}"#.utf8),
            now: Date(timeIntervalSince1970: 100)
        ))
        XCTAssertTrue(runner.capture(
            Data(#"{"rate_limits":{"five_hour":{"used_percentage":0,"resets_at":400}}}"#.utf8),
            now: Date(timeIntervalSince1970: 210)
        ))
        XCTAssertTrue(runner.capture(
            Data(#"{"rate_limits":{"five_hour":{"used_percentage":65,"resets_at":200}}}"#.utf8),
            now: Date(timeIntervalSince1970: 220)
        ))

        let snapshot = try cache.read()
        XCTAssertEqual(snapshot?.fiveHour?.usedPercentage, 0)
        XCTAssertEqual(snapshot?.fiveHour?.resetsAt?.timeIntervalSince1970, 400)
    }
}
