import Foundation
import XCTest
@testable import BarometerCore

final class RateLimitParserTests: XCTestCase {
    func testParsesOnlyAllowlistedRateLimitFields() throws {
        let input = Data(#"""
        {
          "session_id":"SENSITIVE-SESSION",
          "cwd":"/private/secret",
          "transcript_path":"SENSITIVE-TRANSCRIPT",
          "model":{"id":"SENSITIVE-MODEL-ID","display_name":"Claude Opus"},
          "context_window":{"remaining_percentage":73,"total_input_tokens":999999},
          "cost":{"total_cost_usd":123.45},
          "rate_limits":{
            "five_hour":{"used_percentage":42.4,"resets_at":1784674800},
            "seven_day":{"used_percentage":"68","resets_at":1785106800}
          }
        }
        """#.utf8)

        let captured = Date(timeIntervalSince1970: 1_784_670_000)
        let result = try RateLimitParser().parse(input, capturedAt: captured)

        XCTAssertEqual(result.capturedAt, captured)
        XCTAssertEqual(result.fiveHour?.usedPercentage, 42.4)
        XCTAssertEqual(result.fiveHour?.resetsAt?.timeIntervalSince1970, 1_784_674_800)
        XCTAssertEqual(result.sevenDay?.usedPercentage, 68)
    }

    func testMissingRateLimitsDoesNotCreateSnapshot() {
        XCTAssertThrowsError(try RateLimitParser().parse(Data(#"{"cwd":"/secret"}"#.utf8))) {
            XCTAssertEqual($0 as? RateLimitParserError, .noRateLimits)
        }
    }

    func testRejectsOutOfRangeAndNonFiniteValues() {
        for input in [
            #"{"rate_limits":{"five_hour":{"used_percentage":101}}}"#,
            #"{"rate_limits":{"five_hour":{"used_percentage":-1}}}"#,
            #"{"rate_limits":{"five_hour":{"used_percentage":"nan"}}}"#,
        ] {
            XCTAssertThrowsError(try RateLimitParser().parse(Data(input.utf8)))
        }
    }

    func testAllowsIndependentWindows() throws {
        let result = try RateLimitParser().parse(Data(#"{"rate_limits":{"seven_day":{"used_percentage":12}}}"#.utf8))
        XCTAssertNil(result.fiveHour)
        XCTAssertEqual(result.sevenDay?.usedPercentage, 12)
    }

    func testUnrelatedSessionDetailsDoNotAffectRateLimits() throws {
        let longName = String(repeating: "x", count: 81)
        let input = Data("{\"model\":{\"display_name\":\"\(longName)\"},\"context_window\":{\"remaining_percentage\":101},\"rate_limits\":{\"five_hour\":{\"used_percentage\":10}}}".utf8)
        let result = try RateLimitParser().parse(input)

        XCTAssertEqual(result.fiveHour?.usedPercentage, 10)
    }
}
