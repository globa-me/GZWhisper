import AVFoundation
import AppKit
import Foundation
import UniformTypeIdentifiers

enum TranscriptJobState: String, Codable {
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
    var sourceFilePath: String
    var createdAt: Date
    var mediaDurationSeconds: Double?
    var transcriptPath: String?
    var detectedLanguage: String?
    var modelID: String?
    var state: TranscriptJobState
    var errorMessage: String?
    var progressFraction: Double? = nil
    var etaSeconds: Double? = nil
    var isRuntimeOnly = false

    init(
        id: UUID = UUID(),
        sourceFileName: String,
        sourceFilePath: String,
        createdAt: Date,
        mediaDurationSeconds: Double?,
        transcriptPath: String? = nil,
        detectedLanguage: String? = nil,
        modelID: String? = nil,
        state: TranscriptJobState,
        errorMessage: String? = nil,
        progressFraction: Double? = nil,
        etaSeconds: Double? = nil,
        isRuntimeOnly: Bool = false
    ) {
        self.id = id
        self.sourceFileName = sourceFileName
        self.sourceFilePath = sourceFilePath
        self.createdAt = createdAt
        self.mediaDurationSeconds = mediaDurationSeconds
        self.transcriptPath = transcriptPath
        self.detectedLanguage = detectedLanguage
        self.modelID = modelID
        self.state = state
        self.errorMessage = errorMessage
        self.progressFraction = progressFraction
        self.etaSeconds = etaSeconds
        self.isRuntimeOnly = isRuntimeOnly
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sourceFileName
        case sourceFilePath
        case createdAt
        case mediaDurationSeconds
        case transcriptPath
        case detectedLanguage
        case modelID
        case state
        case errorMessage
    }
}

@MainActor
final class AppViewModel: ObservableObject {
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

    let languageOptions = L10n.transcriptionLanguageOptions
    let appVersionLabel = "1.1"

    private let engine = WhisperEngine.shared
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

    var canStartQueue: Bool {
        !isDownloadingModel && !isTranscribing && hasConnectedModel && hasQueuedItems && runtimeIssueMessage == nil
    }

    var canDeleteModel: Bool {
        hasConnectedModel && !isDownloadingModel && !isTranscribing
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

    func initialize() {
        refreshModelStatus()
        refreshRuntimeIssue()
        loadHistoryFromDisk()

        if let runtimeIssueMessage {
            statusMessage = runtimeIssueMessage
        }
    }

    func chooseFiles() {
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

    func transcribeAllQueuedFiles() {
        guard ensureRuntimeReady() else { return }

        guard hasConnectedModel else {
            statusMessage = L10n.t("status.connectModelFirst")
            return
        }

        guard !isTranscribing else { return }

        guard hasQueuedItems else {
            statusMessage = L10n.t("status.queueEmpty")
            return
        }

        isTranscribing = true
        processNextQueuedItem()
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
            statusMessage = L10n.f("status.historyLoaded", item.sourceFileName)
        } catch {
            statusMessage = L10n.f("status.fileMissing", item.sourceFileName)
        }
    }

    func revealTranscriptInFinder(_ id: UUID) {
        guard let item = historyItems.first(where: { $0.id == id }), let transcriptPath = item.transcriptPath else {
            statusMessage = L10n.t("status.noTranscriptFile")
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: transcriptPath)])
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

