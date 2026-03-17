import AVFoundation
import CoreMedia
import Foundation

enum RecordingCaptureSource: String, Codable {
    case system
    case microphone
}

struct ActiveRecordingSession: Codable {
    let id: UUID
    let mode: RecordingInputMode
    let destinationPath: String
    let startedAt: Date
    var pausedAt: Date?
    var totalPausedSeconds: Double
    var updatedAt: Date
    let systemCapturePath: String?
    let microphoneCapturePath: String?
}

struct RecoveredRecording {
    let audioURL: URL
    let mode: RecordingInputMode
    let durationSeconds: Double
}

final class RecordingSessionStore {
    private let fileManager: FileManager
    private let rootDirectoryURL: URL
    private let inProgressDirectoryURL: URL
    private let activeSessionURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager

        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        rootDirectoryURL = appSupport.appendingPathComponent("GZWhisper/recording-sessions", isDirectory: true)
        inProgressDirectoryURL = rootDirectoryURL.appendingPathComponent("in-progress", isDirectory: true)
        activeSessionURL = rootDirectoryURL.appendingPathComponent("active.json")

        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func stagingDirectoryURL() -> URL {
        inProgressDirectoryURL
    }

    func makeCaptureFileURL(sessionID: UUID, source: RecordingCaptureSource) -> URL {
        inProgressDirectoryURL.appendingPathComponent("\(sessionID.uuidString)-\(source.rawValue).m4a")
    }

    func saveActiveSession(_ session: ActiveRecordingSession) throws {
        try ensureDirectories()
        let data = try encoder.encode(session)
        try data.write(to: activeSessionURL, options: .atomic)
    }

    func loadActiveSession() -> ActiveRecordingSession? {
        guard let data = try? Data(contentsOf: activeSessionURL) else {
            return nil
        }
        return try? decoder.decode(ActiveRecordingSession.self, from: data)
    }

    func clearActiveSession() throws {
        if fileManager.fileExists(atPath: activeSessionURL.path) {
            try fileManager.removeItem(at: activeSessionURL)
        }
    }

    func recoverActiveSession(into transcriptsDirectoryURL: URL) throws -> RecoveredRecording? {
        guard let session = loadActiveSession() else {
            return nil
        }

        let preferredDestinationURL = URL(fileURLWithPath: session.destinationPath)
        if isUsableAudioFile(preferredDestinationURL) {
            try cleanupCaptureArtifacts(for: session, preserving: preferredDestinationURL)
            try clearActiveSession()
            return RecoveredRecording(
                audioURL: preferredDestinationURL,
                mode: session.mode,
                durationSeconds: durationForMedia(at: preferredDestinationURL)
            )
        }

        let systemURL = usableCaptureURL(path: session.systemCapturePath)
        let microphoneURL = usableCaptureURL(path: session.microphoneCapturePath)

        guard systemURL != nil || microphoneURL != nil else {
            try cleanupCaptureArtifacts(for: session, preserving: nil)
            try clearActiveSession()
            return nil
        }

        try fileManager.createDirectory(at: transcriptsDirectoryURL, withIntermediateDirectories: true)
        let destinationURL = uniqueDestinationURL(preferred: preferredDestinationURL, mode: session.mode, directory: transcriptsDirectoryURL)
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        switch session.mode {
        case .systemOnly:
            guard let sourceURL = systemURL ?? microphoneURL else {
                throw AudioCaptureServiceError.emptyRecording
            }
            try moveFile(from: sourceURL, to: destinationURL)
        case .microphoneOnly:
            guard let sourceURL = microphoneURL ?? systemURL else {
                throw AudioCaptureServiceError.emptyRecording
            }
            try moveFile(from: sourceURL, to: destinationURL)
        case .systemAndMicrophone:
            if let systemURL, let microphoneURL {
                do {
                    try mergeAudioFiles(first: systemURL, second: microphoneURL, outputURL: destinationURL)
                } catch {
                    try? fileManager.removeItem(at: destinationURL)
                    guard let fallback = preferredSingleSource(systemURL: systemURL, microphoneURL: microphoneURL) else {
                        throw AudioCaptureServiceError.emptyRecording
                    }
                    try moveFile(from: fallback, to: destinationURL)
                }
            } else if let sourceURL = preferredSingleSource(systemURL: systemURL, microphoneURL: microphoneURL) {
                try moveFile(from: sourceURL, to: destinationURL)
            } else {
                throw AudioCaptureServiceError.emptyRecording
            }
        }

        try cleanupCaptureArtifacts(for: session, preserving: destinationURL)
        try clearActiveSession()

        return RecoveredRecording(
            audioURL: destinationURL,
            mode: session.mode,
            durationSeconds: durationForMedia(at: destinationURL)
        )
    }

