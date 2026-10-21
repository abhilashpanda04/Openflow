import Foundation
import Combine
import AppKit

public final class ModelStorageManager: ObservableObject {
    public static let shared = ModelStorageManager()

    @Published public var downloadedWhisperModelIds: Set<String> = []
    @Published public var lastActionNotice: String = ""

    private var whisperKitModelsDirectory: URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return docs.appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
    }

    public init() {
        refresh()
    }

    public func refresh() {
        var downloaded: Set<String> = []
        guard let base = whisperKitModelsDirectory, FileManager.default.fileExists(atPath: base.path) else {
            DispatchQueue.main.async {
                self.downloadedWhisperModelIds = []
            }
            return
        }

        if let contents = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) {
            for folder in contents {
                let name = folder.lastPathComponent
                if name.hasPrefix(".") { continue }
                if let sub = try? FileManager.default.contentsOfDirectory(atPath: folder.path), !sub.isEmpty {
                    downloaded.insert(name)
                    for choice in WhisperModelChoice.allCases {
                        if name == choice.rawValue || name.contains(choice.rawValue) || choice.rawValue.contains(name) {
                            downloaded.insert(choice.rawValue)
                        }
                    }
                }
            }
        }

        DispatchQueue.main.async {
            self.downloadedWhisperModelIds = downloaded
        }
    }

    public func isWhisperModelDownloaded(_ model: WhisperModelChoice) -> Bool {
        if downloadedWhisperModelIds.contains(model.rawValue) {
            return true
        }
        return localFolder(for: model) != nil
    }

    public func localFolder(for model: WhisperModelChoice) -> URL? {
        guard let base = whisperKitModelsDirectory, FileManager.default.fileExists(atPath: base.path) else { return nil }
        let direct = base.appendingPathComponent(model.rawValue)
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        if let contents = try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: nil) {
            for folder in contents {
                let name = folder.lastPathComponent
                if name.hasPrefix(".") { continue }
                if name == model.rawValue || name.contains(model.rawValue) || model.rawValue.contains(name) {
                    if let sub = try? FileManager.default.contentsOfDirectory(atPath: folder.path), !sub.isEmpty {
                        return folder
                    }
                }
            }
        }
        return nil
    }

    public func deleteWhisperModel(_ model: WhisperModelChoice) {
        if let folder = localFolder(for: model) {
            try? FileManager.default.removeItem(at: folder)
        }
        offloadSpeechEngine()
        refresh()
        updateNotice("Deleted \(model.shortTitle) from disk")
    }

    public func deleteKokoroModel() {
        KokoroTTSEngine.shared.deleteModel()
        refresh()
        updateNotice("Deleted Kokoro-82M from disk")
    }

    public func offloadSpeechEngine() {
        AppDelegate.shared?.offloadSpeechEngine()
        updateNotice("Speech engine offloaded from RAM")
    }

    public func offloadReaderEngine() {
        KokoroTTSEngine.shared.offload()
        updateNotice("Kokoro reader offloaded from RAM")
    }

    public func offloadAll() {
        AppDelegate.shared?.offloadSpeechEngine()
        KokoroTTSEngine.shared.offload()
        updateNotice("All models offloaded from memory")
    }

    private func updateNotice(_ notice: String) {
        if Thread.isMainThread {
            self.lastActionNotice = notice
        } else {
            DispatchQueue.main.async {
                self.lastActionNotice = notice
            }
        }
    }
}
