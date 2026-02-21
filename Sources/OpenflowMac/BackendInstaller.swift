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

enum BackendInstallerError: LocalizedError {
    case pythonNotAvailable
    case venvCreationFailed(String)
    case dependencyInstallationFailed(String)
    case pipNotFound
    case backendSourceNotFound
    case verificationFailed(String)

    var errorDescription: String? {
        switch self {
        case .pythonNotAvailable:
            return "Python 3.12+ is not available. Installation cannot proceed."
        case .venvCreationFailed(let reason):
            return "Failed to create Python virtual environment: \(reason)"
        case .dependencyInstallationFailed(let reason):
            return "Failed to install dependencies: \(reason)"
        case .pipNotFound:
            return "pip not found in virtual environment. Installation cannot proceed."
        case .backendSourceNotFound:
            return "Backend source files (pyproject.toml, qwen_server.py) not found in app bundle."
        case .verificationFailed(let reason):
            return "Installation verification failed: \(reason)"
        }
    }
}

final class BackendInstaller {
    typealias ProgressCallback = (Double, String) -> Void

    static let shared = BackendInstaller()
    
    private let fileManager = FileManager.default
    
    // MARK: - Paths
    
    var backendRuntimePath: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Openflow/backend-runtime")
    }
    
    var bundledBackendSourcePath: URL? {
        guard let bundleResources = Bundle.main.resourceURL else {
            return nil
        }
        let backendPath = bundleResources.appendingPathComponent("backend")
        if fileManager.fileExists(atPath: backendPath.path) {
            return backendPath
        }
        return nil
    }
    
    var venvPythonPath: URL {
        backendRuntimePath.appendingPathComponent("venv/bin/python")
    }
    
    var venvPath: URL {
        backendRuntimePath.appendingPathComponent("venv")
    }
    
    // MARK: - Installation Status
    
    var isInstalled: Bool {
        fileManager.isExecutableFile(atPath: venvPythonPath.path)
    }
    
    // MARK: - Installation Process
    
    func install(pythonPath: URL, progressCallback: @escaping ProgressCallback) async throws {
        progressCallback(0.0, "Preparing backend installation...")
        
        // Step 1: Verify backend source exists
        progressCallback(0.05, "Locating backend source files...")
        guard let backendSource = bundledBackendSourcePath else {
            throw BackendInstallerError.backendSourceNotFound
        }
        
        // Step 2: Create runtime directory
        progressCallback(0.1, "Creating installation directory...")
        try createRuntimeDirectory()
        
        // Step 3: Create virtual environment
        progressCallback(0.15, "Creating Python virtual environment...")
        try createVirtualEnvironment(pythonPath: pythonPath)
        
        // Step 4: Upgrade pip
        progressCallback(0.25, "Upgrading pip...")
        try upgradePip()
        
        // Step 5: Install dependencies
        progressCallback(0.35, "Installing dependencies (PyTorch, FastAPI, etc.)...")
        try installDependencies(backendSource: backendSource, progressCallback: progressCallback)
        
        // Step 6: Verify installation
        progressCallback(0.95, "Verifying installation...")
        try verifyInstallation()
        
        progressCallback(1.0, "Backend installation complete!")
    }
    
    // MARK: - Private Methods
    
    private func createRuntimeDirectory() throws {
        try fileManager.createDirectory(at: backendRuntimePath, withIntermediateDirectories: true, attributes: nil)
    }
    
    private func createVirtualEnvironment(pythonPath: URL) throws {
        let process = Process()
        process.executableURL = pythonPath
        process.arguments = ["-m", "venv", venvPath.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw BackendInstallerError.venvCreationFailed(output)
            }
        } catch let error as BackendInstallerError {
            throw error
        } catch {
            throw BackendInstallerError.venvCreationFailed(error.localizedDescription)
        }
    }
    
    private func upgradePip() throws {
        let process = Process()
        process.executableURL = venvPythonPath
        process.arguments = ["-m", "pip", "install", "--upgrade", "pip", "-q"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw BackendInstallerError.dependencyInstallationFailed(output)
            }
        } catch let error as BackendInstallerError {
            throw error
        } catch {
            throw BackendInstallerError.dependencyInstallationFailed(error.localizedDescription)
        }
    }
    
    private func installDependencies(backendSource: URL, progressCallback: @escaping ProgressCallback) throws {
        let process = Process()
        process.executableURL = venvPythonPath
        process.arguments = ["-m", "pip", "install", "-e", backendSource.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        // Capture output for progress
        var lastProgress: Double = 0.35
        let progressIncrement: Double = 0.60 / 20 // Distribute 60% across estimated 20 packages
        
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let output = String(data: data, encoding: .utf8) else {
                return
            }
            
            // Parse pip output for progress
            for line in output.split(separator: "\n") {
                if line.contains("Installing collected packages") || line.contains("Successfully installed") {
                    lastProgress = min(lastProgress + progressIncrement, 0.90)
                    DispatchQueue.main.async {
                        progressCallback(lastProgress, "Installing dependencies... \(Int(lastProgress * 100))%")
                    }
                }
            }
        }
        
        do {
            try process.run()
            process.waitUntilExit()
            
            pipe.fileHandleForReading.readabilityHandler = nil
            
            if process.terminationStatus != 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw BackendInstallerError.dependencyInstallationFailed(output)
            }
        } catch let error as BackendInstallerError {
            throw error
        } catch {
            throw BackendInstallerError.dependencyInstallationFailed(error.localizedDescription)
        }
    }
    
    private func verifyInstallation() throws {
        guard fileManager.isExecutableFile(atPath: venvPythonPath.path) else {
            throw BackendInstallerError.verificationFailed("Python executable not found in venv")
        }
        
        // Verify pip is available
        let process = Process()
        process.executableURL = venvPythonPath
        process.arguments = ["-m", "pip", "--version"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                throw BackendInstallerError.pipNotFound
            }
        } catch let error as BackendInstallerError {
            throw error
        } catch {
            throw BackendInstallerError.verificationFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Retry Logic
    
    func installWithRetry(pythonPath: URL, progressCallback: @escaping ProgressCallback, maxRetries: Int = 5) async throws {
        var lastError: Error?
        
        for attempt in 1...maxRetries {
            do {
                progressCallback(0.0, "Installation attempt \(attempt) of \(maxRetries)...")
                try await install(pythonPath: pythonPath, progressCallback: progressCallback)
                return
            } catch {
                lastError = error
                NSLog("[Openflow][BackendInstaller] Attempt \(attempt) failed: \(error.localizedDescription)")
                
                if attempt < maxRetries {
                    // Wait before retry (exponential backoff: 2s, 4s, 8s, 16s, 32s)
                    let delay = UInt32(pow(2.0, Double(attempt)))
                    progressCallback(0.0, "Installation failed. Retrying in \(delay)s... (attempt \(attempt + 1) of \(maxRetries))")
                    sleep(delay)
                }
            }
        }
        
        // All retries exhausted
        if let lastError = lastError {
            throw lastError
        }
        throw BackendInstallerError.dependencyInstallationFailed("Installation failed after \(maxRetries) attempts")
    }
}