    private func ensureDirectories() throws {
        try fileManager.createDirectory(at: inProgressDirectoryURL, withIntermediateDirectories: true)
    }

    private func isUsableAudioFile(_ url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path) else {
            return false
        }
        return (try? fileSize(at: url)) ?? 0 > 1024
    }

    private func usableCaptureURL(path: String?) -> URL? {
        guard let path else {
            return nil
        }
        let url = URL(fileURLWithPath: path)
        return isUsableAudioFile(url) ? url : nil
    }

    private func uniqueDestinationURL(preferred: URL, mode: RecordingInputMode, directory: URL) -> URL {
        if !fileManager.fileExists(atPath: preferred.path) {
            return preferred
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        let modeToken: String
        switch mode {
        case .systemAndMicrophone:
            modeToken = "system-mic"
        case .microphoneOnly:
            modeToken = "mic"
        case .systemOnly:
            modeToken = "system"
        }

        let fileName = "recording-recovered-\(modeToken)-\(timestamp).m4a"
        return directory.appendingPathComponent(fileName)
    }

    private func preferredSingleSource(systemURL: URL?, microphoneURL: URL?) -> URL? {
        if let microphoneURL {
            return microphoneURL
        }
        if let systemURL {
            return systemURL
        }
        return nil
    }

    private func cleanupCaptureArtifacts(for session: ActiveRecordingSession, preserving urlToKeep: URL?) throws {
        let paths = [session.systemCapturePath, session.microphoneCapturePath].compactMap { $0 }
        for path in paths {
            let url = URL(fileURLWithPath: path)
            if url == urlToKeep {
                continue
            }
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
        }
    }

    private func moveFile(from sourceURL: URL, to destinationURL: URL) throws {
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: sourceURL, to: destinationURL)
    }

    private func fileSize(at url: URL) throws -> UInt64 {
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        return attributes[.size] as? UInt64 ?? 0
    }

    private func durationForMedia(at url: URL) -> Double {
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        if seconds.isFinite, seconds > 0 {
            return seconds
        }
        return 0
    }

    private func mergeAudioFiles(first: URL, second: URL, outputURL: URL) throws {
        let composition = AVMutableComposition()
        let firstAsset = AVURLAsset(url: first)
        let secondAsset = AVURLAsset(url: second)

        guard let firstTrack = firstAsset.tracks(withMediaType: .audio).first else {
            throw AudioCaptureServiceError.mergeFailed("System track is missing")
        }
        guard let secondTrack = secondAsset.tracks(withMediaType: .audio).first else {
            throw AudioCaptureServiceError.mergeFailed("Microphone track is missing")
        }

        guard
            let firstOutTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
            let secondOutTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            throw AudioCaptureServiceError.mergeFailed("Cannot create composition tracks")
        }

        do {
            try firstOutTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: firstAsset.duration),
                of: firstTrack,
                at: .zero
            )
            try secondOutTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: secondAsset.duration),
                of: secondTrack,
                at: .zero
            )
        } catch {
            throw AudioCaptureServiceError.mergeFailed(error.localizedDescription)
        }

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw AudioCaptureServiceError.mergeFailed("Cannot initialize AVAssetExportSession")
        }

        let audioMix = AVMutableAudioMix()
        let firstParams = AVMutableAudioMixInputParameters(track: firstOutTrack)
        firstParams.setVolume(1.0, at: .zero)
        let secondParams = AVMutableAudioMixInputParameters(track: secondOutTrack)
        secondParams.setVolume(1.0, at: .zero)
        audioMix.inputParameters = [firstParams, secondParams]

        exporter.outputURL = outputURL
        exporter.outputFileType = .m4a
        exporter.audioMix = audioMix

        let semaphore = DispatchSemaphore(value: 0)
        var completionError: Error?

        exporter.exportAsynchronously {
            switch exporter.status {
            case .completed:
                break
            case .failed, .cancelled:
                completionError = AudioCaptureServiceError.mergeFailed(
                    exporter.error?.localizedDescription ?? "Export failed"
                )
            default:
                completionError = AudioCaptureServiceError.mergeFailed("Unexpected export state")
            }
            semaphore.signal()
        }

        semaphore.wait()
        if let completionError {
            throw completionError
        }
    }
}
