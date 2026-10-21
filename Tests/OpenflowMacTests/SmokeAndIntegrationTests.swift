import Darwin
import Foundation
import XCTest
@testable import OpenflowMac

final class SmokeTests: XCTestCase {
    func testSmokeAppConfigLoadsWithSaneDefaults() {
        let config = AppConfig.load()
        XCTAssertFalse(config.backendBaseURL.absoluteString.isEmpty)
        XCTAssertGreaterThan(config.requestTimeoutSeconds, 0)
        XCTAssertGreaterThanOrEqual(config.maxRetryCount, 0)
        XCTAssertGreaterThan(config.maxUploadBytes, 0)
    }

    func testSmokeHotKeyDefaultIsParseableAndStable() {
        let parsed = HotKeyConfiguration.parse("cmd+shift+space")
        XCTAssertEqual(parsed.keyCode, HotKeyConfiguration.default.keyCode)
        XCTAssertEqual(parsed.modifiers, HotKeyConfiguration.default.modifiers)
        XCTAssertEqual(parsed.displayText, HotKeyConfiguration.default.displayText)
    }
}

final class BackendSupervisorIntegrationTests: XCTestCase {
    private var originalDirectoryPath = ""
    private var originalPathEnv: String?
    private var temporaryRoots: [URL] = []

    override func setUp() {
        super.setUp()
        originalDirectoryPath = FileManager.default.currentDirectoryPath
        originalPathEnv = ProcessInfo.processInfo.environment["PATH"]
    }

    override func tearDown() {
        _ = FileManager.default.changeCurrentDirectoryPath(originalDirectoryPath)
        restorePathEnvironment()

        for root in temporaryRoots {
            try? FileManager.default.removeItem(at: root)
        }
        temporaryRoots.removeAll()
        super.tearDown()
    }

    func testIntegrationBackendSupervisorStartsStopsAndEmitsOutput() throws {
        let root = try makeFakeBackendWorkspace()
        XCTAssertTrue(FileManager.default.changeCurrentDirectoryPath(root.path))
        setenv("PATH", "", 1) // Force `.venv/bin/python` launcher path in this test.

        let supervisor = BackendSupervisor()
        let outputExpectation = expectation(description: "backend output observed")
        let exitExpectation = expectation(description: "backend process exit observed")

        var outputLines: [String] = []
        supervisor.onOutputLine = { line in
            outputLines.append(line)
            if line.contains(ModelName.accurate17B.rawValue) {
                outputExpectation.fulfill()
            }
        }
        supervisor.onProcessExit = { code in
            XCTAssertTrue(code == 0 || code == 15)
            exitExpectation.fulfill()
        }

        let launchInfo = try supervisor.start(modelName: .accurate17B)
        XCTAssertTrue(supervisor.isRunning)
        XCTAssertEqual(launchInfo.workingDirectory.lastPathComponent, "backend")
        XCTAssertTrue(launchInfo.commandDescription.contains(".venv/bin/python"))

        wait(for: [outputExpectation], timeout: 3)
        supervisor.stop()
        wait(for: [exitExpectation], timeout: 3)
        XCTAssertFalse(supervisor.isRunning)
        XCTAssertTrue(outputLines.contains { $0.contains("backend-ready") })
        XCTAssertTrue(outputLines.contains { $0.contains(ModelName.accurate17B.rawValue) })
    }

    func testIntegrationBackendSupervisorThrowsWhenStartedTwice() throws {
        let root = try makeFakeBackendWorkspace()
        XCTAssertTrue(FileManager.default.changeCurrentDirectoryPath(root.path))
        setenv("PATH", "", 1)

        let supervisor = BackendSupervisor()
        _ = try supervisor.start(modelName: .fast06B)
        defer { supervisor.stop() }

        XCTAssertThrowsError(try supervisor.start(modelName: .fast06B)) { error in
            guard case BackendSupervisorError.alreadyRunning = error else {
                XCTFail("Expected alreadyRunning but got \(error)")
                return
            }
        }
    }

    private func makeFakeBackendWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("openflow-integration-\(UUID().uuidString)", isDirectory: true)
        let backendDirectory = root.appendingPathComponent("backend", isDirectory: true)
        let binDirectory = backendDirectory.appendingPathComponent(".venv/bin", isDirectory: true)

        try FileManager.default.createDirectory(at: binDirectory, withIntermediateDirectories: true)

        let serverScript = backendDirectory.appendingPathComponent("qwen_server.py")
        try "print('placeholder')\n".write(to: serverScript, atomically: true, encoding: .utf8)

        let fakePython = binDirectory.appendingPathComponent("python")
        let launcher = """
        #!/bin/sh
        echo backend-ready
        if [ -n "$OPENFLOW_MODEL_NAME" ]; then
          echo "model:$OPENFLOW_MODEL_NAME"
        fi
        sleep 1
        exit 0
        """
        try launcher.write(to: fakePython, atomically: true, encoding: .utf8)
        try setExecutablePermission(for: fakePython)

        temporaryRoots.append(root)
        return root
    }

    private func setExecutablePermission(for fileURL: URL) throws {
        let status = chmod(fileURL.path, 0o755)
        if status != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    private func restorePathEnvironment() {
        if let originalPathEnv {
            setenv("PATH", originalPathEnv, 1)
        } else {
            unsetenv("PATH")
        }
    }
}
