import Foundation
import XCTest
@testable import BarometerCore

final class LaunchAtLoginManagerTests: XCTestCase {
    private var root: URL!
    private var executable: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("LaunchAtLoginManagerTests-\(UUID().uuidString)")
        executable = root.appendingPathComponent("Barometer.app/Contents/MacOS/Barometer")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: executable.path, contents: Data()))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    override func tearDownWithError() throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testEnableCreatesRestrictedLaunchAgentAndDisableRemovesIt() throws {
        let manager = makeManager()
        try manager.setEnabled(true, executableURL: executable)

        XCTAssertTrue(manager.isEnabled)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(
            from: Data(contentsOf: manager.plistURL),
            options: [],
            format: nil
        ) as? [String: Any])
        XCTAssertEqual(plist["Label"] as? String, "io.test.barometer")
        XCTAssertEqual(plist["ProgramArguments"] as? [String], [executable.path])
        XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
        let mode = (try FileManager.default.attributesOfItem(atPath: manager.plistURL.path)[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(mode, 0o600)

        try manager.setEnabled(false, executableURL: executable)
        XCTAssertFalse(manager.isEnabled)
    }

    func testRefreshUpdatesExecutablePath() throws {
        let manager = makeManager()
        try manager.setEnabled(true, executableURL: executable)
        let moved = root.appendingPathComponent("Moved.app/Contents/MacOS/Barometer")
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(FileManager.default.createFile(atPath: moved.path, contents: Data()))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: moved.path)

        try manager.refreshExecutablePathIfEnabled(moved)

        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(
            from: Data(contentsOf: manager.plistURL), options: [], format: nil
        ) as? [String: Any])
        XCTAssertEqual(plist["ProgramArguments"] as? [String], [moved.path])
    }

    func testDoesNotOverwriteForeignLaunchAgent() throws {
        let manager = makeManager()
        try FileManager.default.createDirectory(at: manager.launchAgentsDirectoryURL, withIntermediateDirectories: true)
        try Data("not a plist".utf8).write(to: manager.plistURL)

        XCTAssertThrowsError(try manager.setEnabled(true, executableURL: executable)) {
            XCTAssertEqual($0 as? LaunchAtLoginError, .invalidExistingConfiguration)
        }
        XCTAssertEqual(try Data(contentsOf: manager.plistURL), Data("not a plist".utf8))
    }

    func testRejectsSymbolicLink() throws {
        let manager = makeManager()
        try FileManager.default.createDirectory(at: manager.launchAgentsDirectoryURL, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("target.plist")
        try Data("target".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: manager.plistURL, withDestinationURL: target)

        XCTAssertThrowsError(try manager.setEnabled(true, executableURL: executable))
        XCTAssertEqual(try Data(contentsOf: target), Data("target".utf8))
    }

    private func makeManager() -> LaunchAtLoginManager {
        LaunchAtLoginManager(
            launchAgentsDirectoryURL: root.appendingPathComponent("LaunchAgents"),
            label: "io.test.barometer"
        )
    }
}
