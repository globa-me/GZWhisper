import AVFoundation
import AppKit
import Foundation
import UniformTypeIdentifiers

enum TranscriptJobState: String, Codable, Hashable {
    case ready
    case queued
    case processing
    case completed
    case failed

    var isTerminal: Bool {
        self == .completed || self == .failed
    }
}

struct TranscriptHistoryItem: Identifiable, Codable {
    let id: UUID
    var sourceFileName: String
    var customName: String?
    var sourceFilePath: String
    var createdAt: Date
    var mediaDurationSeconds: Double?
    var audioPath: String?
    var transcriptPath: String?
    var detectedLanguage: String?
    var modelID: String?
    var recordingMode: RecordingInputMode?
    var state: TranscriptJobState
    var queueOrder: Int?
    var errorMessage: String?
    var progressFraction: Double? = nil
    var etaSeconds: Double? = nil
    var isRuntimeOnly = false

    init(
        id: UUID = UUID(),
        sourceFileName: String,
        customName: String? = nil,
        sourceFilePath: String,
        createdAt: Date,
        mediaDurationSeconds: Double?,
        audioPath: String? = nil,
        transcriptPath: String? = nil,
        detectedLanguage: String? = nil,
        modelID: String? = nil,
        recordingMode: RecordingInputMode? = nil,
        state: TranscriptJobState,
        queueOrder: Int? = nil,
        errorMessage: String? = nil,
        progressFraction: Double? = nil,
        etaSeconds: Double? = nil,
        isRuntimeOnly: Bool = false
    ) {
        self.id = id
        self.sourceFileName = sourceFileName
        self.customName = customName
        self.sourceFilePath = sourceFilePath
        self.createdAt = createdAt
        self.mediaDurationSeconds = mediaDurationSeconds
        self.audioPath = audioPath
        self.transcriptPath = transcriptPath
        self.detectedLanguage = detectedLanguage
        self.modelID = modelID
        self.recordingMode = recordingMode
        self.state = state
        self.queueOrder = queueOrder
        self.errorMessage = errorMessage
        self.progressFraction = progressFraction
        self.etaSeconds = etaSeconds
        self.isRuntimeOnly = isRuntimeOnly
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sourceFileName
        case customName
        case sourceFilePath
        case createdAt
        case mediaDurationSeconds
        case audioPath
        case transcriptPath
        case detectedLanguage
        case modelID
        case recordingMode
        case state
        case queueOrder
        case errorMessage
    }

    var hasTranscript: Bool {
        transcriptPath != nil
    }

    var hasAudio: Bool {
        audioPath != nil
    }

    var displayName: String {
        let normalized = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? sourceFileName : normalized
    }

    var hasCustomName: Bool {
        let normalized = customName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !normalized.isEmpty && normalized != sourceFileName
    }
}

private struct HistorySearchSource: Sendable, Equatable {
    let id: UUID
    let metadata: String
    let transcriptPath: String?
}

