import ClaudeCodeBridge
import Foundation
import BarometerCore
import XCTest

final class ClaudeSettingsManagerTests: XCTestCase {
    private var root: URL!
    private var settingsURL: URL!
    private var supportURL: URL!
    private var helperURL: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeSettingsManagerTests-\(UUID().uuidString)")
        settingsURL = root.appendingPathComponent(".claude/settings.json")
        supportURL = root.appendingPathComponent("support")
        helperURL = root.appendingPathComponent("Barometer.app/Contents/Helpers/barometer-bridge")
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testInstallAndDisconnectWithEmptySettings() throws {
        let manager = makeManager()
        try manager.install(helperExecutableURL: helperURL, now: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(manager.status(), .connected)
        let settings = try json(at: settingsURL)
        let statusLine = try XCTUnwrap(settings["statusLine"] as? [String: Any])
        XCTAssertEqual(statusLine["type"] as? String, "command")
        XCTAssertEqual(statusLine["command"] as? String, ClaudeSettingsManager.shellQuote(helperURL.path))
        XCTAssertEqual(statusLine["refreshInterval"] as? Int, 60)
        XCTAssertNil(try manager.originalStatusLineCommand())

        try manager.disconnect()
        XCTAssertNil(try json(at: settingsURL)["statusLine"])
        XCTAssertEqual(manager.status(), .disconnected)
    }

    func testPreservesAndChainsExistingStatusLine() throws {
        try Data(#"{"theme":"dark","statusLine":{"type":"command","command":"printf existing","padding":2}}"#.utf8).write(to: settingsURL)
        let manager = makeManager()

        try manager.install(helperExecutableURL: helperURL)

        XCTAssertEqual(try manager.originalStatusLineCommand(), "printf existing")
        var settings = try json(at: settingsURL)
        XCTAssertEqual(settings["theme"] as? String, "dark")
        XCTAssertEqual((settings["statusLine"] as? [String: Any])?["padding"] as? Int, 2)

        try manager.disconnect()
        settings = try json(at: settingsURL)
        XCTAssertEqual((settings["statusLine"] as? [String: Any])?["command"] as? String, "printf existing")
    }

    func testInstallIsIdempotent() throws {
        let manager = makeManager()
        try manager.install(helperExecutableURL: helperURL, now: Date(timeIntervalSince1970: 100))
        let firstState = try Data(contentsOf: supportURL.appendingPathComponent("integration.json"))

        try manager.install(helperExecutableURL: helperURL, now: Date(timeIntervalSince1970: 200))

        XCTAssertEqual(try Data(contentsOf: supportURL.appendingPathComponent("integration.json")), firstState)
    }

    func testDisconnectStopsOnUserConflict() throws {
        let manager = makeManager()
        try manager.install(helperExecutableURL: helperURL)
        try Data(#"{"statusLine":{"type":"command","command":"user changed it"}}"#.utf8).write(to: settingsURL)

        XCTAssertEqual(manager.status(), .conflict)
        XCTAssertThrowsError(try manager.disconnect()) {
            XCTAssertEqual($0 as? ClaudeIntegrationError, .integrationConflict)
        }
        XCTAssertEqual((try json(at: settingsURL)["statusLine"] as? [String: Any])?["command"] as? String, "user changed it")
    }

    func testDetectsSettingsRace() throws {
        let raceURL = try XCTUnwrap(settingsURL)
        let manager = ClaudeSettingsManager(
            paths: paths,
            beforeCommit: {
                try Data(#"{"changed":true}"#.utf8).write(to: raceURL)
            }
        )

        XCTAssertThrowsError(try manager.install(helperExecutableURL: helperURL)) {
            XCTAssertEqual($0 as? ClaudeIntegrationError, .settingsChangedDuringInstall)
        }
        XCTAssertEqual(try json(at: settingsURL)["changed"] as? Bool, true)
    }

    func testRejectsSymlinkSettings() throws {
        let target = root.appendingPathComponent("actual.json")
        try Data("{}".utf8).write(to: target)
        try FileManager.default.removeItem(at: settingsURL.deletingLastPathComponent())
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: settingsURL, withDestinationURL: target)

        XCTAssertThrowsError(try makeManager().install(helperExecutableURL: helperURL))
        XCTAssertEqual(try Data(contentsOf: target), Data("{}".utf8))
    }

    func testRejectsMalformedSettings() throws {
        try Data("not json".utf8).write(to: settingsURL)
        XCTAssertThrowsError(try makeManager().install(helperExecutableURL: helperURL)) {
            XCTAssertEqual($0 as? ClaudeIntegrationError, .invalidSettings)
        }
    }

    func testEraseAllLocalDataDisconnectsAndRemovesBackups() throws {
        let manager = makeManager()
        try manager.install(helperExecutableURL: helperURL, now: Date(timeIntervalSince1970: 100))
        let backupsDirectory = supportURL.appendingPathComponent("backups")
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: backupsDirectory.path).isEmpty)

        try manager.eraseAllLocalData()

        XCTAssertEqual(manager.status(), .disconnected)
        XCTAssertNil(try json(at: settingsURL)["statusLine"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: supportURL.appendingPathComponent("integration.json").path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: backupsDirectory.path).isEmpty)
    }

    func testEraseAllLocalDataOnConflictKeepsSettingsButClearsLocalState() throws {
        let manager = makeManager()
        try manager.install(helperExecutableURL: helperURL)
        try Data(#"{"statusLine":{"type":"command","command":"user changed it"}}"#.utf8).write(to: settingsURL)
        XCTAssertEqual(manager.status(), .conflict)

        try manager.eraseAllLocalData()

        XCTAssertEqual((try json(at: settingsURL)["statusLine"] as? [String: Any])?["command"] as? String, "user changed it")
        XCTAssertFalse(FileManager.default.fileExists(atPath: supportURL.appendingPathComponent("integration.json").path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: supportURL.appendingPathComponent("backups").path).isEmpty)
    }

    private var paths: ClaudeIntegrationPaths {
        ClaudeIntegrationPaths(settingsURL: settingsURL, supportDirectoryURL: supportURL)
    }

    private func makeManager() -> ClaudeSettingsManager { ClaudeSettingsManager(paths: paths) }

    private func json(at url: URL) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
}
