import Foundation
import Combine

public final class ModelDownloadProgressManager: ObservableObject {
    public static let shared = ModelDownloadProgressManager()

    @Published public var isDownloading: Bool = false
    @Published public var progress: Double = 0.0 // 0.0 to 1.0
    @Published public var statusMessage: String = ""
    @Published public var modelName: String = ""
    @Published public var modelDisplayName: String = ""

    public var formattedPercent: String {
        "\(Int(progress * 100))%"
    }

    private init() {}

    public func start(modelName: String, displayName: String = "") {
        DispatchQueue.main.async {
            self.isDownloading = true
            self.progress = 0.05
            self.modelName = modelName
            self.modelDisplayName = displayName.isEmpty ? modelName : displayName
            self.statusMessage = "Starting download..."
        }
    }

    public func update(progress: Double, message: String) {
        DispatchQueue.main.async {
            self.isDownloading = true
            self.progress = min(1.0, max(self.progress, progress))
            self.statusMessage = message
        }
    }

    public func finish() {
        DispatchQueue.main.async {
            self.progress = 1.0
            self.statusMessage = "Ready"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                self.isDownloading = false
            }
        }
    }

    public func fail(error: String) {
        DispatchQueue.main.async {
            self.isDownloading = false
            self.statusMessage = "Failed: \(error)"
        }
    }
}
