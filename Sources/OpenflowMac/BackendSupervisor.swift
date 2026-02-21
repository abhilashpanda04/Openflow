// Copyright 2025 Abhilash Panda
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation

enum BackendSupervisorError: LocalizedError {
    case alreadyRunning
    case backendDirectoryNotFound
    case bundledRuntimeNotFound
    case launcherUnavailable
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "Backend process is already running."
        case .backendDirectoryNotFound:
            return "Could not locate backend directory."
        case .bundledRuntimeNotFound:
            return "Bundled backend runtime is unavailable. Reinstall Openflow or use manual backend setup."
        case .launcherUnavailable:
            return "Could not find a backend launcher (bundled runtime, uv, or backend/.venv/bin/python)."
        case .launchFailed(let message):
            return message
        }
    }
}

struct BackendLaunchInfo {
    let commandDescription: String
    let workingDirectory: URL
}

private struct BackendLaunchCommand {
    let executableURL: URL
    let arguments: [String]
    let workingDirectory: URL
    let environment: [String: String]?
    let description: String
}

final class BackendSupervisor {
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutBuffer = ""
    private var stderrBuffer = ""
    var onProcessExit: ((Int32) -> Void)?
    var onOutputLine: ((String) -> Void)?

    var isRunning: Bool {
        process?.isRunning == true
    }

