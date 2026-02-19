import Foundation

struct TranscriptionSegment: Codable {
    let start: Double
    let end: Double
    let text: String
}

struct TranscriptionResult {
    let modelID: String
    let detectedLanguage: String?
    let text: String
    let segments: [TranscriptionSegment]
}

struct LocalModelReference: Codable, Sendable {
    enum SourceType: String, Codable, Sendable {
        case downloaded
        case linked
    }

    let modelID: String
    let modelPath: String
    let sourceType: SourceType
    let sourceRepo: String?
    let configuredAt: String
}

enum ModelDownloadEvent: Sendable {
    case source(repoID: String, url: String)
    case progress(downloadedBytes: Int64, totalBytes: Int64?)
    case status(message: String)
}

enum ModelDeleteOutcome: Sendable {
    case deletedFiles(path: String)
    case unlinked(path: String)
}

enum WhisperEngineError: LocalizedError {
    case missingBundledWorker
    case missingVenvPython
    case commandFailed(message: String)
    case malformedResponse
    case modelMissing
    case invalidModelPath

    var errorDescription: String? {
        switch self {
        case .missingBundledWorker:
            return L10n.t("engine.missingWorker")
        case .missingVenvPython:
            return L10n.t("engine.missingVenvPython")
        case let .commandFailed(message):
            return message
        case .malformedResponse:
            return L10n.t("engine.malformedResponse")
        case .modelMissing:
            return L10n.t("engine.modelMissing")
        case .invalidModelPath:
            return L10n.t("engine.invalidModelPath")
        }
    }
}

final class WhisperEngine: @unchecked Sendable {
    static let shared = WhisperEngine()

    static let modelRepoCandidates = [
        "mobiuslabsgmbh/faster-whisper-large-v3-turbo",
        "SYSTRAN/faster-whisper-large-v3",
    ]

    static var modelSourceURLs: [String] {
        modelRepoCandidates.map { "https://huggingface.co/\($0)" }
    }

    private let fileManager = FileManager.default

