@preconcurrency import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

enum RecordingInputMode: String, Codable, CaseIterable, Identifiable {
    case systemAndMicrophone
    case microphoneOnly
    case systemOnly

    var id: String { rawValue }

    var includesSystemAudio: Bool {
        self == .systemAndMicrophone || self == .systemOnly
    }

    var includesMicrophone: Bool {
        self == .systemAndMicrophone || self == .microphoneOnly
    }
}

enum AudioCaptureServiceError: LocalizedError {
    case alreadyRecording
    case notRecording
    case invalidState
    case microphoneAccessDenied
    case screenCaptureAccessDenied
    case screenCaptureUnavailable
    case noDisplay
    case cannotCreateWriter(String)
    case captureFailed(String)
    case writerFailed(String)
    case mergeFailed(String)
    case emptyRecording

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return L10n.t("record.error.alreadyRecording")
        case .notRecording:
            return L10n.t("record.error.notRecording")
        case .invalidState:
            return L10n.t("record.error.invalidState")
        case .microphoneAccessDenied:
            return L10n.t("record.error.microphoneDenied")
        case .screenCaptureAccessDenied:
            return L10n.t("record.error.screenDenied")
        case .screenCaptureUnavailable:
            return L10n.t("record.error.screenUnavailable")
        case .noDisplay:
            return L10n.t("record.error.noDisplay")
        case let .cannotCreateWriter(details):
            return L10n.f("record.error.writerCreate", details)
        case let .captureFailed(details):
            return L10n.f("record.error.capture", details)
        case let .writerFailed(details):
            return L10n.f("record.error.writer", details)
        case let .mergeFailed(details):
            return L10n.f("record.error.merge", details)
        case .emptyRecording:
            return L10n.t("record.error.empty")
        }
    }
}

final class AudioCaptureService: NSObject {
    private final class UncheckedSendableBox<T>: @unchecked Sendable {
        let value: T

        init(_ value: T) {
            self.value = value
        }
    }

    struct CaptureResult {
        let audioURL: URL
        let durationSeconds: Double
        let mode: RecordingInputMode
    }

    private enum CaptureState {
        case idle
        case recording
        case paused
        case stopping
    }

    private enum CaptureSource {
        case system
        case microphone
    }

    private let captureQueue = DispatchQueue(label: "com.gzwhisper.audio.capture", qos: .userInitiated)

    private var state: CaptureState = .idle
    private var mode: RecordingInputMode = .systemAndMicrophone
    private var destinationURL: URL?
    private var startedAt: Date?
    private var pausedAt: Date?
    private var totalPausedSeconds: Double = 0
    private var captureError: Error?

    private var systemWriter: AVAssetWriter?
    private var systemWriterInput: AVAssetWriterInput?
    private var systemTempURL: URL?
    private var systemHasSamples = false

    private var microphoneWriter: AVAssetWriter?
    private var microphoneWriterInput: AVAssetWriterInput?
    private var microphoneTempURL: URL?
    private var microphoneHasSamples = false

    private var microphoneSession: AVCaptureSession?
    private var microphoneOutput: AVCaptureAudioDataOutput?

    private var systemStream: AnyObject?

    var isRecording: Bool {
        syncQueue { state == .recording || state == .paused }
    }

    var isPaused: Bool {
        syncQueue { state == .paused }
    }

    func start(mode: RecordingInputMode, destinationURL: URL) async throws {
        try await requestPermissions(for: mode)

        try syncQueueThrows {
            guard state == .idle else {
                throw AudioCaptureServiceError.alreadyRecording
            }

            captureError = nil
            self.mode = mode
            self.destinationURL = destinationURL
            startedAt = Date()
            pausedAt = nil
            totalPausedSeconds = 0

            let fileNameBase = destinationURL.deletingPathExtension().lastPathComponent
            let tempDir = FileManager.default.temporaryDirectory
            systemTempURL = tempDir.appendingPathComponent("\(fileNameBase)-system-\(UUID().uuidString).m4a")
            microphoneTempURL = tempDir.appendingPathComponent("\(fileNameBase)-mic-\(UUID().uuidString).m4a")

            systemWriter = nil
            systemWriterInput = nil
            microphoneWriter = nil
            microphoneWriterInput = nil
            systemHasSamples = false
            microphoneHasSamples = false
            state = .recording
        }

        do {
            if mode.includesSystemAudio {
                try syncQueueThrows {
                    try setupWriter(for: .system)
                }
                try await startSystemCaptureIfNeeded()
            }

            if mode.includesMicrophone {
                try syncQueueThrows {
                    try setupWriter(for: .microphone)
                    try startMicrophoneCapture()
                }
            }
        } catch {
            try? await stopWithoutResult()
            throw error
        }
    }

