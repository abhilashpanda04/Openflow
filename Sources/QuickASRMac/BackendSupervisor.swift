import Foundation

enum BackendSupervisorError: LocalizedError {
    case alreadyRunning
    case backendDirectoryNotFound
    case launcherUnavailable
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Backend process is already running."
        case .backendDirectoryNotFound:
            return "Could not locate backend directory."
        case .launcherUnavailable:
            return "Could not find a backend launcher (uv or backend/.venv/bin/python)."
        case .launchFailed(let message):
            return message
        }
    }
}

struct BackendLaunchInfo {
    let commandDescription: String
    let workingDirectory: URL
}

final class BackendSupervisor {
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    var isRunning: Bool {
        process?.isRunning == true
    }

    func start() throws -> BackendLaunchInfo {
        if isRunning {
            throw BackendSupervisorError.alreadyRunning
        }

        let backendDirectory = try resolveBackendDirectory()
        let launch = try resolveLaunchCommand(backendDirectory: backendDirectory)

        let process = Process()
        process.currentDirectoryURL = backendDirectory
        process.executableURL = launch.executableURL
        process.arguments = launch.arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                return
            }
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                NSLog("[Openflow][Backend] %@", String(line))
            }
        }

        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                return
            }
            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                NSLog("[Openflow][Backend][stderr] %@", String(line))
            }
        }

        process.terminationHandler = { terminated in
            NSLog("[Openflow][Backend] Process exited code=%d", terminated.terminationStatus)
        }

        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            throw BackendSupervisorError.launchFailed(error.localizedDescription)
        }

        self.process = process
        self.stdoutPipe = stdout
        self.stderrPipe = stderr

        return BackendLaunchInfo(commandDescription: launch.description, workingDirectory: backendDirectory)
    }

    func stop() {
        guard let process else {
            return
        }

        if process.isRunning {
            process.terminate()
        }

        cleanupPipes()
        self.process = nil
    }

    private func resolveBackendDirectory() throws -> URL {
        let fileManager = FileManager.default
        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        var candidates: [URL] = [
            cwd.appendingPathComponent("../backend").standardizedFileURL,
            cwd.appendingPathComponent("backend").standardizedFileURL,
        ]

        var executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        executableDirectory.deleteLastPathComponent()

        var cursor = executableDirectory
        for _ in 0..<8 {
            candidates.append(cursor.appendingPathComponent("backend").standardizedFileURL)
            candidates.append(cursor.appendingPathComponent("../backend").standardizedFileURL)
            cursor.deleteLastPathComponent()
        }

        for candidate in candidates {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
               isDirectory.boolValue,
               fileManager.fileExists(atPath: candidate.appendingPathComponent("qwen_server.py").path) {
                return candidate
            }
        }

        throw BackendSupervisorError.backendDirectoryNotFound
    }

    private func resolveLaunchCommand(backendDirectory: URL) throws -> (executableURL: URL, arguments: [String], description: String) {
        if commandExists("uv") {
            return (
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["uv", "run", "python", "qwen_server.py"],
                description: "uv run python qwen_server.py"
            )
        }

        let venvPython = backendDirectory.appendingPathComponent(".venv/bin/python")
        if FileManager.default.isExecutableFile(atPath: venvPython.path) {
            return (
                executableURL: venvPython,
                arguments: ["qwen_server.py"],
                description: "./.venv/bin/python qwen_server.py"
            )
        }

        throw BackendSupervisorError.launcherUnavailable
    }

    private func commandExists(_ command: String) -> Bool {
        let checker = Process()
        checker.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        checker.arguments = [command]
        checker.standardOutput = Pipe()
        checker.standardError = Pipe()

        do {
            try checker.run()
            checker.waitUntilExit()
            return checker.terminationStatus == 0
        } catch {
            return false
        }
    }

    private func cleanupPipes() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil
    }

    deinit {
        stop()
    }
}