    private let supportDirectory: URL
    private let venvDirectory: URL
    private let workerScriptURL: URL
    private let modelReferenceURL: URL

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        supportDirectory = appSupport.appendingPathComponent("GZWhisper", isDirectory: true)
        venvDirectory = supportDirectory.appendingPathComponent("venv", isDirectory: true)
        workerScriptURL = supportDirectory.appendingPathComponent("transcription_worker.py")
        modelReferenceURL = supportDirectory.appendingPathComponent("selected_model.json")
    }

    func defaultDownloadDirectory() -> URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("GZWhisper", isDirectory: true)
    }

    func hasUsableModel() -> Bool {
        currentModelReference() != nil
    }

    func currentModelReference() -> LocalModelReference? {
        guard
            let data = try? Data(contentsOf: modelReferenceURL),
            let reference = try? JSONDecoder().decode(LocalModelReference.self, from: data)
        else {
            return nil
        }

        guard fileManager.fileExists(atPath: reference.modelPath) else {
            return nil
        }

        return reference
    }

    func prepareEnvironment(status: (String) -> Void) throws {
        try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try syncWorkerScript()
        try ensureVirtualEnvironment(status: status)
        try ensureDependencies(status: status)
    }

    func downloadModel(
        to destinationDirectory: URL,
        status: (String) -> Void,
        onEvent: @escaping (ModelDownloadEvent) -> Void
    ) throws -> LocalModelReference {
        try prepareEnvironment(status: status)
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        status(L10n.t("engine.downloadingModel"))

        var arguments = [
            workerScriptURL.path,
            "download",
            "--output-dir", destinationDirectory.path,
        ]

        for repo in Self.modelRepoCandidates {
            arguments.append(contentsOf: ["--repo-id", repo])
        }

        var finalPayload: [String: Any]?

        let result = try runPythonStreaming(arguments: arguments) { line in
            guard let json = self.parseJSONLine(line) else { return }

            if let event = json["event"] as? String {
                switch event {
                case "source":
                    let repoID = json["repo_id"] as? String ?? "unknown"
                    let url = json["url"] as? String ?? ""
                    onEvent(.source(repoID: repoID, url: url))
                case "progress":
                    let downloaded = (json["downloaded_bytes"] as? NSNumber)?.int64Value ?? 0
                    let totalNumber = json["total_bytes"] as? NSNumber
                    onEvent(.progress(downloadedBytes: downloaded, totalBytes: totalNumber?.int64Value))
                case "status":
                    let message = json["message"] as? String ?? ""
                    onEvent(.status(message: message))
                default:
                    break
                }
                return
            }

            if json["ok"] != nil {
                finalPayload = json
            }
        }

        if result.exitCode != 0 || finalPayload?["ok"] as? Bool != true {
            let details = finalPayload?["details"] as? String
            let message = finalPayload?["error"] as? String ?? result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw WhisperEngineError.commandFailed(message: details.map { "\(message)\n\($0)" } ?? message)
        }

        guard
            let finalPayload,
            let modelID = finalPayload["model_id"] as? String,
            let modelPath = finalPayload["model_path"] as? String
        else {
            throw WhisperEngineError.malformedResponse
        }

        let reference = LocalModelReference(
            modelID: modelID,
            modelPath: modelPath,
            sourceType: .downloaded,
            sourceRepo: finalPayload["repo_id"] as? String,
            configuredAt: ISO8601DateFormatter().string(from: Date())
        )

        try saveModelReference(reference)
        return reference
    }

    func connectLocalModel(at modelPath: URL, status: (String) -> Void) throws -> LocalModelReference {
        try prepareEnvironment(status: status)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: modelPath.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw WhisperEngineError.invalidModelPath
        }

        status(L10n.t("engine.validatingModel"))

        let result = try runPython(arguments: [
            workerScriptURL.path,
            "validate-model",
            "--model-path", modelPath.path,
        ])

        let payload = parsePayload(stdout: result.stdout)

        if result.exitCode != 0 || payload?["ok"] as? Bool != true {
            let details = payload?["details"] as? String
            let message = payload?["error"] as? String ?? result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw WhisperEngineError.commandFailed(message: details.map { "\(message)\n\($0)" } ?? message)
        }

        let modelID = payload?["model_id"] as? String ?? modelPath.lastPathComponent

        let reference = LocalModelReference(
            modelID: modelID,
            modelPath: modelPath.path,
            sourceType: .linked,
            sourceRepo: nil,
            configuredAt: ISO8601DateFormatter().string(from: Date())
        )

        try saveModelReference(reference)
        return reference
    }

    func deleteCurrentModel() throws -> ModelDeleteOutcome {
        guard let reference = loadSavedModelReference() else {
            throw WhisperEngineError.modelMissing
        }

        switch reference.sourceType {
        case .downloaded:
            if fileManager.fileExists(atPath: reference.modelPath) {
                try fileManager.removeItem(atPath: reference.modelPath)
            }
            try clearModelReference()
            return .deletedFiles(path: reference.modelPath)
        case .linked:
            try clearModelReference()
            return .unlinked(path: reference.modelPath)
        }
    }

    func transcribe(inputAudioURL: URL, languageCode: String?, status: (String) -> Void) throws -> TranscriptionResult {
        try prepareEnvironment(status: status)

        guard let reference = currentModelReference() else {
            throw WhisperEngineError.modelMissing
        }

        status(L10n.t("engine.transcribing"))

        var arguments = [
            workerScriptURL.path,
            "transcribe",
            "--model-path", reference.modelPath,
            "--model-id", reference.modelID,
            "--input", inputAudioURL.path,
        ]

        if let languageCode, !languageCode.isEmpty, languageCode != "auto" {
            arguments.append(contentsOf: ["--language", languageCode])
        }

        let result = try runPython(arguments: arguments)
        let payload = parsePayload(stdout: result.stdout)

        if result.exitCode != 0 || payload?["ok"] as? Bool != true {
            let details = payload?["details"] as? String
            let message = payload?["error"] as? String ?? result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw WhisperEngineError.commandFailed(message: details.map { "\(message)\n\($0)" } ?? message)
        }

        guard let payload else {
            throw WhisperEngineError.malformedResponse
        }

        let modelID = payload["model_id"] as? String ?? reference.modelID
        let language = payload["language"] as? String
        let text = payload["text"] as? String ?? ""

        let segments: [TranscriptionSegment]
        if let rawSegments = payload["segments"] as? [[String: Any]] {
            segments = rawSegments.compactMap { raw in
                guard
                    let start = raw["start"] as? Double,
                    let end = raw["end"] as? Double,
                    let value = raw["text"] as? String
                else {
                    return nil
                }
                return TranscriptionSegment(start: start, end: end, text: value)
            }
        } else {
            segments = []
        }

        return TranscriptionResult(modelID: modelID, detectedLanguage: language, text: text, segments: segments)
    }

    private func syncWorkerScript() throws {
        guard let bundledWorker = Bundle.main.url(forResource: "transcription_worker", withExtension: "py") else {
            throw WhisperEngineError.missingBundledWorker
        }

        let bundledData = try Data(contentsOf: bundledWorker)
        let shouldCopy: Bool

        if let currentData = try? Data(contentsOf: workerScriptURL) {
            shouldCopy = currentData != bundledData
        } else {
            shouldCopy = true
        }

        if shouldCopy {
            if fileManager.fileExists(atPath: workerScriptURL.path) {
                try fileManager.removeItem(at: workerScriptURL)
            }
            try fileManager.copyItem(at: bundledWorker, to: workerScriptURL)
        }
    }

    private func ensureVirtualEnvironment(status: (String) -> Void) throws {
        guard !fileManager.fileExists(atPath: venvPythonURL.path) else {
            return
        }

        status(L10n.t("engine.creatingVenv"))
        let result = try ProcessRunner.run(
            executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
            arguments: ["-m", "venv", venvDirectory.path]
        )

        guard result.exitCode == 0 else {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw WhisperEngineError.commandFailed(message: L10n.f("engine.creatingVenvFailed", message))
        }
    }

    private func ensureDependencies(status: (String) -> Void) throws {
        let pythonURL = try resolvedVenvPythonURL()

        let checkResult = try ProcessRunner.run(
            executableURL: pythonURL,
            arguments: ["-c", "import faster_whisper, huggingface_hub"]
        )

        guard checkResult.exitCode != 0 else {
            return
        }

        status(L10n.t("engine.installingDeps"))

        _ = try ProcessRunner.run(
            executableURL: pythonURL,
            arguments: ["-m", "pip", "install", "--upgrade", "pip"]
        )

        let installResult = try ProcessRunner.run(
            executableURL: pythonURL,
            arguments: ["-m", "pip", "install", "--upgrade", "faster-whisper", "huggingface_hub"]
        )

        guard installResult.exitCode == 0 else {
            let stderr = installResult.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw WhisperEngineError.commandFailed(message: L10n.f("engine.installDepsFailed", stderr))
        }
    }

    private func runPython(arguments: [String]) throws -> ProcessResult {
        try ProcessRunner.run(
            executableURL: resolvedVenvPythonURL(),
            arguments: arguments,
            environment: [
                "PYTHONUNBUFFERED": "1",
                "GZWHISPER_UI_LANG": AppLanguage.current.workerCode,
            ],
            currentDirectoryURL: supportDirectory
        )
    }

    private func runPythonStreaming(arguments: [String], onLine: @escaping (String) -> Void) throws -> ProcessResult {
        try ProcessRunner.runStreaming(
            executableURL: resolvedVenvPythonURL(),
            arguments: arguments,
            environment: [
                "PYTHONUNBUFFERED": "1",
                "GZWHISPER_UI_LANG": AppLanguage.current.workerCode,
            ],
            currentDirectoryURL: supportDirectory,
            onStdoutLine: onLine,
            onStderrLine: nil
        )
    }

    private func resolvedVenvPythonURL() throws -> URL {
        if fileManager.fileExists(atPath: venvPythonURL.path) {
            return venvPythonURL
        }

        let alternate = venvDirectory.appendingPathComponent("bin/python")
        if fileManager.fileExists(atPath: alternate.path) {
            return alternate
        }

        throw WhisperEngineError.missingVenvPython
    }

    private var venvPythonURL: URL {
        venvDirectory.appendingPathComponent("bin/python3")
    }

    private func parsePayload(stdout: String) -> [String: Any]? {
        let lines = stdout
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .reversed()

        for line in lines {
            if let json = parseJSONLine(line) {
                return json
            }
        }

        return nil
    }

    private func parseJSONLine(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else {
            return nil
        }

        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func loadSavedModelReference() -> LocalModelReference? {
        guard
            let data = try? Data(contentsOf: modelReferenceURL),
            let reference = try? JSONDecoder().decode(LocalModelReference.self, from: data)
        else {
            return nil
        }

        return reference
    }

    private func saveModelReference(_ reference: LocalModelReference) throws {
        try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(reference)
        try data.write(to: modelReferenceURL, options: .atomic)
    }

    private func clearModelReference() throws {
        if fileManager.fileExists(atPath: modelReferenceURL.path) {
            try fileManager.removeItem(at: modelReferenceURL)
        }
    }
}