private actor HistorySearchIndex {
    private struct CachedEntry {
        let source: HistorySearchSource
        let transcriptModificationDate: Date?
        let normalizedText: String
    }

    private var entries: [UUID: CachedEntry] = [:]

    func matchingItemIDs(query: String, sources: [HistorySearchSource]) -> Set<UUID>? {
        let normalizedQuery = Self.normalized(query)
        guard !normalizedQuery.isEmpty else {
            return Set(sources.map(\.id))
        }

        var matches: Set<UUID> = []
        let activeIDs = Set(sources.map(\.id))
        entries = entries.filter { activeIDs.contains($0.key) }

        for source in sources {
            guard !Task.isCancelled else {
                return nil
            }

            let modificationDate = source.transcriptPath.flatMap(Self.modificationDate)
            let normalizedText: String

            if
                let cached = entries[source.id],
                cached.source == source,
                cached.transcriptModificationDate == modificationDate
            {
                normalizedText = cached.normalizedText
            } else {
                let transcriptText = source.transcriptPath.flatMap { path in
                    try? String(contentsOfFile: path, encoding: .utf8)
                } ?? ""
                normalizedText = Self.normalized(source.metadata + "\n" + transcriptText)
                entries[source.id] = CachedEntry(
                    source: source,
                    transcriptModificationDate: modificationDate,
                    normalizedText: normalizedText
                )
            }

            if normalizedText.contains(normalizedQuery) {
                matches.insert(source.id)
            }
        }

        return matches
    }

    private static func modificationDate(for path: String) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return attributes?[.modificationDate] as? Date
    }

    private static func normalized(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    private struct PendingHistoryDeletion {
        let item: TranscriptHistoryItem
        let originalIndex: Int
        let wasSelected: Bool
    }

    @Published var modelStatus = L10n.t("status.modelNotLoaded")
    @Published var modelLocationText = ""
    @Published var modelSourceText = ""
    @Published var modelHubURL = URL(string: WhisperEngine.modelSourceURLs.first ?? "https://huggingface.co")!

    @Published var statusMessage = L10n.t("status.ready")
    @Published var transcriptText = ""
    @Published var selectedLanguage = "auto"
    @Published var detectedLanguage = "-"

    @Published var isDownloadingModel = false
    @Published var isTranscribing = false
    @Published var isQueuePaused = false
    @Published var shouldPauseQueueAfterCurrent = false
    @Published var downloadSourceText = ""
    @Published var downloadProgressText = ""
    @Published var downloadProgressFraction = 0.0
    @Published var hasKnownDownloadTotal = false
    @Published var runtimeIssueMessage: String?
    @Published private(set) var hasConnectedModel = false

    @Published var historyItems: [TranscriptHistoryItem] = []
    @Published var selectedHistoryItemID: UUID?

    @Published var activeProgressFraction: Double?
    @Published var activeETA: String = ""
    @Published var currentTranscribingFileName: String = ""
    @Published var selectedRecordingMode: RecordingInputMode = .systemAndMicrophone
    @Published var isRecording = false
    @Published var isRecordingPaused = false
    @Published var isStoppingRecording = false
    @Published var recordingElapsedText = "00:00:00"
    @Published var isRecordingHUDVisible = true
    @Published private(set) var pendingHistoryDeletionName: String?
    @Published var shouldShowHUDOnRecordingStart = true {
        didSet {
            UserDefaults.standard.set(shouldShowHUDOnRecordingStart, forKey: Self.showHUDOnRecordingStartKey)
        }
    }
    @Published var shouldAutoPauseOnSleep = true {
        didSet {
            UserDefaults.standard.set(shouldAutoPauseOnSleep, forKey: Self.autoPauseOnSleepKey)
        }
    }

    let languageOptions = L10n.transcriptionLanguageOptions
    let appVersionLabel: String
    let appBuildLabel: String
    let recordingModeOptions = RecordingInputMode.allCases

    private let engine = WhisperEngine.shared
    private let audioCaptureService = AudioCaptureService()
    private let recordingSessionStore = RecordingSessionStore()
    private let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.includesCount = true
        return formatter
    }()

    private let historyDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var segments: [TranscriptionSegment] = []
    private var lastModelID: String?
    private var currentModelReference: LocalModelReference?
    private var currentEditorSourcePath: String?
    private var recordingStartedAt: Date?
    private var recordingPausedAt: Date?
    private var recordingPausedTotalSeconds: Double = 0
    private var recordingTimer: Timer?
    private var activeRecordingSession: ActiveRecordingSession?
    private let historySearchIndex = HistorySearchIndex()
    private var workspaceObservers: [NSObjectProtocol] = []
    private var activeTranscriptionRunHandle: TranscriptionRunHandle?
    private var isQueueCancellationRequested = false
    private var isSkippingCurrentQueueItem = false
    private var activeQueueFilterIDs: Set<UUID>?
    private var pendingHistoryDeletion: PendingHistoryDeletion?
    private var pendingHistoryDeletionTask: Task<Void, Never>?
    private let historyPersistenceQueue = DispatchQueue(label: "com.gzwhisper.history.persistence", qos: .utility)
    private static let showHUDOnRecordingStartKey = "recording.showHUDOnStart"
    private static let autoPauseOnSleepKey = "recording.autoPauseOnSleep"
    private static let largeMediaSizeThresholdBytes: Int64 = 2 * 1024 * 1024 * 1024
    private static let longMediaDurationThresholdSeconds: Double = 60 * 60

    var canStartQueue: Bool {
        !isDownloadingModel && !isTranscribing && !isRecording && !isStoppingRecording && hasConnectedModel && hasQueuedItems && runtimeIssueMessage == nil
    }

    var canCancelQueue: Bool {
        isTranscribing
    }

    var canResumeQueue: Bool {
        isQueuePaused && canStartQueue
    }

    var canStartSelectedQueue: Bool {
        guard
            !isDownloadingModel,
            !isTranscribing,
            !isRecording,
            !isStoppingRecording,
            hasConnectedModel,
            runtimeIssueMessage == nil,
            let selectedHistoryItem
        else {
            return false
        }

        return canRunHistoryItem(selectedHistoryItem)
    }

    var canClearQueue: Bool {
        hasQueuedItems
    }

    var canSkipCurrentQueueItem: Bool {
        isTranscribing && activeProcessingItem != nil
    }

    var canDeleteModel: Bool {
        hasConnectedModel && !isDownloadingModel && !isTranscribing && !isRecording
    }

    var shouldShowDownloadProgress: Bool {
        isDownloadingModel
    }

    var hasQueuedItems: Bool {
        historyItems.contains(where: { $0.state == .queued })
    }

    var queueCount: Int {
        historyItems.filter { $0.state == .queued }.count
    }

    var historyCount: Int {
        historyItems.count
    }

    var queueSummaryText: String {
        if queueCount == 0 {
            return L10n.t("text.queueEmpty")
        }

        if queueCount == 1 {
            return L10n.t("text.queueSingle")
        }

        return L10n.f("text.queueMany", queueCount)
    }

    var activeProcessingItem: TranscriptHistoryItem? {
        historyItems.first(where: { $0.state == .processing })
    }

    var selectedHistoryItem: TranscriptHistoryItem? {
        guard let selectedHistoryItemID else {
            return nil
        }
        return historyItems.first(where: { $0.id == selectedHistoryItemID })
    }

    var canStartRecording: Bool {
        !isRecording && !isStoppingRecording && !isDownloadingModel
    }

    var canUndoHistoryDeletion: Bool {
        pendingHistoryDeletion != nil
    }

    var canStopRecording: Bool {
        isRecording && !isStoppingRecording
    }

    var canPauseRecording: Bool {
        isRecording && !isRecordingPaused && !isStoppingRecording
    }

    var canResumeRecording: Bool {
        isRecording && isRecordingPaused && !isStoppingRecording
    }

    init() {
        appVersionLabel = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.5.1"
        appBuildLabel = AppViewModel.normalizedBundleBuildLabel(
            Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        ) ?? "2508261"
    }

    deinit {
        pendingHistoryDeletionTask?.cancel()
        historyPersistenceQueue.sync {}
        recordingTimer?.invalidate()
        let notificationCenter = NSWorkspace.shared.notificationCenter
        for observer in workspaceObservers {
            notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    func initialize() {
        shouldShowHUDOnRecordingStart = UserDefaults.standard.object(forKey: Self.showHUDOnRecordingStartKey) as? Bool ?? true
        shouldAutoPauseOnSleep = UserDefaults.standard.object(forKey: Self.autoPauseOnSleepKey) as? Bool ?? true
        refreshModelStatus()
        refreshRuntimeIssue()
        loadHistoryFromDisk()
        setupWorkspaceObservers()
        activeRecordingSession = recordingSessionStore.loadActiveSession()
        let recovered = recoverInterruptedRecordingIfNeeded()

        if let runtimeIssueMessage, !recovered {
            statusMessage = runtimeIssueMessage
        }
    }

    func chooseFiles() {
        guard !isRecording else {
            statusMessage = L10n.t("record.status.stopFirst")
            return
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.audio, .movie]
        panel.prompt = L10n.t("panel.choosePrompt")

        if panel.runModal() == .OK {
            addMediaFiles(panel.urls)
        }
    }

    func handleDroppedProviders(_ providers: [NSItemProvider]) -> Bool {
        if isRecording {
            statusMessage = L10n.t("record.status.stopFirst")
            return false
        }

        guard !providers.isEmpty else {
            return false
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        var accepted = false

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }

                let resolvedURL: URL?
                if let data = item as? Data {
                    resolvedURL = URL(dataRepresentation: data, relativeTo: nil)
                } else if let url = item as? URL {
                    resolvedURL = url
                } else if let string = item as? String, let url = URL(string: string), url.isFileURL {
                    resolvedURL = url
                } else {
                    resolvedURL = nil
                }

                guard let resolvedURL else { return }
                lock.lock()
                urls.append(resolvedURL)
                lock.unlock()
            }
        }

        guard accepted else {
            return false
        }

        group.notify(queue: .main) {
            self.addMediaFiles(urls)
        }

        return true
    }

    func downloadModelWithFolderPrompt() {
        guard !isDownloadingModel else { return }
        guard ensureRuntimeReady() else { return }

        let defaultDirectory = engine.defaultDownloadDirectory()
        try? FileManager.default.createDirectory(at: defaultDirectory, withIntermediateDirectories: true)

        let panel = NSOpenPanel()
        panel.title = L10n.t("panel.downloadModelTitle")
        panel.message = L10n.t("panel.downloadModelMessage")
        panel.prompt = L10n.t("panel.downloadModelPrompt")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = defaultDirectory

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        startModelDownload(to: destinationURL)
    }

    func connectExistingLocalModel() {
        guard !isDownloadingModel else { return }
        guard ensureRuntimeReady() else { return }

        let panel = NSOpenPanel()
        panel.title = L10n.t("panel.connectModelTitle")
        panel.message = L10n.t("panel.connectModelMessage")
        panel.prompt = L10n.t("panel.connectModelPrompt")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = engine.defaultDownloadDirectory()

        guard panel.runModal() == .OK, let modelURL = panel.url else {
            return
        }

        let engine = self.engine

        statusMessage = L10n.t("status.validatingModel")

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try engine.connectLocalModel(at: modelURL) { message in
                    DispatchQueue.main.async {
                        self.statusMessage = message
                    }
                }

                DispatchQueue.main.async {
                    self.refreshModelStatus()
                    self.statusMessage = L10n.t("status.localModelConnected")
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    func revealModelInFinder() {
        guard let path = currentModelReference?.modelPath else {
            statusMessage = L10n.t("status.modelFolderNotFound")
            return
        }

        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func deleteModel() {
        guard canDeleteModel, let reference = currentModelReference else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.t("alert.deleteModelTitle")

        if reference.sourceType == .downloaded {
            alert.informativeText = L10n.t("alert.deleteDownloadedInfo")
        } else {
            alert.informativeText = L10n.t("alert.deleteLinkedInfo")
        }

        alert.addButton(withTitle: L10n.t("button.delete"))
        alert.addButton(withTitle: L10n.t("button.cancel"))

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let engine = self.engine
        statusMessage = L10n.t("status.deletingModel")

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let outcome = try engine.deleteCurrentModel()

                DispatchQueue.main.async {
                    self.refreshModelStatus()
                    switch outcome {
                    case let .deletedFiles(path):
                        self.statusMessage = L10n.f("status.modelDeleted", path)
                    case let .unlinked(path):
                        self.statusMessage = L10n.f("status.modelUnlinked", path)
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    func recordingModeTitle(_ mode: RecordingInputMode) -> String {
        switch mode {
        case .systemAndMicrophone:
            return L10n.t("record.mode.systemMic")
        case .microphoneOnly:
            return L10n.t("record.mode.mic")
        case .systemOnly:
            return L10n.t("record.mode.system")
        }
    }

    func recordingModeShortTitle(_ mode: RecordingInputMode) -> String {
        switch mode {
        case .systemAndMicrophone:
            return L10n.t("record.mode.short.systemMic")
        case .microphoneOnly:
            return L10n.t("record.mode.short.mic")
        case .systemOnly:
            return L10n.t("record.mode.short.system")
        }
    }

    func startRecording() {
        guard canStartRecording else {
            return
        }

        let mode = selectedRecordingMode
        let startedAt = Date()
        let sessionID = UUID()
        let destinationURL = Self.makeRecordingFileURL(
            createdAt: startedAt,
            mode: mode,
            in: transcriptsDirectoryURL
        )
        let activeSession = ActiveRecordingSession(
            id: sessionID,
            mode: mode,
            destinationPath: destinationURL.path,
            startedAt: startedAt,
            pausedAt: nil,
            totalPausedSeconds: 0,
            updatedAt: startedAt,
            systemCapturePath: mode.includesSystemAudio
                ? recordingSessionStore.makeCaptureFileURL(sessionID: sessionID, source: .system).path
                : nil,
            microphoneCapturePath: mode.includesMicrophone
                ? recordingSessionStore.makeCaptureFileURL(sessionID: sessionID, source: .microphone).path
                : nil
        )

        statusMessage = L10n.t("record.status.starting")

        Task {
            do {
                try FileManager.default.createDirectory(at: transcriptsDirectoryURL, withIntermediateDirectories: true)
                try recordingSessionStore.saveActiveSession(activeSession)
                try await audioCaptureService.start(
                    mode: mode,
                    destinationURL: destinationURL,
                    sessionID: sessionID,
                    stagingDirectoryURL: recordingSessionStore.stagingDirectoryURL()
                )
                self.activeRecordingSession = activeSession

                recordingStartedAt = startedAt
                recordingPausedAt = nil
                recordingPausedTotalSeconds = 0
                isRecording = true
                isRecordingPaused = false
                isStoppingRecording = false
                isRecordingHUDVisible = shouldShowHUDOnRecordingStart
                recordingElapsedText = "00:00:00"
                startRecordingTimer()
                statusMessage = L10n.t("record.status.recording")
            } catch {
                isRecording = false
                isRecordingPaused = false
                isStoppingRecording = false
                recordingStartedAt = nil
                recordingPausedAt = nil
                recordingPausedTotalSeconds = 0
                recordingElapsedText = "00:00:00"
                stopRecordingTimer()
                clearActiveRecordingSession()
                statusMessage = error.localizedDescription
            }
        }
    }

    func pauseRecording() {
        guard canPauseRecording else {
            return
        }

        do {
            try audioCaptureService.pause()
            isRecordingPaused = true
            let pausedAt = Date()
            recordingPausedAt = pausedAt
            updateActiveRecordingSession { session in
                session.pausedAt = pausedAt
                session.totalPausedSeconds = recordingPausedTotalSeconds
            }
            statusMessage = L10n.t("record.status.paused")
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func resumeRecording() {
        guard canResumeRecording else {
            return
        }

        do {
            try audioCaptureService.resume()
            if let recordingPausedAt {
                recordingPausedTotalSeconds += max(Date().timeIntervalSince(recordingPausedAt), 0)
            }
            self.recordingPausedAt = nil
            updateActiveRecordingSession { session in
                session.pausedAt = nil
                session.totalPausedSeconds = recordingPausedTotalSeconds
            }
            isRecordingPaused = false
            statusMessage = L10n.t("record.status.recording")
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func stopRecording() {
        guard canStopRecording else {
            return
        }

        statusMessage = L10n.t("record.status.stopping")
        let wasPaused = isRecordingPaused
        let pausedAt = recordingPausedAt

        isStoppingRecording = true
        isRecordingPaused = false
        recordingPausedAt = nil
        stopRecordingTimer()

        Task {
            do {
                if wasPaused, let pausedAt {
                    recordingPausedTotalSeconds += max(Date().timeIntervalSince(pausedAt), 0)
                }
                updateActiveRecordingSession { session in
                    session.pausedAt = nil
                    session.totalPausedSeconds = recordingPausedTotalSeconds
                }

                let result = try await audioCaptureService.stop()
                addRecordingToHistory(result)
                clearActiveRecordingSession()
                statusMessage = L10n.f("record.status.saved", result.audioURL.lastPathComponent)
            } catch {
                if let audioError = error as? AudioCaptureServiceError {
                    switch audioError {
                    case .notRecording, .invalidState:
                        if !recoverInterruptedRecordingIfNeeded() {
                            statusMessage = error.localizedDescription
                        }
                    default:
                        statusMessage = error.localizedDescription
                    }
                } else {
                    statusMessage = error.localizedDescription
                }
            }

            isRecording = false
            isStoppingRecording = false
            recordingStartedAt = nil
            recordingPausedAt = nil
            recordingPausedTotalSeconds = 0
            recordingElapsedText = "00:00:00"
        }
    }

    func toggleRecordingPause() {
        if isRecordingPaused {
            resumeRecording()
        } else {
            pauseRecording()
        }
    }

    func hideRecordingHUD() {
        isRecordingHUDVisible = false
    }

    func showRecordingHUD() {
        isRecordingHUDVisible = true
    }

    func transcribeAllQueuedFiles() {
        startQueue(filterIDs: nil)
    }

    func transcribeSelectedHistoryItem() {
        guard let selectedHistoryItemID else {
            statusMessage = L10n.t("status.pickFileFirst")
            return
        }

        transcribeHistoryItemNow(selectedHistoryItemID)
    }

    func transcribeHistoryItemNow(_ id: UUID) {
        transcribeHistoryItemsNow([id])
    }

    func transcribeHistoryItemsNow(_ ids: Set<UUID>) {
        guard !ids.isEmpty else {
            statusMessage = L10n.t("status.pickFileFirst")
            return
        }

        var runnableIDs: Set<UUID> = []

        for id in ids {
            guard let index = historyItems.firstIndex(where: { $0.id == id }) else {
                continue
            }

            guard historyItems[index].state != .processing else {
                continue
            }

            guard historyItems[index].state == .queued || canQueueHistoryItem(historyItems[index]) else {
                continue
            }

            guard FileManager.default.fileExists(atPath: historyItems[index].sourceFilePath) else {
                historyItems[index].state = .failed
                historyItems[index].queueOrder = nil
                historyItems[index].errorMessage = L10n.f("status.fileMissing", historyItems[index].displayName)
                continue
            }

            ensureItemQueued(at: index)
            runnableIDs.insert(id)
        }

        guard !runnableIDs.isEmpty else {
            persistHistoryToDisk()
            statusMessage = L10n.t("status.queueEmpty")
            return
        }

        selectedHistoryItemID = runnableIDs.first
        normalizeQueueOrders()
        sortHistoryByDateDesc()
        persistHistoryToDisk()
        startQueue(filterIDs: runnableIDs)
    }

    func resumeQueue() {
        guard canResumeQueue else {
            return
        }

        isQueuePaused = false
        shouldPauseQueueAfterCurrent = false
        isQueueCancellationRequested = false
        isSkippingCurrentQueueItem = false
        isTranscribing = true
        processNextQueuedItem()
    }

    func togglePauseQueueAfterCurrent() {
        guard isTranscribing else {
            return
        }

        shouldPauseQueueAfterCurrent.toggle()
        statusMessage = shouldPauseQueueAfterCurrent
            ? L10n.t("status.queuePauseRequested")
            : L10n.t("status.queuePauseCancelled")
    }

    func skipCurrentQueueItem() {
        guard canSkipCurrentQueueItem else {
            return
        }

        isSkippingCurrentQueueItem = true
        activeTranscriptionRunHandle?.cancel()
        activeProgressFraction = nil
        activeETA = ""
        statusMessage = L10n.t("status.queueSkippingCurrent")
    }

    func clearQueuedItems() {
        guard hasQueuedItems else {
            statusMessage = L10n.t("status.queueEmpty")
            return
        }

        var clearedCount = 0
        historyItems = historyItems.compactMap { item in
            guard item.state == .queued else {
                return item
            }

            clearedCount += 1

            if item.isRuntimeOnly && item.transcriptPath == nil && item.audioPath == nil {
                return nil
            }

            var copy = item
            copy.state = .ready
            copy.queueOrder = nil
            copy.errorMessage = nil
            copy.progressFraction = nil
            copy.etaSeconds = nil
            return copy
        }

        if !hasQueuedItems {
            shouldPauseQueueAfterCurrent = false
            if isQueuePaused {
                isQueuePaused = false
                activeQueueFilterIDs = nil
            }
        }

        sortHistoryByDateDesc()
        persistHistoryToDisk()
        statusMessage = L10n.f("status.queueCleared", clearedCount)
    }

    func removeHistoryItemFromQueue(_ id: UUID) {
        guard let index = historyItems.firstIndex(where: { $0.id == id }), historyItems[index].state == .queued else {
            return
        }

        if historyItems[index].isRuntimeOnly && historyItems[index].transcriptPath == nil && historyItems[index].audioPath == nil {
            let name = historyItems[index].displayName
            historyItems.remove(at: index)
            statusMessage = L10n.f("status.queueRemoved", name)
        } else {
            historyItems[index].state = .ready
            historyItems[index].queueOrder = nil
            historyItems[index].errorMessage = nil
            historyItems[index].progressFraction = nil
            historyItems[index].etaSeconds = nil
            statusMessage = L10n.f("status.queueRemoved", historyItems[index].displayName)
        }

        sortHistoryByDateDesc()
        persistHistoryToDisk()
    }

    func moveQueuedHistoryItemUp(_ id: UUID) {
        moveQueuedHistoryItem(id, offset: -1)
    }

    func moveQueuedHistoryItemDown(_ id: UUID) {
        moveQueuedHistoryItem(id, offset: 1)
    }

    func canMoveQueuedHistoryItemUp(_ item: TranscriptHistoryItem) -> Bool {
        queuedOnlyItemIDsInOrder().first != item.id && item.state == .queued
    }

    func canMoveQueuedHistoryItemDown(_ item: TranscriptHistoryItem) -> Bool {
        queuedOnlyItemIDsInOrder().last != item.id && item.state == .queued
    }

    func queuePositionText(for item: TranscriptHistoryItem) -> String? {
        let activeStates: Set<TranscriptJobState> = [.queued, .processing]
        guard activeStates.contains(item.state) else {
            return nil
        }

        guard let index = queuedItemIDsInOrder().firstIndex(of: item.id) else {
            return nil
        }

        return L10n.f("status.queuePosition", index + 1)
    }

    private func startQueue(filterIDs: Set<UUID>?) {
        guard ensureRuntimeReady() else { return }
        guard !isRecording else {
            statusMessage = L10n.t("record.status.stopFirst")
            return
        }

        guard hasConnectedModel else {
            statusMessage = L10n.t("status.connectModelFirst")
            return
        }

        guard !isTranscribing else { return }

        guard hasQueuedItems else {
            statusMessage = L10n.t("status.queueEmpty")
            return
        }

        isQueueCancellationRequested = false
        isSkippingCurrentQueueItem = false
        isQueuePaused = false
        shouldPauseQueueAfterCurrent = false
        activeQueueFilterIDs = filterIDs
        isTranscribing = true
        processNextQueuedItem()
    }

    func cancelTranscriptionQueue() {
        guard isTranscribing else {
            return
        }

        isQueueCancellationRequested = true
        isSkippingCurrentQueueItem = false
        activeTranscriptionRunHandle?.cancel()
        activeProgressFraction = nil
        activeETA = ""
        statusMessage = L10n.t("status.queueCancelling")
    }

    func queueHistoryItemForTranscription(_ id: UUID) {
        guard let index = historyItems.firstIndex(where: { $0.id == id }) else {
            return
        }

        guard historyItems[index].state != .processing else {
            return
        }

        let fileExists = FileManager.default.fileExists(atPath: historyItems[index].sourceFilePath)
        guard fileExists else {
            historyItems[index].state = .failed
            historyItems[index].errorMessage = L10n.f("status.fileMissing", historyItems[index].displayName)
            persistHistoryToDisk()
            statusMessage = historyItems[index].errorMessage ?? L10n.t("status.failed")
            return
        }

        historyItems[index].state = .queued
        historyItems[index].queueOrder = nextQueueOrder()
        historyItems[index].errorMessage = nil
        historyItems[index].progressFraction = nil
        historyItems[index].etaSeconds = nil
        selectedHistoryItemID = id
        statusMessage = L10n.f("status.fileSelected", historyItems[index].displayName)
        sortHistoryByDateDesc()
        persistHistoryToDisk()

        if hasConnectedModel, !isTranscribing {
            transcribeAllQueuedFiles()
        }
    }

    func canQueueHistoryItem(_ item: TranscriptHistoryItem) -> Bool {
        if item.state == .processing {
            return false
        }
        if item.state == .queued {
            return false
        }
        if item.state == .completed, item.transcriptPath != nil {
            return false
        }
        return FileManager.default.fileExists(atPath: item.sourceFilePath)
    }

    func canRunHistoryItem(_ item: TranscriptHistoryItem) -> Bool {
        (item.state == .queued || canQueueHistoryItem(item))
            && FileManager.default.fileExists(atPath: item.sourceFilePath)
    }

    func openHistoryItem(_ id: UUID) {
        guard let index = historyItems.firstIndex(where: { $0.id == id }) else {
            return
        }

        selectedHistoryItemID = id
        let item = historyItems[index]

        guard item.state == .completed else {
            return
        }

        guard let transcriptPath = item.transcriptPath else {
            transcriptText = ""
            segments = []
            currentEditorSourcePath = item.sourceFilePath
            statusMessage = L10n.t("status.noTranscriptFile")
            return
        }

        let url = URL(fileURLWithPath: transcriptPath)
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            transcriptText = text
            segments = []
            lastModelID = item.modelID
            detectedLanguage = item.detectedLanguage ?? L10n.t("status.languageNotDetected")
            currentEditorSourcePath = item.sourceFilePath
            statusMessage = L10n.f("status.historyLoaded", item.displayName)
        } catch {
            statusMessage = L10n.f("status.fileMissing", item.displayName)
        }
    }

    func revealTranscriptInFinder(_ id: UUID) {
        guard let item = historyItems.first(where: { $0.id == id }), let transcriptPath = item.transcriptPath else {
            statusMessage = L10n.t("status.noTranscriptFile")
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: transcriptPath)])
    }

    func revealAudioInFinder(_ id: UUID) {
        guard let item = historyItems.first(where: { $0.id == id }), let audioPath = item.audioPath else {
            statusMessage = L10n.t("record.status.noAudioFile")
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: audioPath)])
    }

    func deleteHistoryItem(_ id: UUID) {
        guard let index = historyItems.firstIndex(where: { $0.id == id }) else {
            return
        }

        let item = historyItems[index]
        guard item.state != .processing else {
            statusMessage = L10n.t("status.historyDeleteBlocked")
            return
        }

        finalizePendingHistoryDeletion()

        let wasSelected = selectedHistoryItemID == id
        pendingHistoryDeletion = PendingHistoryDeletion(
            item: item,
            originalIndex: index,
            wasSelected: wasSelected
        )
        pendingHistoryDeletionName = item.displayName

        historyItems.remove(at: index)

        if wasSelected {
            selectedHistoryItemID = nil
            transcriptText = ""
            segments = []
            currentEditorSourcePath = nil
        }

        statusMessage = L10n.f("status.historyDeleted", item.displayName)
        persistHistoryToDisk()
        schedulePendingHistoryDeletionFinalization(for: item.id)
    }

    func undoHistoryDeletion() {
        guard let pending = pendingHistoryDeletion else {
            return
        }

        pendingHistoryDeletionTask?.cancel()
        pendingHistoryDeletionTask = nil
        pendingHistoryDeletion = nil
        pendingHistoryDeletionName = nil

        let insertionIndex = min(max(pending.originalIndex, 0), historyItems.count)
        historyItems.insert(pending.item, at: insertionIndex)
        sortHistoryByDateDesc()

        if pending.wasSelected {
            openHistoryItem(pending.item.id)
        }

        statusMessage = L10n.f("status.historyRestored", pending.item.displayName)
        persistHistoryToDisk()
    }

    func renameHistoryItem(_ id: UUID, to proposedName: String) {
        guard let index = historyItems.firstIndex(where: { $0.id == id }) else {
            return
        }

        let sourceFileName = historyItems[index].sourceFileName
        historyItems[index].customName = Self.normalizedHistoryCustomName(proposedName, sourceFileName: sourceFileName)
        persistHistoryToDisk()

        if historyItems[index].hasCustomName {
            statusMessage = L10n.f("status.historyRenamed", historyItems[index].displayName)
        } else {
            statusMessage = L10n.f("status.historyRenameReset", sourceFileName)
        }
    }

    func copyDebugInfo() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(debugReport(), forType: .string)
        statusMessage = L10n.t("status.debugCopied")
    }

    func revealRuntimeFolderInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([engine.runtimeSupportDirectoryURL()])
    }

    func copyAllText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(transcriptText, forType: .string)
        statusMessage = L10n.t("status.copied")
    }

    func saveAsText() {
        guard !transcriptText.isEmpty else {
            statusMessage = L10n.t("status.noTextToSave")
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "transcript.txt"
        panel.title = L10n.t("panel.saveTXTTitle")

        if panel.runModal() == .OK, let destination = panel.url {
            do {
                try transcriptText.write(to: destination, atomically: true, encoding: .utf8)
                statusMessage = L10n.f("status.txtSaved", destination.lastPathComponent)
            } catch {
                statusMessage = L10n.f("status.txtSaveError", error.localizedDescription)
            }
        }
    }

    func saveAsJSON() {
        guard !transcriptText.isEmpty else {
            statusMessage = L10n.t("status.noTextToSave")
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "transcript.json"
        panel.title = L10n.t("panel.saveJSONTitle")

        if panel.runModal() == .OK, let destination = panel.url {
            var payload: [String: Any] = [
                "generated_at": ISO8601DateFormatter().string(from: Date()),
                "text": transcriptText,
                "detected_language": detectedLanguage,
                "segments": segments.map { [
                    "start": $0.start,
                    "end": $0.end,
                    "text": $0.text,
                ] },
            ]

            if let currentEditorSourcePath {
                payload["source_file"] = currentEditorSourcePath
            }

            if let lastModelID {
                payload["model_id"] = lastModelID
            }

            if let currentModelReference {
                payload["model_path"] = currentModelReference.modelPath
            }

            do {
                let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: destination)
                statusMessage = L10n.f("status.jsonSaved", destination.lastPathComponent)
            } catch {
                statusMessage = L10n.f("status.jsonSaveError", error.localizedDescription)
            }
        }
    }

    func historyStateLabel(for state: TranscriptJobState) -> String {
        switch state {
        case .ready:
            return L10n.t("status.readyToQueue")
        case .queued:
            return L10n.t("status.queued")
        case .processing:
            return L10n.t("status.processing")
        case .completed:
            return L10n.t("status.completed")
        case .failed:
            return L10n.t("status.failed")
        }
    }

    func historyMetaText(for item: TranscriptHistoryItem) -> String {
        let datePart = historyDateFormatter.string(from: item.createdAt)
        let durationPart = formattedDuration(item.mediaDurationSeconds)
        if let recordingMode = item.recordingMode {
            return "\(datePart) • \(durationPart) • \(recordingModeShortTitle(recordingMode))"
        }
        return "\(datePart) • \(durationPart)"
    }

    func historyDisplayName(for item: TranscriptHistoryItem) -> String {
        item.displayName
    }

    func historyOriginalNameText(for item: TranscriptHistoryItem) -> String? {
        item.hasCustomName ? item.sourceFileName : nil
    }

    func filteredHistoryItems(matching query: String) async -> [TranscriptHistoryItem]? {
        let snapshot = historyItems
        let sources = snapshot.map { item in
            HistorySearchSource(
                id: item.id,
                metadata: [
                    item.displayName,
                    item.sourceFileName,
                    item.sourceFilePath,
                    item.audioPath ?? "",
                    item.transcriptPath ?? "",
                ].joined(separator: "\n"),
                transcriptPath: item.transcriptPath
            )
        }

        guard let matchingIDs = await historySearchIndex.matchingItemIDs(query: query, sources: sources) else {
            return nil
        }
        guard !Task.isCancelled else {
            return nil
        }
        return snapshot.filter { matchingIDs.contains($0.id) }
    }

    func historyBadgeText(for item: TranscriptHistoryItem) -> String? {
        if item.hasTranscript && item.hasAudio {
            return "t+a"
        }
        if item.hasTranscript {
            return "t"
        }
        if item.hasAudio {
            return "a"
        }
        return nil
    }

    func historyBadgeHelp(for item: TranscriptHistoryItem) -> String? {
        if item.hasTranscript && item.hasAudio {
            return L10n.t("help.badgeTranscriptAudio")
        }
        if item.hasTranscript {
            return L10n.t("help.badgeTranscript")
        }
        if item.hasAudio {
            return L10n.t("help.badgeAudio")
        }
        return nil
    }

    func etaText(for item: TranscriptHistoryItem) -> String {
        guard let etaSeconds = item.etaSeconds else {
            return ""
        }
        return L10n.f("status.eta", formattedClock(max(etaSeconds, 0)))
    }

    func canDeleteHistoryItem(_ item: TranscriptHistoryItem) -> Bool {
        item.state != .processing
    }

    private func ensureItemQueued(at index: Int) {
        historyItems[index].state = .queued
        if historyItems[index].queueOrder == nil {
            historyItems[index].queueOrder = nextQueueOrder()
        }
        historyItems[index].errorMessage = nil
        historyItems[index].progressFraction = nil
        historyItems[index].etaSeconds = nil
    }

    private func nextQueueOrder(excluding excludedID: UUID? = nil) -> Int {
        let currentMax = historyItems
            .filter { $0.id != excludedID }
            .compactMap(\.queueOrder)
            .max() ?? 0
        return currentMax + 1
    }

    private func nextQueuedItemIndex() -> Int? {
        let filterIDs = activeQueueFilterIDs
        let candidates = historyItems.indices.filter { index in
            historyItems[index].state == .queued
                && (filterIDs == nil || filterIDs?.contains(historyItems[index].id) == true)
        }

        return candidates.min { lhs, rhs in
            queueSortKey(for: historyItems[lhs]) < queueSortKey(for: historyItems[rhs])
        }
    }

    private func queuedItemIDsInOrder() -> [UUID] {
        historyItems
            .filter { $0.state == .queued || $0.state == .processing }
            .sorted { queueSortKey(for: $0) < queueSortKey(for: $1) }
            .map(\.id)
    }

    private func queuedOnlyItemIDsInOrder() -> [UUID] {
        historyItems
            .filter { $0.state == .queued }
            .sorted { queueSortKey(for: $0) < queueSortKey(for: $1) }
            .map(\.id)
    }

    private func moveQueuedHistoryItem(_ id: UUID, offset: Int) {
        let orderedIDs = queuedOnlyItemIDsInOrder()

        guard
            let currentPosition = orderedIDs.firstIndex(of: id),
            orderedIDs.indices.contains(currentPosition + offset),
            let currentIndex = historyItems.firstIndex(where: { $0.id == id }),
            let swapIndex = historyItems.firstIndex(where: { $0.id == orderedIDs[currentPosition + offset] })
        else {
            return
        }

        let currentOrder = historyItems[currentIndex].queueOrder
        historyItems[currentIndex].queueOrder = historyItems[swapIndex].queueOrder
        historyItems[swapIndex].queueOrder = currentOrder

        normalizeQueueOrders()
        sortHistoryByDateDesc()
        persistHistoryToDisk()
    }

    private func queueSortKey(for item: TranscriptHistoryItem) -> (Int, TimeInterval, String) {
        (
            item.queueOrder ?? Int.max,
            item.createdAt.timeIntervalSince1970,
            item.id.uuidString
        )
    }

    private func normalizeQueueOrders() {
        let orderedIDs = queuedItemIDsInOrder()
        for (position, id) in orderedIDs.enumerated() {
            guard let index = historyItems.firstIndex(where: { $0.id == id }) else {
                continue
            }
            historyItems[index].queueOrder = position + 1
        }
    }

    private func processNextQueuedItem() {
        if isQueueCancellationRequested {
            finishQueueCancellation()
            return
        }

        guard let index = nextQueuedItemIndex() else {
            finishQueueRun()
            return
        }

        let itemID = historyItems[index].id
        let sourceURL = URL(fileURLWithPath: historyItems[index].sourceFilePath)
        let languageCode = selectedLanguage
        let startedAt = Date()
        let transcriptsDirectoryURL = self.transcriptsDirectoryURL

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            historyItems[index].state = .failed
            historyItems[index].errorMessage = L10n.f("status.fileMissing", historyItems[index].displayName)
            persistHistoryToDisk()
            processNextQueuedItem()
            return
        }

        historyItems[index].state = .processing
        historyItems[index].progressFraction = nil
        historyItems[index].etaSeconds = nil
        historyItems[index].errorMessage = nil
        selectedHistoryItemID = itemID

        currentTranscribingFileName = historyItems[index].displayName
        statusMessage = L10n.f("status.transcribingFile", historyItems[index].displayName)
        activeProgressFraction = nil
        activeETA = ""

        let engine = self.engine
        let runHandle = TranscriptionRunHandle()
        activeTranscriptionRunHandle = runHandle

        DispatchQueue.global(qos: .userInitiated).async {
            var prepared: PreparedAudio?

            do {
                prepared = try MediaPreprocessor.prepareInput(from: sourceURL)

                if runHandle.isCancellationRequested {
                    throw TranscriptionCancellationError.cancelled
                }

                let result = try engine.transcribe(
                    inputAudioURL: prepared!.url,
                    languageCode: languageCode,
                    runHandle: runHandle
                ) { message in
                    DispatchQueue.main.async {
                        guard !self.isQueueCancellationRequested else {
                            return
                        }
                        self.statusMessage = message
                    }
                } onEvent: { event in
                    DispatchQueue.main.async {
                        guard !self.isQueueCancellationRequested else {
                            return
                        }
                        self.applyTranscriptionEvent(event, itemID: itemID, startedAt: startedAt)
                    }
                }

                if prepared?.shouldCleanup == true {
                    try? FileManager.default.removeItem(at: prepared!.url)
                }

                let completedAt = Date()
                let transcriptURL = Self.makeTranscriptFileURL(
                    for: sourceURL,
                    createdAt: completedAt,
                    in: transcriptsDirectoryURL
                )

                try FileManager.default.createDirectory(at: transcriptsDirectoryURL, withIntermediateDirectories: true)
                try result.text.write(to: transcriptURL, atomically: true, encoding: .utf8)

                DispatchQueue.main.async {
                    self.activeTranscriptionRunHandle = nil
                    self.finishTranscriptionSuccess(
                        itemID: itemID,
                        result: result,
                        transcriptURL: transcriptURL,
                        completedAt: completedAt
                    )
                    self.advanceQueueAfterCurrentItem()
                }
            } catch {
                if prepared?.shouldCleanup == true, let prepared {
                    try? FileManager.default.removeItem(at: prepared.url)
                }

                DispatchQueue.main.async {
                    self.activeTranscriptionRunHandle = nil
                    if self.isSkippingCurrentQueueItem {
                        self.restoreQueuedStateAfterSkip(itemID: itemID)
                        self.isSkippingCurrentQueueItem = false
                        self.advanceQueueAfterCurrentItem()
                        return
                    }
                    if error is TranscriptionCancellationError || self.isQueueCancellationRequested {
                        self.restoreQueuedStateAfterCancellation(itemID: itemID)
                        self.finishQueueCancellation()
                        return
                    }
                    self.finishTranscriptionFailure(itemID: itemID, error: error)
                    self.advanceQueueAfterCurrentItem()
                }
            }
        }
    }

    private func advanceQueueAfterCurrentItem() {
        if isQueueCancellationRequested {
            finishQueueCancellation()
            return
        }

        guard nextQueuedItemIndex() != nil else {
            finishQueueRun()
            return
        }

        if shouldPauseQueueAfterCurrent {
            pauseQueueRun()
            return
        }

        processNextQueuedItem()
    }

    private func finishQueueRun() {
        isTranscribing = false
        isQueuePaused = false
        isQueueCancellationRequested = false
        isSkippingCurrentQueueItem = false
        shouldPauseQueueAfterCurrent = false
        activeQueueFilterIDs = nil
        activeTranscriptionRunHandle = nil
        currentTranscribingFileName = ""
        activeProgressFraction = nil
        activeETA = ""
        statusMessage = L10n.t("status.queueCompleted")
    }

    private func finishQueueCancellation() {
        isTranscribing = false
        isQueuePaused = false
        isQueueCancellationRequested = false
        isSkippingCurrentQueueItem = false
        shouldPauseQueueAfterCurrent = false
        activeQueueFilterIDs = nil
        activeTranscriptionRunHandle = nil
        currentTranscribingFileName = ""
        activeProgressFraction = nil
        activeETA = ""
        statusMessage = L10n.t("status.queueCancelled")
        persistHistoryToDisk()
    }

    private func pauseQueueRun() {
        isTranscribing = false
        isQueuePaused = true
        isQueueCancellationRequested = false
        isSkippingCurrentQueueItem = false
        shouldPauseQueueAfterCurrent = false
        activeTranscriptionRunHandle = nil
        currentTranscribingFileName = ""
        activeProgressFraction = nil
        activeETA = ""
        statusMessage = L10n.t("status.queuePaused")
        persistHistoryToDisk()
    }

    private func finishTranscriptionSuccess(
        itemID: UUID,
        result: TranscriptionResult,
        transcriptURL: URL,
        completedAt: Date
    ) {
        guard let index = historyItems.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        historyItems[index].state = .completed
        historyItems[index].queueOrder = nil
        historyItems[index].createdAt = completedAt
        historyItems[index].transcriptPath = transcriptURL.path
        historyItems[index].detectedLanguage = result.detectedLanguage
        historyItems[index].modelID = result.modelID
        historyItems[index].errorMessage = nil
        historyItems[index].progressFraction = 1.0
        historyItems[index].etaSeconds = nil
        historyItems[index].isRuntimeOnly = false
        transcriptText = result.text
        segments = result.segments
        lastModelID = result.modelID
        detectedLanguage = result.detectedLanguage ?? L10n.t("status.languageNotDetected")
        currentEditorSourcePath = historyItems[index].sourceFilePath
        selectedHistoryItemID = itemID

        activeProgressFraction = nil
        activeETA = ""
        statusMessage = L10n.f("status.transcriptionCompletedFile", historyItems[index].displayName)

        sortHistoryByDateDesc()
        persistHistoryToDisk()
    }

    private func finishTranscriptionFailure(itemID: UUID, error: Error) {
        guard let index = historyItems.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        historyItems[index].state = .failed
        historyItems[index].queueOrder = nil
        historyItems[index].errorMessage = error.localizedDescription
        historyItems[index].progressFraction = nil
        historyItems[index].etaSeconds = nil
        historyItems[index].isRuntimeOnly = false

        activeProgressFraction = nil
        activeETA = ""
        statusMessage = error.localizedDescription

        sortHistoryByDateDesc()
        persistHistoryToDisk()
    }

    private func restoreQueuedStateAfterCancellation(itemID: UUID) {
        guard let index = historyItems.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        historyItems[index].state = .queued
        if historyItems[index].queueOrder == nil {
            historyItems[index].queueOrder = nextQueueOrder()
        }
        historyItems[index].errorMessage = nil
        historyItems[index].progressFraction = nil
        historyItems[index].etaSeconds = nil
    }

    private func restoreQueuedStateAfterSkip(itemID: UUID) {
        guard let index = historyItems.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        historyItems[index].state = .queued
        historyItems[index].queueOrder = nextQueueOrder(excluding: itemID)
        historyItems[index].errorMessage = nil
        historyItems[index].progressFraction = nil
        historyItems[index].etaSeconds = nil
        sortHistoryByDateDesc()
        statusMessage = L10n.f("status.queueSkippedCurrent", historyItems[index].displayName)
    }

    private func applyTranscriptionEvent(_ event: TranscriptionEvent, itemID: UUID, startedAt: Date) {
        guard let index = historyItems.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        switch event {
        case let .progress(processedSeconds, totalSeconds):
            if let totalSeconds, totalSeconds > 0 {
                let fraction = min(max(processedSeconds / totalSeconds, 0), 1)
                historyItems[index].progressFraction = fraction
                activeProgressFraction = fraction

                let elapsed = Date().timeIntervalSince(startedAt)
                if fraction > 0.02 {
                    let eta = max(elapsed * (1 - fraction) / fraction, 0)
                    historyItems[index].etaSeconds = eta
                    activeETA = formattedClock(eta)
                } else {
                    historyItems[index].etaSeconds = nil
                    activeETA = ""
                }

                statusMessage = L10n.f("status.transcriptionProgress", fraction * 100, historyItems[index].displayName)
            } else {
                historyItems[index].progressFraction = nil
                activeProgressFraction = nil
            }
        }
    }

    private func addMediaFiles(_ urls: [URL]) {
        let normalized = urls
            .map { $0.standardizedFileURL }
            .filter { $0.isFileURL }

        let supported = normalized.filter { Self.isSupportedMediaFile($0) }

        guard !supported.isEmpty else {
            statusMessage = L10n.t("status.unsupportedFiles")
            return
        }

        let now = Date()
        var largeMediaCount = 0

        for (offset, url) in supported.enumerated() {
            let durationSeconds = mediaDurationSeconds(for: url)
            if Self.isHeavyMediaFile(url, durationSeconds: durationSeconds) {
                largeMediaCount += 1
            }

            let item = TranscriptHistoryItem(
                sourceFileName: url.lastPathComponent,
                sourceFilePath: url.path,
                createdAt: now.addingTimeInterval(Double(offset) * 0.001),
                mediaDurationSeconds: durationSeconds,
                state: .queued,
                queueOrder: nextQueueOrder() + offset,
                isRuntimeOnly: true
            )
            historyItems.insert(item, at: 0)
            selectedHistoryItemID = item.id
        }

        if largeMediaCount > 0 {
            statusMessage = L10n.f("status.filesAddedLargeWarning", supported.count, largeMediaCount)
        } else {
            statusMessage = L10n.f("status.filesAdded", supported.count)
        }
        normalizeQueueOrders()
        sortHistoryByDateDesc()
    }

    private static func isSupportedMediaFile(_ url: URL) -> Bool {
        guard !url.pathExtension.isEmpty else {
            return false
        }

        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return false
        }

        return type.conforms(to: .audio) || type.conforms(to: .movie)
    }

    private func mediaDurationSeconds(for url: URL) -> Double? {
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(asset.duration)
        guard seconds.isFinite, seconds > 0 else {
            return nil
        }
        return seconds
    }

    private func formattedDuration(_ seconds: Double?) -> String {
        guard let seconds else {
            return L10n.t("status.unknownDuration")
        }

        return formattedClock(seconds)
    }

    private func formattedClock(_ value: Double) -> String {
        let total = Int(value.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    private static func isHeavyMediaFile(_ url: URL, durationSeconds: Double?) -> Bool {
        if let durationSeconds, durationSeconds >= longMediaDurationThresholdSeconds {
            return true
        }

        guard
            let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
            fileSize > 0
        else {
            return false
        }

        return Int64(fileSize) >= largeMediaSizeThresholdBytes
    }

    private var transcriptsDirectoryURL: URL {
        engine.defaultDownloadDirectory().appendingPathComponent("transcripts", isDirectory: true)
    }

    private var historyFileURL: URL {
        transcriptsDirectoryURL.appendingPathComponent("history.json")
    }

    nonisolated private static func makeTranscriptFileURL(for sourceURL: URL, createdAt: Date, in directoryURL: URL) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let timestamp = Int(createdAt.timeIntervalSince1970)
        let fileName = "\(sanitizeFileName(baseName))-\(timestamp).txt"
        return directoryURL.appendingPathComponent(fileName)
    }

    nonisolated private static func makeRecordingFileURL(
        createdAt: Date,
        mode: RecordingInputMode,
        in directoryURL: URL
    ) -> URL {
        let timestamp = Int(createdAt.timeIntervalSince1970)
        let modeToken: String
        switch mode {
        case .systemAndMicrophone:
            modeToken = "system-mic"
        case .microphoneOnly:
            modeToken = "mic"
        case .systemOnly:
            modeToken = "system"
        }
        let fileName = "recording-\(modeToken)-\(timestamp).m4a"
        return directoryURL.appendingPathComponent(fileName)
    }

    nonisolated private static func sanitizeFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "\\/:*?\"<>|")
        let components = name.components(separatedBy: invalid)
        let merged = components.joined(separator: "-")
        return merged.isEmpty ? "transcript" : merged
    }

    private func loadHistoryFromDisk() {
        guard let data = try? Data(contentsOf: historyFileURL) else {
            historyItems = []
            return
        }

        guard let decoded = try? JSONDecoder().decode([TranscriptHistoryItem].self, from: data) else {
            historyItems = []
            return
        }

        historyItems = decoded.map { item in
            var copy = item
            copy.progressFraction = nil
            copy.etaSeconds = nil
            copy.isRuntimeOnly = false
            if copy.state == .processing {
                if copy.audioPath != nil {
                    copy.state = .queued
                    copy.errorMessage = nil
                } else {
                    copy.state = .failed
                    copy.errorMessage = L10n.t("status.failed")
                }
            }
            if copy.state != .queued {
                copy.queueOrder = nil
            }
            return copy
        }

        normalizeQueueOrders()
        sortHistoryByDateDesc()
    }

    private func persistHistoryToDisk() {
        let persisted = historyItems.compactMap { item -> TranscriptHistoryItem? in
            let hasArtifact = item.transcriptPath != nil || item.audioPath != nil
            if !hasArtifact && item.state != .failed {
                return nil
            }

            if item.state == .completed && item.transcriptPath == nil && item.audioPath == nil {
                return nil
            }

            var copy = item
            if copy.state == .processing {
                copy.state = .queued
                copy.errorMessage = nil
            }
            if copy.state != .queued {
                copy.queueOrder = nil
            }
            copy.progressFraction = nil
            copy.etaSeconds = nil
            copy.isRuntimeOnly = false
            return copy
        }

        let directoryURL = transcriptsDirectoryURL
        let fileURL = historyFileURL

        historyPersistenceQueue.async {
            do {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                let data = try JSONEncoder().encode(persisted)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.statusMessage = error.localizedDescription
                }
            }
        }
    }

    private func sortHistoryByDateDesc() {
        historyItems.sort { lhs, rhs in
            let lhsIsActive = lhs.state == .queued || lhs.state == .processing
            let rhsIsActive = rhs.state == .queued || rhs.state == .processing

            if lhsIsActive != rhsIsActive {
                return lhsIsActive && !rhsIsActive
            }

            if lhsIsActive && rhsIsActive {
                return queueSortKey(for: lhs) < queueSortKey(for: rhs)
            }

            return lhs.createdAt > rhs.createdAt
        }
    }

    private static func normalizedHistoryCustomName(_ name: String, sourceFileName: String) -> String? {
        let normalized = name
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !normalized.isEmpty else {
            return nil
        }

        return normalized == sourceFileName ? nil : normalized
    }

    private func schedulePendingHistoryDeletionFinalization(for itemID: UUID) {
        pendingHistoryDeletionTask?.cancel()
        pendingHistoryDeletionTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 15_000_000_000)
            } catch {
                return
            }

            guard let self, self.pendingHistoryDeletion?.item.id == itemID else {
                return
            }
            self.finalizePendingHistoryDeletion()
        }
    }

    private func finalizePendingHistoryDeletion() {
        pendingHistoryDeletionTask?.cancel()
        pendingHistoryDeletionTask = nil

        guard let pending = pendingHistoryDeletion else {
            pendingHistoryDeletionName = nil
            return
        }

        pendingHistoryDeletion = nil
        pendingHistoryDeletionName = nil

        let paths = Set([pending.item.transcriptPath, pending.item.audioPath].compactMap { $0 })
        for path in paths where FileManager.default.fileExists(atPath: path) {
            var resultingURL: NSURL?
            try? FileManager.default.trashItem(
                at: URL(fileURLWithPath: path),
                resultingItemURL: &resultingURL
            )
        }
    }

    private static func normalizedBundleBuildLabel(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let digits = value.filter(\.isNumber)
        return digits.isEmpty ? nil : digits
    }

    private func addRecordingToHistory(_ result: AudioCaptureService.CaptureResult) {
        if let existing = historyItems.firstIndex(where: { $0.sourceFilePath == result.audioURL.path || $0.audioPath == result.audioURL.path }) {
            selectedHistoryItemID = historyItems[existing].id
            return
        }

        let item = TranscriptHistoryItem(
            sourceFileName: result.audioURL.lastPathComponent,
            sourceFilePath: result.audioURL.path,
            createdAt: Date(),
            mediaDurationSeconds: result.durationSeconds,
            audioPath: result.audioURL.path,
            recordingMode: result.mode,
            state: .queued,
            queueOrder: nextQueueOrder(),
            isRuntimeOnly: false
        )
        historyItems.insert(item, at: 0)
        selectedHistoryItemID = item.id
        sortHistoryByDateDesc()
        persistHistoryToDisk()
    }

    private func setupWorkspaceObservers() {
        guard workspaceObservers.isEmpty else {
            return
        }

        let notificationCenter = NSWorkspace.shared.notificationCenter
        let willSleep = notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSystemWillSleep()
            }
        }
        workspaceObservers = [willSleep]
    }

    private func handleSystemWillSleep() {
        guard shouldAutoPauseOnSleep, isRecording, !isRecordingPaused else {
            return
        }

        pauseRecording()
        statusMessage = L10n.t("record.status.pausedBySystem")
    }

    private func clearActiveRecordingSession() {
        activeRecordingSession = nil
        try? recordingSessionStore.clearActiveSession()
    }

    private func updateActiveRecordingSession(_ update: (inout ActiveRecordingSession) -> Void) {
        guard var session = activeRecordingSession else {
            return
        }
        update(&session)
        session.updatedAt = Date()
        activeRecordingSession = session
        try? recordingSessionStore.saveActiveSession(session)
    }

    @discardableResult
    private func recoverInterruptedRecordingIfNeeded() -> Bool {
        do {
            guard let recovered = try recordingSessionStore.recoverActiveSession(into: transcriptsDirectoryURL) else {
                activeRecordingSession = nil
                return false
            }

            addRecordingToHistory(
                AudioCaptureService.CaptureResult(
                    audioURL: recovered.audioURL,
                    durationSeconds: recovered.durationSeconds,
                    mode: recovered.mode
                )
            )
            activeRecordingSession = nil
            statusMessage = L10n.f("record.status.recovered", recovered.audioURL.lastPathComponent)
            return true
        } catch {
            statusMessage = L10n.f("record.status.recoverFailed", error.localizedDescription)
            return false
        }
    }

    private func startRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateRecordingElapsed()
            }
        }
        updateRecordingElapsed()
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    private func updateRecordingElapsed() {
        guard let recordingStartedAt else {
            recordingElapsedText = "00:00:00"
            return
        }

        var paused = recordingPausedTotalSeconds
        if isRecordingPaused, let recordingPausedAt {
            paused += max(Date().timeIntervalSince(recordingPausedAt), 0)
        }
        let elapsed = max(Date().timeIntervalSince(recordingStartedAt) - paused, 0)
        recordingElapsedText = formattedClock(elapsed)
    }

    private func startModelDownload(to destinationURL: URL) {
        guard !isDownloadingModel else { return }
        guard ensureRuntimeReady() else { return }

        let engine = self.engine

        isDownloadingModel = true
        downloadSourceText = L10n.f("status.source", WhisperEngine.modelSourceURLs.first ?? "-")
        downloadProgressText = L10n.f("status.downloadedOnly", byteFormatter.string(fromByteCount: 0))
        downloadProgressFraction = 0.0
        hasKnownDownloadTotal = false
        statusMessage = L10n.t("status.preparingEnvironment")

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let reference = try engine.downloadModel(
                    to: destinationURL,
                    status: { message in
                        DispatchQueue.main.async {
                            self.statusMessage = message
                        }
                    },
                    onEvent: { event in
                        DispatchQueue.main.async {
                            self.applyDownloadEvent(event)
                        }
                    }
                )

                DispatchQueue.main.async {
                    self.isDownloadingModel = false
                    self.currentModelReference = reference
                    self.lastModelID = reference.modelID
                    self.refreshModelStatus()
                    self.statusMessage = L10n.t("status.modelDownloadedReady")
                }
            } catch {
                DispatchQueue.main.async {
                    self.isDownloadingModel = false
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    private func applyDownloadEvent(_ event: ModelDownloadEvent) {
        switch event {
        case let .source(_, url):
            downloadSourceText = L10n.f("status.source", url)
            if let parsed = URL(string: url) {
                modelHubURL = parsed
            }
        case let .progress(downloadedBytes, totalBytes):
            let downloaded = byteFormatter.string(fromByteCount: downloadedBytes)

            if let totalBytes, totalBytes > 0 {
                let total = byteFormatter.string(fromByteCount: totalBytes)
                let fraction = min(max(Double(downloadedBytes) / Double(totalBytes), 0), 1)
                hasKnownDownloadTotal = true
                downloadProgressFraction = fraction
                downloadProgressText = L10n.f("status.downloadProgress", fraction * 100, downloaded, total)
            } else {
                hasKnownDownloadTotal = false
                downloadProgressFraction = 0
                downloadProgressText = L10n.f("status.downloadedOnly", downloaded)
            }
        case let .status(message):
            if !message.isEmpty {
                statusMessage = message
            }
        }
    }

    private func refreshModelStatus() {
        if let reference = engine.currentModelReference() {
            hasConnectedModel = true
            currentModelReference = reference
            lastModelID = reference.modelID
            modelStatus = L10n.f("status.localModel", reference.modelID)
            modelLocationText = reference.modelPath

            if let sourceRepo = reference.sourceRepo {
                let sourceURL = "https://huggingface.co/\(sourceRepo)"
                modelSourceText = sourceURL
                if let parsed = URL(string: sourceURL) {
                    modelHubURL = parsed
                }
            } else {
                modelSourceText = L10n.t("status.sourceLocalFolder")
                if let fallback = URL(string: WhisperEngine.modelSourceURLs.first ?? "https://huggingface.co") {
                    modelHubURL = fallback
                }
            }
        } else {
            hasConnectedModel = false
            currentModelReference = nil
            modelStatus = L10n.t("status.modelNotLoaded")
            modelLocationText = ""
            modelSourceText = ""
            if let fallback = URL(string: WhisperEngine.modelSourceURLs.first ?? "https://huggingface.co") {
                modelHubURL = fallback
            }
        }
    }

    private func refreshRuntimeIssue() {
        runtimeIssueMessage = engine.runtimeIssueDescription()
    }

    @discardableResult
    private func ensureRuntimeReady() -> Bool {
        refreshRuntimeIssue()

        if let runtimeIssueMessage {
            statusMessage = runtimeIssueMessage
            return false
        }

        return true
    }

    private func debugReport() -> String {
        let formatter = ISO8601DateFormatter()
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = info?["CFBundleVersion"] as? String ?? "unknown"

        var lines: [String] = []
        lines.append("timestamp: \(formatter.string(from: Date()))")
        lines.append("app_version: \(version)")
        lines.append("app_build: \(build)")
        lines.append("ui_language: \(AppLanguage.current.rawValue)")
        lines.append("status_message: \(statusMessage)")
        lines.append("runtime_issue: \(engine.runtimeIssueDescription() ?? "none")")
        lines.append("selected_language: \(selectedLanguage)")
        lines.append("detected_language: \(detectedLanguage)")
        lines.append("history_count: \(historyCount)")
        lines.append("queue_count: \(queueCount)")
        lines.append("is_transcribing: \(isTranscribing)")
        lines.append("is_recording: \(isRecording)")
        lines.append("selected_history_item: \(selectedHistoryItemID?.uuidString ?? "none")")

        if let failedItem = historyItems.first(where: { $0.state == .failed }) {
            lines.append("failed_item: \(failedItem.displayName)")
            lines.append("failed_error: \(failedItem.errorMessage ?? "none")")
        }

        lines.append(engine.debugReport())
        return lines.joined(separator: "\n")
    }
}