    func start(modelName: ModelName? = nil) throws -> BackendLaunchInfo {
        if isRunning {
            throw BackendSupervisorError.alreadyRunning
        }

        let launch = try resolveLaunchCommand(modelName: modelName)

        let process = Process()
        process.currentDirectoryURL = launch.workingDirectory
        process.executableURL = launch.executableURL
        process.arguments = launch.arguments
        if let environment = launch.environment {
            var merged = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                merged[key] = value
            }
            process.environment = merged
        }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                return
            }
            self?.consumeOutputChunk(text, isError: false)
        }

        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                return
            }
            self?.consumeOutputChunk(text, isError: true)
        }

        process.terminationHandler = { [weak self] terminated in
            NSLog("[Openflow][Backend] Process exited code=%d", terminated.terminationStatus)
            DispatchQueue.main.async {
                self?.onProcessExit?(terminated.terminationStatus)
            }
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

        return BackendLaunchInfo(commandDescription: launch.description, workingDirectory: launch.workingDirectory)
    }

    func stop() {
        guard let process else {
            return
        }

        if process.isRunning {
            process.terminate()
        }

        cleanupPipes()
        stdoutBuffer = ""
        stderrBuffer = ""
        self.process = nil
    }

    private func resolveBackendDirectory() throws -> URL {
        let fileManager = FileManager.default
        let cwd = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        var candidates: [URL] = [
            cwd.appendingPathComponent("../backend").standardizedFileURL,
            cwd.appendingPathComponent("backend").standardizedFileURL,
            cwd.appendingPathComponent("../services/backend").standardizedFileURL,
            cwd.appendingPathComponent("services/backend").standardizedFileURL,
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

    private func resolveLaunchCommand(modelName: ModelName? = nil) throws -> BackendLaunchCommand {
        let modelEnv = modelName.map { ["OPENFLOW_MODEL_NAME": $0.rawValue] }
        
        // Try app-installed backend first (from BackendInstaller)
        if let installedLaunch = resolveInstalledBackendCommand(modelName: modelName) {
            return installedLaunch
        }
        
        // Fall back to old bundled runtime (for compatibility)
        if let bundledLaunch = resolveBundledLaunchCommand(modelName: modelName) {
            return bundledLaunch
        }

        let backendDirectory = try resolveBackendDirectory()

        if commandExists("uv") {
            return BackendLaunchCommand(
                executableURL: URL(fileURLWithPath: "/usr/bin/env"),
                arguments: ["uv", "run", "python", "qwen_server.py"],
                workingDirectory: backendDirectory,
                environment: modelEnv,
                description: "uv run python qwen_server.py"
            )
        }

        let venvPython = backendDirectory.appendingPathComponent(".venv/bin/python")
        if FileManager.default.isExecutableFile(atPath: venvPython.path) {
            return BackendLaunchCommand(
                executableURL: venvPython,
                arguments: ["qwen_server.py"],
                workingDirectory: backendDirectory,
                environment: modelEnv,
                description: "./.venv/bin/python qwen_server.py"
            )
        }

        throw BackendSupervisorError.launcherUnavailable
    }
    
    private func resolveInstalledBackendCommand(modelName: ModelName? = nil) -> BackendLaunchCommand? {
        let installer = BackendInstaller.shared
        
        guard FileManager.default.isExecutableFile(atPath: installer.venvPythonPath.path) else {
            return nil
        }
        
        guard let backendSource = installer.bundledBackendSourcePath else {
            return nil
        }
        
        guard FileManager.default.fileExists(atPath: backendSource.appendingPathComponent("qwen_server.py").path) else {
            return nil
        }
        
        var environment: [String: String] = [:]
        if let modelName {
            environment["OPENFLOW_MODEL_NAME"] = modelName.rawValue
        }
        
        return BackendLaunchCommand(
            executableURL: installer.venvPythonPath,
            arguments: ["qwen_server.py"],
            workingDirectory: backendSource,
            environment: environment,
            description: "installed backend: \(installer.venvPythonPath.lastPathComponent) qwen_server.py"
        )
    }

    private func resolveBundledLaunchCommand(modelName: ModelName? = nil) -> BackendLaunchCommand? {
        let fileManager = FileManager.default

        for resourcesRoot in resourceRootCandidates() {
            let runtimeRoot = resourcesRoot.appendingPathComponent("backend-runtime")
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: runtimeRoot.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }

            let pythonCandidates = [
                runtimeRoot.appendingPathComponent("python-home/bin/python3"),
                runtimeRoot.appendingPathComponent("python-home/bin/python"),
                runtimeRoot.appendingPathComponent("bin/python3"),
                runtimeRoot.appendingPathComponent("bin/python"),
            ]
            let scriptCandidates = [
                runtimeRoot.appendingPathComponent("qwen_server.py"),
                runtimeRoot.appendingPathComponent("backend/qwen_server.py"),
            ]
            let sitePackagesCandidates = [
                runtimeRoot.appendingPathComponent("site-packages"),
                runtimeRoot.appendingPathComponent("lib/python3.13/site-packages"),
            ]

            guard let python = pythonCandidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) }),
                  let script = scriptCandidates.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
                continue
            }

            let sitePackages = sitePackagesCandidates.first(where: { fileManager.fileExists(atPath: $0.path) })
            var environment: [String: String] = [:]
            if let sitePackages {
                environment["PYTHONPATH"] = sitePackages.path
            }
            environment["PYTHONNOUSERSITE"] = "1"
            if let modelName {
                environment["OPENFLOW_MODEL_NAME"] = modelName.rawValue
            }

            return BackendLaunchCommand(
                executableURL: python,
                arguments: [script.path],
                workingDirectory: script.deletingLastPathComponent(),
                environment: environment,
                description: "bundled runtime: \(python.lastPathComponent) \(script.lastPathComponent)"
            )
        }

        return nil
    }

    private func resourceRootCandidates() -> [URL] {
        var candidates: [URL] = []

        if let bundleResources = Bundle.main.resourceURL {
            candidates.append(bundleResources.standardizedFileURL)
        }

        var executableDirectory = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        executableDirectory.deleteLastPathComponent()

        var cursor = executableDirectory
        for _ in 0..<8 {
            candidates.append(cursor.appendingPathComponent("../Resources").standardizedFileURL)
            candidates.append(cursor.appendingPathComponent("Resources").standardizedFileURL)
            cursor.deleteLastPathComponent()
        }

        return candidates
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

    private func consumeOutputChunk(_ text: String, isError: Bool) {
        if isError {
            stderrBuffer += text
            drainBuffer(isError: true)
        } else {
            stdoutBuffer += text
            drainBuffer(isError: false)
        }
    }

    private func drainBuffer(isError: Bool) {
        var buffer = isError ? stderrBuffer : stdoutBuffer
        let separators = CharacterSet(charactersIn: "\n\r")

        while let range = buffer.rangeOfCharacter(from: separators) {
            let line = String(buffer[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !line.isEmpty {
                emitOutput(line, isError: isError)
            }
            buffer = String(buffer[range.upperBound...])
        }

        if !buffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, buffer.count > 400 {
            let snapshot = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
            emitOutput(snapshot, isError: isError)
            buffer = ""
        }

        if isError {
            stderrBuffer = buffer
        } else {
            stdoutBuffer = buffer
        }
    }

    private func emitOutput(_ line: String, isError: Bool) {
        if isError {
            NSLog("[Openflow][Backend][stderr] %@", line)
        } else {
            NSLog("[Openflow][Backend] %@", line)
        }
        DispatchQueue.main.async {
            self.onOutputLine?(line)
        }
    }

    deinit {
        stop()
    }
}
