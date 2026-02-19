import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppViewModel: ObservableObject {
    @Published var modelStatus = L10n.t("status.modelNotLoaded")
    @Published var modelLocationText = ""
    @Published var modelSourceText = ""
    @Published var statusMessage = L10n.t("status.ready")
    @Published var selectedFileURL: URL?
    @Published var transcriptText = ""
    @Published var selectedLanguage = "auto"
    @Published var detectedLanguage = "-"
    @Published var isDownloadingModel = false
    @Published var isTranscribing = false
    @Published var downloadSourceText = ""
    @Published var downloadProgressText = ""
    @Published var downloadProgressFraction = 0.0
    @Published var hasKnownDownloadTotal = false
    @Published private(set) var hasConnectedModel = false

    let languageOptions = L10n.transcriptionLanguageOptions

    let downloadSourcesHint = WhisperEngine.modelSourceURLs.joined(separator: "  |  ")

    private let engine = WhisperEngine.shared
    private let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.includesCount = true
        return formatter
    }()

    private var segments: [TranscriptionSegment] = []
    private var lastModelID: String?
    private var currentModelReference: LocalModelReference?

    var canTranscribe: Bool {
        selectedFileURL != nil && !isDownloadingModel && !isTranscribing && hasConnectedModel
    }

    var shouldShowModelSelectionButtons: Bool {
        !hasConnectedModel
    }

    var canDeleteModel: Bool {
        hasConnectedModel && !isDownloadingModel && !isTranscribing
    }

    var shouldShowDownloadProgress: Bool {
        isDownloadingModel
    }

    func initialize() {
        refreshModelStatus()
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio, .movie]
        panel.prompt = L10n.t("panel.choosePrompt")

        if panel.runModal() == .OK {
            selectedFileURL = panel.url
            statusMessage = L10n.f("status.fileSelected", panel.url?.lastPathComponent ?? "")
        }
    }

    func downloadModelWithFolderPrompt() {
        guard !isDownloadingModel else { return }

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

    func transcribeSelectedFile() {
        guard let selectedFileURL else {
            statusMessage = L10n.t("status.pickFileFirst")
            return
        }

        guard hasConnectedModel else {
            statusMessage = L10n.t("status.connectModelFirst")
            return
        }

        guard !isTranscribing else { return }

        let engine = self.engine
        let selectedLanguage = self.selectedLanguage

        isTranscribing = true
        statusMessage = L10n.t("status.preparingFile")

        DispatchQueue.global(qos: .userInitiated).async {
            var prepared: PreparedAudio?

            do {
                prepared = try MediaPreprocessor.prepareInput(from: selectedFileURL)

                let result = try engine.transcribe(
                    inputAudioURL: prepared!.url,
                    languageCode: selectedLanguage
                ) { message in
                    DispatchQueue.main.async {
                        self.statusMessage = message
                    }
                }

                if prepared?.shouldCleanup == true {
                    try? FileManager.default.removeItem(at: prepared!.url)
                }

                DispatchQueue.main.async {
                    self.isTranscribing = false
                    self.segments = result.segments
                    self.lastModelID = result.modelID
                    self.detectedLanguage = result.detectedLanguage ?? L10n.t("status.languageNotDetected")
                    self.transcriptText = result.text
                    self.statusMessage = L10n.t("status.transcriptionCompleted")
                    self.refreshModelStatus()
                }
            } catch {
                if prepared?.shouldCleanup == true, let prepared {
                    try? FileManager.default.removeItem(at: prepared.url)
                }

                DispatchQueue.main.async {
                    self.isTranscribing = false
                    self.statusMessage = error.localizedDescription
                }
            }
        }
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

            if let selectedFileURL {
                payload["source_file"] = selectedFileURL.path
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

    private func startModelDownload(to destinationURL: URL) {
        guard !isDownloadingModel else { return }

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
                modelSourceText = L10n.f("status.source", "https://huggingface.co/\(sourceRepo)")
            } else {
                modelSourceText = L10n.t("status.sourceLocalFolder")
            }
        } else {
            hasConnectedModel = false
            currentModelReference = nil
            modelStatus = L10n.t("status.modelNotLoaded")
            modelLocationText = ""
            modelSourceText = ""
        }
    }
}