    func pause() throws {
        try syncQueueThrows {
            guard state == .recording else {
                throw AudioCaptureServiceError.invalidState
            }
            pausedAt = Date()
            state = .paused
        }
    }

    func resume() throws {
        try syncQueueThrows {
            guard state == .paused else {
                throw AudioCaptureServiceError.invalidState
            }
            if let pausedAt {
                totalPausedSeconds += max(Date().timeIntervalSince(pausedAt), 0)
            }
            self.pausedAt = nil
            state = .recording
        }
    }

    func stop() async throws -> CaptureResult {
        let snapshot = try syncQueueThrows { () -> (RecordingInputMode, URL) in
            guard state == .recording || state == .paused else {
                throw AudioCaptureServiceError.notRecording
            }

            if state == .paused, let pausedAt {
                totalPausedSeconds += max(Date().timeIntervalSince(pausedAt), 0)
                self.pausedAt = nil
            }

            state = .stopping
            guard let destinationURL else {
                throw AudioCaptureServiceError.invalidState
            }
            return (mode, destinationURL)
        }

        try await stopSources()

        if let captureError = syncQueue({ self.captureError }) {
            cleanupTempFiles(except: nil)
            resetToIdle()
            throw captureError
        }

        let systemURL = try finishWriter(for: .system)
        let microphoneURL = try finishWriter(for: .microphone)

        let finalURL = try await exportFinalFile(
            mode: snapshot.0,
            destinationURL: snapshot.1,
            systemURL: systemURL,
            microphoneURL: microphoneURL
        )
        cleanupTempFiles(except: finalURL)

        let duration = durationForMedia(at: finalURL)
        resetToIdle()
        return CaptureResult(audioURL: finalURL, durationSeconds: duration, mode: snapshot.0)
    }

    func stopWithoutResult() async throws {
        if !isRecording {
            resetToIdle()
            return
        }

        try await stopSources()
        _ = try finishWriter(for: .system)
        _ = try finishWriter(for: .microphone)
        cleanupTempFiles(except: nil)
        resetToIdle()
    }

