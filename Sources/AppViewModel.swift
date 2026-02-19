import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
final class AppViewModel: ObservableObject {
    @Published var modelStatus = "Модель не загружена"
    @Published var modelLocationText = ""
    @Published var modelSourceText = ""
    @Published var statusMessage = "Готово к работе"
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

    let languageOptions: [(title: String, code: String)] = [
        ("Авто", "auto"),
        ("Русский", "ru"),
        ("English", "en"),
        ("Deutsch", "de"),
        ("Español", "es"),
    ]

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
        panel.prompt = "Выбрать"

        if panel.runModal() == .OK {
            selectedFileURL = panel.url
            statusMessage = "Файл выбран: \(panel.url?.lastPathComponent ?? "")"
        }
    }

    func downloadModelWithFolderPrompt() {
        guard !isDownloadingModel else { return }

        let defaultDirectory = engine.defaultDownloadDirectory()
        try? FileManager.default.createDirectory(at: defaultDirectory, withIntermediateDirectories: true)

        let panel = NSOpenPanel()
        panel.title = "Куда сохранить локальную модель"
        panel.message = "Выберите папку, где будут храниться файлы модели Whisper. По умолчанию: Documents/GZWhisper"
        panel.prompt = "Сохранить сюда"
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
        panel.title = "Указать локальную модель"
        panel.message = "Выберите папку с уже скачанной моделью faster-whisper."
        panel.prompt = "Подключить"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = engine.defaultDownloadDirectory()

        guard panel.runModal() == .OK, let modelURL = panel.url else {
            return
        }

        let engine = self.engine

        statusMessage = "Проверяю локальную модель..."

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try engine.connectLocalModel(at: modelURL) { message in
                    DispatchQueue.main.async {
                        self.statusMessage = message
                    }
                }

                DispatchQueue.main.async {
                    self.refreshModelStatus()
                    self.statusMessage = "Локальная модель подключена."
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
            statusMessage = "Папка модели не найдена."
            return
        }

        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func deleteModel() {
        guard canDeleteModel, let reference = currentModelReference else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Удалить модель?"

        if reference.sourceType == .downloaded {
            alert.informativeText = "Файлы модели будут удалены с диска. Это освободит место."
        } else {
            alert.informativeText = "Эта модель подключена по внешнему пути. Будет удалена только привязка в приложении, файлы на диске останутся."
        }

        alert.addButton(withTitle: "Удалить")
        alert.addButton(withTitle: "Отмена")

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        let engine = self.engine
        statusMessage = "Удаляю модель..."

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let outcome = try engine.deleteCurrentModel()

                DispatchQueue.main.async {
                    self.refreshModelStatus()
                    switch outcome {
                    case let .deletedFiles(path):
                        self.statusMessage = "Модель удалена: \(path)"
                    case let .unlinked(path):
                        self.statusMessage = "Привязка к модели удалена: \(path)"
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
            statusMessage = "Сначала выберите аудио или видео файл."
            return
        }

        guard hasConnectedModel else {
            statusMessage = "Сначала подключите локальную модель Whisper."
            return
        }

        guard !isTranscribing else { return }

        let engine = self.engine
        let selectedLanguage = self.selectedLanguage

        isTranscribing = true
        statusMessage = "Подготовка файла..."

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
                    self.detectedLanguage = result.detectedLanguage ?? "не определен"
                    self.transcriptText = result.text
                    self.statusMessage = "Транскрипция завершена."
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
        statusMessage = "Текст скопирован в буфер обмена."
    }

    func saveAsText() {
        guard !transcriptText.isEmpty else {
            statusMessage = "Нет текста для сохранения."
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "transcript.txt"
        panel.title = "Сохранить транскрипцию в TXT"

        if panel.runModal() == .OK, let destination = panel.url {
            do {
                try transcriptText.write(to: destination, atomically: true, encoding: .utf8)
                statusMessage = "TXT сохранен: \(destination.lastPathComponent)"
            } catch {
                statusMessage = "Ошибка сохранения TXT: \(error.localizedDescription)"
            }
        }
    }

    func saveAsJSON() {
        guard !transcriptText.isEmpty else {
            statusMessage = "Нет текста для сохранения."
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "transcript.json"
        panel.title = "Сохранить транскрипцию в JSON"

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
                statusMessage = "JSON сохранен: \(destination.lastPathComponent)"
            } catch {
                statusMessage = "Ошибка сохранения JSON: \(error.localizedDescription)"
            }
        }
    }

    private func startModelDownload(to destinationURL: URL) {
        guard !isDownloadingModel else { return }

        let engine = self.engine

        isDownloadingModel = true
        downloadSourceText = "Источник: \(WhisperEngine.modelSourceURLs.first ?? "-")"
        downloadProgressText = "0 MB"
        downloadProgressFraction = 0.0
        hasKnownDownloadTotal = false
        statusMessage = "Подготовка окружения..."

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
                    self.statusMessage = "Модель загружена и готова к работе."
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
            downloadSourceText = "Источник: \(url)"
        case let .progress(downloadedBytes, totalBytes):
            let downloaded = byteFormatter.string(fromByteCount: downloadedBytes)

            if let totalBytes, totalBytes > 0 {
                let total = byteFormatter.string(fromByteCount: totalBytes)
                let fraction = min(max(Double(downloadedBytes) / Double(totalBytes), 0), 1)
                hasKnownDownloadTotal = true
                downloadProgressFraction = fraction
                downloadProgressText = String(format: "%.1f%% • %@ из %@", fraction * 100, downloaded, total)
            } else {
                hasKnownDownloadTotal = false
                downloadProgressFraction = 0
                downloadProgressText = "Загружено: \(downloaded)"
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
            modelStatus = "Локальная модель: \(reference.modelID)"
            modelLocationText = reference.modelPath

            if let sourceRepo = reference.sourceRepo {
                modelSourceText = "Источник: https://huggingface.co/\(sourceRepo)"
            } else {
                modelSourceText = "Источник: пользовательская локальная папка"
            }
        } else {
            hasConnectedModel = false
            currentModelReference = nil
            modelStatus = "Модель не загружена"
            modelLocationText = ""
            modelSourceText = ""
        }
    }
}
