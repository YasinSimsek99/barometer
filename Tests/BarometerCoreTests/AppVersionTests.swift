import XCTest
@testable import BarometerCore

final class AppVersionTests: XCTestCase {
    func testParsesWithAndWithoutVPrefix() throws {
        XCTAssertEqual(AppVersion("1.0.0")?.components, [1, 0, 0])
        XCTAssertEqual(AppVersion("v1.0.0")?.components, [1, 0, 0])
        XCTAssertEqual(AppVersion("V1.2.3")?.components, [1, 2, 3])
    }

    func testRejectsInvalidStrings() {
        XCTAssertNil(AppVersion(""))
        XCTAssertNil(AppVersion("v"))
        XCTAssertNil(AppVersion("latest"))
        XCTAssertNil(AppVersion("1.0.a"))
    }

    func testComparesNumericallyNotLexicographically() throws {
        let v1_9_0 = try XCTUnwrap(AppVersion("1.9.0"))
        let v1_10_0 = try XCTUnwrap(AppVersion("1.10.0"))
        XCTAssertLessThan(v1_9_0, v1_10_0)
        XCTAssertFalse(v1_10_0 < v1_9_0)
    }

    func testComparesDifferentComponentCounts() throws {
        let v1_0 = try XCTUnwrap(AppVersion("1.0"))
        let v1_0_1 = try XCTUnwrap(AppVersion("1.0.1"))
        XCTAssertLessThan(v1_0, v1_0_1)
        XCTAssertEqual(v1_0, try XCTUnwrap(AppVersion("1.0.0")))
    }

    func testEqualVersionsAreNeitherLessThanTheOther() throws {
        let a = try XCTUnwrap(AppVersion("1.2.3"))
        let b = try XCTUnwrap(AppVersion("v1.2.3"))
        XCTAssertEqual(a, b)
        XCTAssertFalse(a < b)
        XCTAssertFalse(b < a)
    }
}
