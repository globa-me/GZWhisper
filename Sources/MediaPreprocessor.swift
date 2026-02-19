import AVFoundation
import Foundation
import UniformTypeIdentifiers

struct PreparedAudio {
    let url: URL
    let shouldCleanup: Bool
}

enum MediaPreprocessorError: LocalizedError {
    case exportUnavailable
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .exportUnavailable:
            return L10n.t("media.exportUnavailable")
        case let .exportFailed(details):
            return L10n.f("media.exportFailed", details)
        }
    }
}

enum MediaPreprocessor {
    static func prepareInput(from sourceURL: URL) throws -> PreparedAudio {
        let ext = sourceURL.pathExtension.lowercased()
        if let contentType = UTType(filenameExtension: ext), contentType.conforms(to: .movie) {
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("gzwhisper-audio-\(UUID().uuidString).m4a")

            try extractAudio(from: sourceURL, to: outputURL)
            return PreparedAudio(url: outputURL, shouldCleanup: true)
        }

        return PreparedAudio(url: sourceURL, shouldCleanup: false)
    }

    private static func extractAudio(from videoURL: URL, to outputURL: URL) throws {
        let asset = AVURLAsset(url: videoURL)

        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw MediaPreprocessorError.exportUnavailable
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a
        exportSession.timeRange = CMTimeRange(start: .zero, duration: asset.duration)

        let semaphore = DispatchSemaphore(value: 0)
        exportSession.exportAsynchronously {
            semaphore.signal()
        }
        semaphore.wait()

        if let error = exportSession.error {
            throw MediaPreprocessorError.exportFailed(error.localizedDescription)
        }

        guard exportSession.status == .completed else {
            throw MediaPreprocessorError.exportFailed(L10n.f("media.exportStatus", exportSession.status.rawValue))
        }
    }
}
