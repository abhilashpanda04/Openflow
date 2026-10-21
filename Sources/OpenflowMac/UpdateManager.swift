import Foundation
import Combine
import Sparkle

public final class UpdateManager: ObservableObject {
    public static let shared = UpdateManager()

    private var updaterController: SPUStandardUpdaterController?

    @Published public var canCheckForUpdates: Bool = false
    @Published public var automaticallyChecksForUpdates: Bool = true
    @Published public var lastUpdateCheckDate: Date? = nil

    private var cancellables = Set<AnyCancellable>()

    private init() {
        // Only initialize Sparkle updater when running outside of automated test harnesses
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil &&
           NSClassFromString("XCTestCase") == nil {
            let controller = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            self.updaterController = controller

            controller.updater.publisher(for: \.canCheckForUpdates)
                .receive(on: DispatchQueue.main)
                .assign(to: &$canCheckForUpdates)

            controller.updater.publisher(for: \.lastUpdateCheckDate)
                .receive(on: DispatchQueue.main)
                .assign(to: &$lastUpdateCheckDate)

            self.automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        }
    }

    public func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }

    public func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        automaticallyChecksForUpdates = enabled
        updaterController?.updater.automaticallyChecksForUpdates = enabled
    }
}
