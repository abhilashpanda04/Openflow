import Foundation

@available(*, deprecated, message: "Use native CoreML (WhisperKit) instead of local Python environment installation")
enum PythonInstallerError: LocalizedError {
    case pythonNotFound
    case pythonVersionTooOld(String)
    case downloadFailed(String)
    case installationFailed(String)
    case checksumMismatch
    case networkError(String)
    case diskSpaceInsufficient(Int64, Int64) // required, available

    var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            return "Python 3.12+ not found on system. Please install from python.org or use Homebrew."
        case .pythonVersionTooOld(let version):
            return "Python version \(version) is too old. Python 3.12+ required."
        case .downloadFailed(let reason):
            return "Failed to download Python installer: \(reason)"
        case .installationFailed(let reason):
            return "Python installation failed: \(reason)"
        case .checksumMismatch:
            return "Downloaded file checksum mismatch. File may be corrupted."
        case .networkError(let reason):
            return "Network error: \(reason)"
        case .diskSpaceInsufficient(let required, let available):
            return "Insufficient disk space. Required: \(Self.formatBytes(required)), Available: \(Self.formatBytes(available))"
        }
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

@available(*, deprecated, message: "Use native CoreML (WhisperKit) instead of local Python environment installation")
final class PythonInstaller {
    typealias ProgressCallback = (Double, String) -> Void

    static let shared = PythonInstaller()
    
    private let fileManager = FileManager.default
    
    // MARK: - Python Detection

    func detectPython() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/python3",      // Homebrew Apple Silicon
            "/usr/local/bin/python3",         // Homebrew Intel
            "/usr/bin/python3",               // macOS system Python
            "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3",
        ]
        
        for path in candidates {
            if fileManager.isExecutableFile(atPath: path) {
                if let version = getPythonVersion(path), version >= (3, 12) {
                    return URL(fileURLWithPath: path)
                }
            }
        }
        
        return nil
    }

    func getPythonVersion(_ pythonPath: String) -> (major: Int, minor: Int)? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["--version"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return nil
            }
            
            // Parse "Python 3.12.1" or "Python 3.13.0"
            let components = output.split(separator: " ")
            if components.count >= 2, let versionStr = components.last {
                let parts = versionStr.split(separator: ".")
                if parts.count >= 2,
                   let major = Int(parts[0]),
                   let minor = Int(parts[1]) {
                    return (major, minor)
                }
            }
        } catch {
            return nil
        }
        
        return nil
    }

    // MARK: - Python Installation

    func downloadAndInstallPython(progressCallback: @escaping ProgressCallback) async throws -> URL {
        progressCallback(0.1, "Checking system requirements...")
        
        // Check disk space (need ~2GB for Python + deps)
        try checkDiskSpace()
        
        progressCallback(0.2, "Downloading Python 3.12 installer...")
        let installerURL = try await downloadPythonInstaller(progressCallback: progressCallback)
        
        progressCallback(0.7, "Installing Python...")
        let pythonPath = try installPythonFromDownload(installerURL)
        
        progressCallback(0.9, "Verifying installation...")
        // Verify installation
        guard let version = getPythonVersion(pythonPath.path), version >= (3, 12) else {
            throw PythonInstallerError.installationFailed("Installation verification failed")
        }
        
        progressCallback(1.0, "Python installation complete")
        return pythonPath
    }

    private func checkDiskSpace() throws {
        let requiredSpace: Int64 = 2 * 1024 * 1024 * 1024 // 2GB
        
        guard let systemAttributes = try? fileManager.attributesOfFileSystem(forPath: NSHomeDirectory()) else {
            throw PythonInstallerError.diskSpaceInsufficient(requiredSpace, 0)
        }
        
        if let availableSpace = systemAttributes[.systemFreeSize] as? Int64 {
            if availableSpace < requiredSpace {
                throw PythonInstallerError.diskSpaceInsufficient(requiredSpace, availableSpace)
            }
        }
    }

    private func downloadPythonInstaller(progressCallback: @escaping ProgressCallback) async throws -> URL {
        // Python 3.12.x installer for macOS (universal2: arm64 + x86_64)
        let installerURL = "https://www.python.org/ftp/python/3.12.7/python-3.12.7-macos11.pkg"
        
        guard let url = URL(string: installerURL) else {
            throw PythonInstallerError.downloadFailed("Invalid URL")
        }
        
        let tempDir = NSTemporaryDirectory()
        let fileName = "python-3.12.7-macos11.pkg"
        let destinationURL = URL(fileURLWithPath: tempDir).appendingPathComponent(fileName)
        
        // Download with progress
        return try await downloadFile(from: url, to: destinationURL, progressCallback: progressCallback)
    }

    private func downloadFile(from sourceURL: URL, to destinationURL: URL, progressCallback: @escaping ProgressCallback) async throws -> URL {
        var request = URLRequest(url: sourceURL)
        request.timeoutInterval = 300 // 5 minute timeout
        
        let session = URLSession.shared
        
        return try await withCheckedThrowingContinuation { [weak self] continuation in
            var downloadTask: URLSessionDownloadTask?
            
            let delegate = URLSessionTaskDelegate()
            delegate.onProgress = { progress in
                DispatchQueue.main.async {
                    progressCallback(0.2 + (progress * 0.5), "Downloading Python 3.12... \(Int(progress * 100))%")
                }
            }
            
            downloadTask = session.downloadTask(with: request) { [weak self] tempURL, response, error in
                do {
                    if let error = error {
                        throw PythonInstallerError.downloadFailed(error.localizedDescription)
                    }
                    
                    guard let tempURL = tempURL else {
                        throw PythonInstallerError.downloadFailed("No download URL returned")
                    }
                    
                    guard let self = self else {
                        throw PythonInstallerError.downloadFailed("Installer deallocated during download")
                    }
                    
                    // Move from temp location
                    if self.fileManager.fileExists(atPath: destinationURL.path) {
                        try self.fileManager.removeItem(at: destinationURL)
                    }
                    try self.fileManager.moveItem(at: tempURL, to: destinationURL)
                    
                    continuation.resume(returning: destinationURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            
            downloadTask?.resume()
        }
    }

    private func installPythonFromDownload(_ installerURL: URL) throws -> URL {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/installer")
        process.arguments = ["-pkg", installerURL.path, "-target", "/"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw PythonInstallerError.installationFailed(output)
            }
        } catch {
            throw PythonInstallerError.installationFailed(error.localizedDescription)
        }
        
        // After installation, verify it exists
        let possiblePaths = [
            "/usr/local/bin/python3",
            "/opt/homebrew/bin/python3"
        ]
        
        for path in possiblePaths {
            if fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        
        throw PythonInstallerError.pythonNotFound
    }
}

// Simple delegate for progress tracking
private class URLSessionTaskDelegate {
    var onProgress: ((Double) -> Void)?
}