    private func setupWriter(for source: CaptureSource) throws {
        let tempURL: URL?
        let channels: Int

        switch source {
        case .system:
            tempURL = systemTempURL
            channels = 2
        case .microphone:
            tempURL = microphoneTempURL
            channels = 1
        }

        guard let tempURL else {
            throw AudioCaptureServiceError.invalidState
        }

        if FileManager.default.fileExists(atPath: tempURL.path) {
            try? FileManager.default.removeItem(at: tempURL)
        }

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(url: tempURL, fileType: .m4a)
        } catch {
            throw AudioCaptureServiceError.cannotCreateWriter(error.localizedDescription)
        }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: channels == 1 ? 64_000 : 96_000,
        ]

        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else {
            throw AudioCaptureServiceError.cannotCreateWriter("Cannot attach AVAssetWriterInput")
        }
        writer.add(input)

        switch source {
        case .system:
            systemWriter = writer
            systemWriterInput = input
            systemHasSamples = false
        case .microphone:
            microphoneWriter = writer
            microphoneWriterInput = input
            microphoneHasSamples = false
        }
    }

    private func startMicrophoneCapture() throws {
        let session = AVCaptureSession()
        session.beginConfiguration()

        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw AudioCaptureServiceError.captureFailed("Microphone device is unavailable")
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw AudioCaptureServiceError.captureFailed(error.localizedDescription)
        }

        guard session.canAddInput(input) else {
            throw AudioCaptureServiceError.captureFailed("Cannot add microphone input")
        }
        session.addInput(input)

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: captureQueue)
        guard session.canAddOutput(output) else {
            throw AudioCaptureServiceError.captureFailed("Cannot add microphone output")
        }
        session.addOutput(output)
        session.commitConfiguration()

        microphoneSession = session
        microphoneOutput = output
        session.startRunning()
    }

    private func startSystemCaptureIfNeeded() async throws {
        guard mode.includesSystemAudio else {
            return
        }

        guard #available(macOS 13.0, *) else {
            throw AudioCaptureServiceError.screenCaptureUnavailable
        }

        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw AudioCaptureServiceError.screenCaptureAccessDenied
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let targetDisplay = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
            throw AudioCaptureServiceError.noDisplay
        }

        let filter = SCContentFilter(display: targetDisplay, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = false
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.sampleRate = 44_100
        configuration.channelCount = 2

        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: captureQueue)
        try await stream.startCapture()

        syncQueue {
            self.systemStream = stream
        }
    }

    private func stopSources() async throws {
        if #available(macOS 13.0, *) {
            if let stream = syncQueue({ self.systemStream }) as? SCStream {
                do {
                    try await stream.stopCapture()
                } catch {
                    throw AudioCaptureServiceError.captureFailed(error.localizedDescription)
                }
                syncQueue {
                    self.systemStream = nil
                }
            }
        }

        syncQueue {
            if let microphoneOutput {
                microphoneOutput.setSampleBufferDelegate(nil, queue: nil)
            }
            microphoneSession?.stopRunning()
            microphoneSession = nil
            microphoneOutput = nil
        }
    }

    private func finishWriter(for source: CaptureSource) throws -> URL? {
        let payload = syncQueue { () -> (AVAssetWriter, AVAssetWriterInput, URL, Bool)? in
            switch source {
            case .system:
                guard let writer = systemWriter, let input = systemWriterInput, let url = systemTempURL else {
                    return nil
                }
                systemWriter = nil
                systemWriterInput = nil
                return (writer, input, url, systemHasSamples)
            case .microphone:
                guard let writer = microphoneWriter, let input = microphoneWriterInput, let url = microphoneTempURL else {
                    return nil
                }
                microphoneWriter = nil
                microphoneWriterInput = nil
                return (writer, input, url, microphoneHasSamples)
            }
        }

        guard let (writer, input, url, hasSamples) = payload else {
            return nil
        }

        if !hasSamples || writer.status == .unknown {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        input.markAsFinished()
        let semaphore = DispatchSemaphore(value: 0)
        var completionError: Error?
        let writerBox = UncheckedSendableBox(writer)

        writer.finishWriting {
            let writer = writerBox.value
            if writer.status != .completed {
                let message = writer.error?.localizedDescription ?? "Unknown writer error"
                completionError = AudioCaptureServiceError.writerFailed(message)
            }
            semaphore.signal()
        }
        semaphore.wait()

        if let completionError {
            throw completionError
        }

        return url
    }

    private func exportFinalFile(
        mode: RecordingInputMode,
        destinationURL: URL,
        systemURL: URL?,
        microphoneURL: URL?
    ) async throws -> URL {
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        switch mode {
        case .systemOnly:
            guard let systemURL else {
                throw AudioCaptureServiceError.emptyRecording
            }
            try FileManager.default.moveItem(at: systemURL, to: destinationURL)
            return destinationURL
        case .microphoneOnly:
            guard let microphoneURL else {
                throw AudioCaptureServiceError.emptyRecording
            }
            try FileManager.default.moveItem(at: microphoneURL, to: destinationURL)
            return destinationURL
        case .systemAndMicrophone:
            guard let systemURL, let microphoneURL else {
                throw AudioCaptureServiceError.emptyRecording
            }
            try mergeAudioFiles(first: systemURL, second: microphoneURL, outputURL: destinationURL)
            return destinationURL
        }
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
            let firstOutTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ),
            let secondOutTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
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
        let exporterBox = UncheckedSendableBox(exporter)

        exporter.exportAsynchronously {
            let exporter = exporterBox.value
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

    private func durationForMedia(at url: URL) -> Double {
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        if seconds.isFinite, seconds > 0 {
            return seconds
        }
        return 0
    }

    private func cleanupTempFiles(except finalURL: URL?) {
        syncQueue {
            let urls = [systemTempURL, microphoneTempURL].compactMap { $0 }
            for url in urls where url != finalURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func resetToIdle() {
        syncQueue {
            state = .idle
            mode = .systemAndMicrophone
            destinationURL = nil
            startedAt = nil
            pausedAt = nil
            totalPausedSeconds = 0
            captureError = nil
            systemWriter = nil
            systemWriterInput = nil
            microphoneWriter = nil
            microphoneWriterInput = nil
            microphoneSession = nil
            microphoneOutput = nil
            systemTempURL = nil
            microphoneTempURL = nil
            systemHasSamples = false
            microphoneHasSamples = false
            systemStream = nil
        }
    }

    private func requestPermissions(for mode: RecordingInputMode) async throws {
        if mode.includesMicrophone {
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
            }
            if !granted {
                throw AudioCaptureServiceError.microphoneAccessDenied
            }
        }
    }

    private func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer, source: CaptureSource) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        if state != .recording {
            return
        }

        let timingShift = CMTime(seconds: totalPausedSeconds, preferredTimescale: 1_000)
        guard let adjusted = Self.adjustSampleBuffer(sampleBuffer, shift: timingShift) else {
            return
        }

        let writer: AVAssetWriter?
        let input: AVAssetWriterInput?

        switch source {
        case .system:
            writer = systemWriter
            input = systemWriterInput
        case .microphone:
            writer = microphoneWriter
            input = microphoneWriterInput
        }

        guard let writer, let input else {
            return
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(adjusted)

        if writer.status == .unknown {
            writer.startWriting()
            writer.startSession(atSourceTime: presentationTime)
        }

        guard writer.status == .writing else {
            if writer.status == .failed {
                captureError = AudioCaptureServiceError.writerFailed(
                    writer.error?.localizedDescription ?? "Writer failed"
                )
            }
            return
        }

        guard input.isReadyForMoreMediaData else {
            return
        }

        if input.append(adjusted) {
            switch source {
            case .system:
                systemHasSamples = true
            case .microphone:
                microphoneHasSamples = true
            }
        } else {
            captureError = AudioCaptureServiceError.writerFailed(
                writer.error?.localizedDescription ?? "Failed appending sample buffer"
            )
        }
    }

    private static func adjustSampleBuffer(_ sampleBuffer: CMSampleBuffer, shift: CMTime) -> CMSampleBuffer? {
        guard shift.seconds > 0 else {
            return sampleBuffer
        }

        var neededCount = 0
        CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: 0,
            arrayToFill: nil,
            entriesNeededOut: &neededCount
        )

        guard neededCount > 0 else {
            return sampleBuffer
        }

        var timing = Array(
            repeating: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid),
            count: neededCount
        )

        CMSampleBufferGetSampleTimingInfoArray(
            sampleBuffer,
            entryCount: neededCount,
            arrayToFill: &timing,
            entriesNeededOut: &neededCount
        )

        for index in timing.indices {
            if timing[index].presentationTimeStamp.isValid {
                timing[index].presentationTimeStamp = timing[index].presentationTimeStamp - shift
            }
            if timing[index].decodeTimeStamp.isValid {
                timing[index].decodeTimeStamp = timing[index].decodeTimeStamp - shift
            }
        }

        var adjustedBuffer: CMSampleBuffer?
        let status = timing.withUnsafeMutableBufferPointer { pointer -> OSStatus in
            CMSampleBufferCreateCopyWithNewTiming(
                allocator: kCFAllocatorDefault,
                sampleBuffer: sampleBuffer,
                sampleTimingEntryCount: neededCount,
                sampleTimingArray: pointer.baseAddress,
                sampleBufferOut: &adjustedBuffer
            )
        }

        guard status == noErr else {
            return nil
        }

        return adjustedBuffer
    }

    private func syncQueue<T>(_ block: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return block()
        }

        return captureQueue.sync(execute: block)
    }

    private func syncQueueThrows<T>(_ block: () throws -> T) throws -> T {
        if DispatchQueue.getSpecific(key: queueKey) != nil {
            return try block()
        }

        var result: Result<T, Error>?
        captureQueue.sync {
            result = Result { try block() }
        }
        return try result!.get()
    }

    private let queueKey = DispatchSpecificKey<Void>()

    override init() {
        super.init()
        captureQueue.setSpecific(key: queueKey, value: ())
    }
}

extension AudioCaptureService: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        appendSampleBuffer(sampleBuffer, source: .microphone)
    }
}

@available(macOS 13.0, *)
extension AudioCaptureService: SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio else {
            return
        }
        appendSampleBuffer(sampleBuffer, source: .system)
    }
}