        if let transcriptPath = item.transcriptPath {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: transcriptPath))
        }

        historyItems.remove(at: index)

        if selectedHistoryItemID == id {
            selectedHistoryItemID = nil
            transcriptText = ""
            segments = []
            currentEditorSourcePath = nil
        }

        statusMessage = L10n.f("status.historyDeleted", item.sourceFileName)
        persistHistoryToDisk()
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
        return "\(datePart) • \(durationPart)"
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

    private func processNextQueuedItem() {
        guard let index = historyItems.firstIndex(where: { $0.state == .queued }) else {
            finishQueueRun()
            return
        }

        let itemID = historyItems[index].id
        let sourceURL = URL(fileURLWithPath: historyItems[index].sourceFilePath)
        let languageCode = selectedLanguage
        let startedAt = Date()
        let transcriptsDirectoryURL = self.transcriptsDirectoryURL

        historyItems[index].state = .processing
        historyItems[index].progressFraction = nil
        historyItems[index].etaSeconds = nil
        historyItems[index].errorMessage = nil
        selectedHistoryItemID = itemID

        currentTranscribingFileName = historyItems[index].sourceFileName
        statusMessage = L10n.f("status.transcribingFile", historyItems[index].sourceFileName)
        activeProgressFraction = nil
        activeETA = ""

        let engine = self.engine

        DispatchQueue.global(qos: .userInitiated).async {
            var prepared: PreparedAudio?

            do {
                prepared = try MediaPreprocessor.prepareInput(from: sourceURL)

                let result = try engine.transcribe(
                    inputAudioURL: prepared!.url,
                    languageCode: languageCode
                ) { message in
                    DispatchQueue.main.async {
                        self.statusMessage = message
                    }
                } onEvent: { event in
                    DispatchQueue.main.async {
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
                    self.finishTranscriptionSuccess(
                        itemID: itemID,
                        result: result,
                        transcriptURL: transcriptURL,
                        completedAt: completedAt
                    )
                    self.processNextQueuedItem()
                }
            } catch {
                if prepared?.shouldCleanup == true, let prepared {
                    try? FileManager.default.removeItem(at: prepared.url)
                }

                DispatchQueue.main.async {
                    self.finishTranscriptionFailure(itemID: itemID, error: error)
                    self.processNextQueuedItem()
                }
            }
        }
    }

    private func finishQueueRun() {
        isTranscribing = false
        currentTranscribingFileName = ""
        activeProgressFraction = nil
        activeETA = ""
        statusMessage = L10n.t("status.queueCompleted")
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
        statusMessage = L10n.f("status.transcriptionCompletedFile", historyItems[index].sourceFileName)

        sortHistoryByDateDesc()
        persistHistoryToDisk()
    }

    private func finishTranscriptionFailure(itemID: UUID, error: Error) {
        guard let index = historyItems.firstIndex(where: { $0.id == itemID }) else {
            return
        }

        historyItems[index].state = .failed
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

                statusMessage = L10n.f("status.transcriptionProgress", fraction * 100, historyItems[index].sourceFileName)
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

        for (offset, url) in supported.enumerated() {
            let item = TranscriptHistoryItem(
                sourceFileName: url.lastPathComponent,
                sourceFilePath: url.path,
                createdAt: now.addingTimeInterval(Double(offset) * 0.001),
                mediaDurationSeconds: mediaDurationSeconds(for: url),
                state: .queued,
                isRuntimeOnly: true
            )
            historyItems.insert(item, at: 0)
            selectedHistoryItemID = item.id
        }

        statusMessage = L10n.f("status.filesAdded", supported.count)
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
            if !copy.state.isTerminal {
                copy.state = .failed
                copy.errorMessage = L10n.t("status.failed")
            }
            return copy
        }

        sortHistoryByDateDesc()
    }

    private func persistHistoryToDisk() {
        let persisted = historyItems.compactMap { item -> TranscriptHistoryItem? in
            guard item.state == .completed || item.state == .failed else {
                return nil
            }

            if item.state == .completed && item.transcriptPath == nil {
                return nil
            }

            var copy = item
            copy.progressFraction = nil
            copy.etaSeconds = nil
            copy.isRuntimeOnly = false
            return copy
        }

        do {
            try FileManager.default.createDirectory(at: transcriptsDirectoryURL, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(persisted)
            try data.write(to: historyFileURL, options: .atomic)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func sortHistoryByDateDesc() {
        historyItems.sort { $0.createdAt > $1.createdAt }
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
}
