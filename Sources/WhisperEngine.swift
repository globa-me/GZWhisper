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
    let ownershipToken: String?

    init(
        modelID: String,
        modelPath: String,
        sourceType: SourceType,
        sourceRepo: String?,
        configuredAt: String,
        ownershipToken: String? = nil
    ) {
        self.modelID = modelID
        self.modelPath = modelPath
        self.sourceType = sourceType
        self.sourceRepo = sourceRepo
        self.configuredAt = configuredAt
        self.ownershipToken = ownershipToken
    }
}

enum MacProcessorFamily: Sendable {
    case appleSilicon
    case intel

    static var current: MacProcessorFamily {
        var info = utsname()
        uname(&info)
        let machine = withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return machine == "arm64" ? .appleSilicon : .intel
    }
}

struct WhisperModelOption: Identifiable, Sendable {
    enum Recommendation: Sendable {
        case best
        case recommended
        case supported
        case demanding
    }

    let id: String
    let displayName: String
    let approximateDownloadGB: Double
    let minimumRAMGB: Int
    let recommendedRAMGB: Int
    let appleSiliconRecommendation: Recommendation
    let intelRecommendation: Recommendation
    let qualityRank: Int
    let speedRank: Int

    var repositoryID: String { id }

    func matches(modelID: String) -> Bool {
        if repositoryID == "dropbox-dash/faster-whisper-large-v3-turbo" {
            return [repositoryID, "mobiuslabsgmbh/faster-whisper-large-v3-turbo"].contains {
                $0.caseInsensitiveCompare(modelID) == .orderedSame
            }
        }
        return repositoryID.caseInsensitiveCompare(modelID) == .orderedSame
    }

    var currentRecommendation: Recommendation {
        let ramGB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
        if MacProcessorFamily.current == .appleSilicon {
            if ramGB < 12 {
                if displayName == "Whisper Small" { return .best }
                if displayName == "Whisper Base" { return .recommended }
                if displayName.contains("Large") { return .demanding }
            }
            return appleSiliconRecommendation
        }

        if ramGB < 12 {
            if displayName == "Whisper Base" { return .best }
            if displayName == "Whisper Small" { return .recommended }
        } else {
            if displayName == "Whisper Small" { return .best }
            if displayName == "Whisper Base" { return .recommended }
        }
        return intelRecommendation
    }
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

enum TranscriptionEvent: Sendable {
    case progress(processedSeconds: Double, totalSeconds: Double?)
}

enum WhisperEngineError: LocalizedError {
    case missingBundledWorker
    case missingBootstrapPython
    case missingVenvPython
    case commandFailed(message: String)
    case malformedResponse
    case modelMissing
    case invalidModelPath

    var errorDescription: String? {
        switch self {
        case .missingBundledWorker:
            return L10n.t("engine.missingWorker")
        case .missingBootstrapPython:
            return L10n.t("engine.missingBootstrapPython")
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

enum TranscriptionCancellationError: LocalizedError {
    case cancelled

    var errorDescription: String? {
        L10n.t("status.queueCancelled")
    }
}

final class TranscriptionRunHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancellationRequested = false

    var isCancellationRequested: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancellationRequested
    }

    func attach(_ process: Process) {
        var shouldTerminate = false

        lock.lock()
        self.process = process
        shouldTerminate = cancellationRequested
        lock.unlock()

        if shouldTerminate {
            process.terminate()
        }
    }

    func cancel() {
        let process: Process?

        lock.lock()
        cancellationRequested = true
        process = self.process
        lock.unlock()

        process?.terminate()
    }

    func clear() {
        lock.lock()
        process = nil
        lock.unlock()
    }
}

final class WhisperEngine: @unchecked Sendable {
    static let shared = WhisperEngine()

    static let modelCatalog: [WhisperModelOption] = [
        WhisperModelOption(
            id: "Systran/faster-whisper-tiny", displayName: "Whisper Tiny", approximateDownloadGB: 0.08,
            minimumRAMGB: 8, recommendedRAMGB: 8, appleSiliconRecommendation: .supported, intelRecommendation: .supported,
            qualityRank: 1, speedRank: 5
        ),
        WhisperModelOption(
            id: "Systran/faster-whisper-base", displayName: "Whisper Base", approximateDownloadGB: 0.15,
            minimumRAMGB: 8, recommendedRAMGB: 8, appleSiliconRecommendation: .supported, intelRecommendation: .recommended,
            qualityRank: 2, speedRank: 4
        ),
        WhisperModelOption(
            id: "Systran/faster-whisper-small", displayName: "Whisper Small", approximateDownloadGB: 0.49,
            minimumRAMGB: 8, recommendedRAMGB: 16, appleSiliconRecommendation: .recommended, intelRecommendation: .best,
            qualityRank: 3, speedRank: 3
        ),
        WhisperModelOption(
            id: "dropbox-dash/faster-whisper-large-v3-turbo", displayName: "Whisper Large v3 Turbo", approximateDownloadGB: 1.6,
            minimumRAMGB: 8, recommendedRAMGB: 16, appleSiliconRecommendation: .best, intelRecommendation: .demanding,
            qualityRank: 4, speedRank: 3
        ),
        WhisperModelOption(
            id: "Systran/faster-whisper-large-v3", displayName: "Whisper Large v3", approximateDownloadGB: 3.1,
            minimumRAMGB: 16, recommendedRAMGB: 24, appleSiliconRecommendation: .demanding, intelRecommendation: .demanding,
            qualityRank: 5, speedRank: 1
        ),
    ]

    static let modelRepoCandidates = modelCatalog.map(\.repositoryID)

    static var modelSourceURLs: [String] {
        modelRepoCandidates.map { "https://huggingface.co/\($0)" }
    }

    private let fileManager = FileManager.default

    private let supportDirectory: URL
    private let venvDirectory: URL
    private let workerScriptURL: URL
    private let modelReferenceURL: URL
    private let modelRegistryURL: URL
    private let workerLogsDirectory: URL
    private static let managedModelMarkerName = ".gzwhisper-model.json"

    private struct ManagedModelMarker: Codable {
        let modelID: String
        let ownershipToken: String
    }

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        supportDirectory = appSupport.appendingPathComponent("GZWhisper", isDirectory: true)
        venvDirectory = supportDirectory.appendingPathComponent("venv", isDirectory: true)
        workerScriptURL = supportDirectory.appendingPathComponent("transcription_worker.py")
        modelReferenceURL = supportDirectory.appendingPathComponent("selected_model.json")
        modelRegistryURL = supportDirectory.appendingPathComponent("installed_models.json")
        workerLogsDirectory = supportDirectory.appendingPathComponent("Worker Logs", isDirectory: true)
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

    func installedModelReferences() -> [LocalModelReference] {
        var references = loadModelRegistry()
        if let current = currentModelReference(), !references.contains(where: { $0.modelPath == current.modelPath }) {
            references.append(current)
            try? saveModelRegistry(references)
        }
        let available = references.filter { fileManager.fileExists(atPath: $0.modelPath) }
        if available.count != references.count {
            try? saveModelRegistry(available)
        }
        return available
    }

    func selectModel(_ reference: LocalModelReference) throws {
        guard fileManager.fileExists(atPath: reference.modelPath) else {
            throw WhisperEngineError.modelMissing
        }
        try activateAndRegisterModel(reference)
    }

    func prepareEnvironment(status: (String) -> Void) throws {
        try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try syncWorkerScript()
        try ensureVirtualEnvironment(status: status)
        try ensureDependencies(status: status)
    }

    func runtimeIssueDescription() -> String? {
        do {
            _ = try resolvedBootstrapPythonURL()
            return nil
        } catch {
            if let localized = error as? LocalizedError, let description = localized.errorDescription {
                return description
            }
            return error.localizedDescription
        }
    }

    func runtimeSupportDirectoryURL() -> URL {
        supportDirectory
    }

    func debugReport() -> String {
        var lines: [String] = []
        lines.append("bundle_path: \(Bundle.main.bundleURL.path)")
        lines.append("processor_family: \(MacProcessorFamily.current == .appleSilicon ? "apple_silicon" : "intel")")
        lines.append("processor_count: \(ProcessInfo.processInfo.processorCount)")
        lines.append("active_processor_count: \(ProcessInfo.processInfo.activeProcessorCount)")
        lines.append("physical_memory_bytes: \(ProcessInfo.processInfo.physicalMemory)")
        lines.append("support_directory: \(supportDirectory.path)")
        lines.append("worker_script: \(workerScriptURL.path)")
        lines.append("worker_logs_directory: \(workerLogsDirectory.path)")
        lines.append("model_reference: \(modelReferenceURL.path)")

        if let reference = currentModelReference() {
            lines.append("model_id: \(reference.modelID)")
            lines.append("model_path: \(reference.modelPath)")
            lines.append("model_source_type: \(reference.sourceType.rawValue)")
            lines.append("model_source_repo: \(reference.sourceRepo ?? "none")")
        } else {
            lines.append("model_id: none")
        }

        if let runtimeIssue = runtimeIssueDescription() {
            lines.append("runtime_issue: \(runtimeIssue)")
        } else {
            lines.append("runtime_issue: none")
        }

        if let bootstrapPythonURL = try? resolvedBootstrapPythonURL() {
            lines.append("bootstrap_python: \(bootstrapPythonURL.path)")
        } else {
            lines.append("bootstrap_python: missing")
        }

        lines.append("venv_directory: \(venvDirectory.path)")
        lines.append("venv_python_expected: \(venvPythonURL.path)")

        if let currentVenvPythonURL = existingVenvPythonURL() {
            lines.append("venv_python_current: \(currentVenvPythonURL.path)")
            lines.append("venv_python_executable: \(fileManager.isExecutableFile(atPath: currentVenvPythonURL.path))")

            if let symlinkTarget = symbolicLinkDestination(for: currentVenvPythonURL) {
                lines.append("venv_python_target: \(symlinkTarget.path)")
            }
        } else {
            lines.append("venv_python_current: missing")
            if let symlinkTarget = symbolicLinkDestination(for: venvPythonURL) {
                lines.append("venv_python_target: \(symlinkTarget.path)")
            }
        }

        let config = venvConfiguration()
        if let home = config["home"] {
            lines.append("venv_home: \(home)")
        }
        if let executable = config["executable"] {
            lines.append("venv_executable: \(executable)")
        }

        let recentLogs = recentWorkerLogURLs(limit: 2)
        lines.append("recent_worker_log_count: \(recentLogs.count)")
        for logURL in recentLogs {
            lines.append("--- worker_log: \(logURL.lastPathComponent) ---")
            if let contents = try? String(contentsOf: logURL, encoding: .utf8) {
                lines.append(contents.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                lines.append("unreadable")
            }
            lines.append("--- end_worker_log ---")
        }

        return lines.joined(separator: "\n")
    }

    func downloadModel(
        option: WhisperModelOption,
        to destinationDirectory: URL,
        status: (String) -> Void,
        onEvent: @escaping (ModelDownloadEvent) -> Void
    ) throws -> LocalModelReference {
        try prepareEnvironment(status: status)
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let expectedModelDirectory = destinationDirectory.appendingPathComponent(
            option.repositoryID.replacingOccurrences(of: "/", with: "--"),
            isDirectory: true
        )
        let ownershipToken = try prepareManagedModelMarker(
            modelID: option.repositoryID,
            modelDirectory: expectedModelDirectory
        )

        status(L10n.f("engine.downloadingNamedModel", option.displayName))

        var arguments = [
            workerScriptURL.path,
            "download",
            "--output-dir", destinationDirectory.path,
        ]

        arguments.append(contentsOf: ["--repo-id", option.repositoryID])

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

        let downloadedURL = URL(fileURLWithPath: modelPath).standardizedFileURL
        let ownsDownloadedDirectory = downloadedURL == expectedModelDirectory.standardizedFileURL
            ? ownershipToken
            : nil
        let reference = LocalModelReference(
            modelID: modelID,
            modelPath: modelPath,
            sourceType: ownsDownloadedDirectory == nil ? .linked : .downloaded,
            sourceRepo: finalPayload["repo_id"] as? String,
            configuredAt: ISO8601DateFormatter().string(from: Date()),
            ownershipToken: ownsDownloadedDirectory
        )

        try activateAndRegisterModel(reference)
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

        try activateAndRegisterModel(reference)
        return reference
    }

    func deleteModel(_ reference: LocalModelReference) throws -> ModelDeleteOutcome {
        var references = loadModelRegistry()
        references.removeAll { $0.modelPath == reference.modelPath }

        if loadSavedModelReference()?.modelPath == reference.modelPath {
            if let fallback = references.last(where: { fileManager.fileExists(atPath: $0.modelPath) }) {
                try saveModelReference(fallback)
            } else {
                try clearModelReference()
            }
        }

        let outcome: ModelDeleteOutcome
        switch reference.sourceType {
        case .downloaded:
            if isAppDownloadedModelDirectory(reference), fileManager.fileExists(atPath: reference.modelPath) {
                try fileManager.removeItem(atPath: reference.modelPath)
                outcome = .deletedFiles(path: reference.modelPath)
            } else {
                // A stale or edited registry must never authorize recursive deletion.
                outcome = .unlinked(path: reference.modelPath)
            }
        case .linked:
            outcome = .unlinked(path: reference.modelPath)
        }

        try saveModelRegistry(references)
        return outcome
    }

    func deletionRemovesFiles(for reference: LocalModelReference) -> Bool {
        reference.sourceType == .downloaded && isAppDownloadedModelDirectory(reference)
    }

    func deleteCurrentModel() throws -> ModelDeleteOutcome {
        guard let reference = loadSavedModelReference() else {
            throw WhisperEngineError.modelMissing
        }

        return try deleteModel(reference)
    }

    func transcribe(
        inputAudioURL: URL,
        languageCode: String?,
        runHandle: TranscriptionRunHandle? = nil,
        status: (String) -> Void,
        onEvent: @escaping (TranscriptionEvent) -> Void
    ) throws -> TranscriptionResult {
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

        defer {
            runHandle?.clear()
        }

        func executeWorker(safeIntelMode: Bool) throws -> (ProcessResult, [String: Any]?) {
            var finalPayload: [String: Any]?
            let logURL = try createWorkerLog(
                inputAudioURL: inputAudioURL,
                modelID: reference.modelID,
                safeIntelMode: safeIntelMode
            )
            var environmentOverrides = safeIntelMode ? [
                "GZWHISPER_SAFE_INTEL_MODE": "1",
                "CT2_FORCE_CPU_ISA": "GENERIC",
                "CT2_PACKED_GEMM": "0",
                "CT2_USE_MKL": "0",
                "OMP_NUM_THREADS": "2",
            ] : [:]
            environmentOverrides["GZWHISPER_WORKER_LOG_PATH"] = logURL.path

            do {
                let result = try runPythonStreaming(
                    arguments: arguments,
                    environmentOverrides: environmentOverrides,
                    onStart: { process in
                        runHandle?.attach(process)
                    }
                ) { line in
                    guard let json = self.parseJSONLine(line) else { return }

                    if let event = json["event"] as? String {
                        switch event {
                        case "progress":
                            let processed = (json["processed_seconds"] as? NSNumber)?.doubleValue ?? 0
                            let totalNumber = json["total_seconds"] as? NSNumber
                            onEvent(.progress(processedSeconds: processed, totalSeconds: totalNumber?.doubleValue))
                        default:
                            break
                        }
                        return
                    }

                    if json["ok"] != nil {
                        finalPayload = json
                    }
                }

                appendWorkerCompletion(result, to: logURL)
                rotateWorkerLogs(keeping: 8)
                return (result, finalPayload)
            } catch {
                appendWorkerLogLine("launch_error: \(error.localizedDescription)", to: logURL)
                rotateWorkerLogs(keeping: 8)
                throw error
            }
        }

        var (result, payload) = try executeWorker(safeIntelMode: false)

        if result.exitCode != 0,
           result.terminationReason == .uncaughtSignal,
           MacProcessorFamily.current == .intel,
           runHandle?.isCancellationRequested != true {
            status(L10n.t("engine.retryingSafeIntel"))
            (result, payload) = try executeWorker(safeIntelMode: true)
        }

        if result.exitCode != 0 || payload?["ok"] as? Bool != true {
            if runHandle?.isCancellationRequested == true {
                throw TranscriptionCancellationError.cancelled
            }
            throw WhisperEngineError.commandFailed(
                message: workerFailureMessage(result: result, payload: payload, modelID: reference.modelID)
            )
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
        let bootstrapPythonURL = try resolvedBootstrapPythonURL()

        if shouldReuseVirtualEnvironment(bootstrapPythonURL: bootstrapPythonURL) {
            return
        }

        if fileManager.fileExists(atPath: venvDirectory.path) {
            try fileManager.removeItem(at: venvDirectory)
        }

        status(L10n.t("engine.creatingVenv"))
        let result = try ProcessRunner.run(
            executableURL: bootstrapPythonURL,
            arguments: ["-m", "venv", venvDirectory.path],
            environment: pythonEnvironment()
        )

        guard result.exitCode == 0 else {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw WhisperEngineError.commandFailed(message: L10n.f("engine.creatingVenvFailed", message))
        }
    }

    private func ensureDependencies(status: (String) -> Void) throws {
        let pythonURL = try resolvedVenvPythonURL()
        let requirementsURL = bundledRequirementsURL()

        let checkResult = try ProcessRunner.run(
            executableURL: pythonURL,
            arguments: dependencyCheckArguments(requirementsURL: requirementsURL),
            environment: pythonEnvironment()
        )

        guard checkResult.exitCode != 0 else {
            return
        }

        status(L10n.t("engine.installingDeps"))
        let requestedPackages = requirementsURL.map { ["--requirement", $0.path] }
            ?? ["faster-whisper", "huggingface_hub"]

        var offlineInstallDetails: String?

        if let wheelhouseURL = bundledWheelhouseURL() {
            let bundledInstallResult = try ProcessRunner.run(
                executableURL: pythonURL,
                arguments: [
                    "-m", "pip", "install",
                    "--no-index",
                    "--find-links", wheelhouseURL.path,
                    "--upgrade",
                ] + requestedPackages,
                environment: pythonEnvironment()
            )

            if bundledInstallResult.exitCode == 0 {
                return
            }

            offlineInstallDetails = processFailureDetails(bundledInstallResult)
        }

        _ = try ProcessRunner.run(
            executableURL: pythonURL,
            arguments: ["-m", "pip", "install", "--upgrade", "pip"],
            environment: pythonEnvironment()
        )

        let installResult = try ProcessRunner.run(
            executableURL: pythonURL,
            arguments: ["-m", "pip", "install", "--upgrade"] + requestedPackages,
            environment: pythonEnvironment()
        )

        guard installResult.exitCode == 0 else {
            var failureSections: [String] = []

            if let offlineInstallDetails, !offlineInstallDetails.isEmpty {
                failureSections.append(L10n.f("engine.offlineInstallFailed", offlineInstallDetails))
            }

            failureSections.append(L10n.f("engine.onlineInstallFailed", processFailureDetails(installResult)))

            throw WhisperEngineError.commandFailed(
                message: L10n.f("engine.installDepsFailed", failureSections.joined(separator: "\n\n"))
            )
        }
    }

    private func dependencyCheckArguments(requirementsURL: URL?) -> [String] {
        guard let requirementsURL else {
            return ["-c", "import faster_whisper, huggingface_hub, ctranslate2"]
        }

        let script = """
        import importlib.metadata as metadata
        import pathlib
        import sys

        for raw_line in pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
            line = raw_line.strip()
            if not line or line.startswith("#") or "==" not in line:
                continue
            name, expected = line.split("==", 1)
            if metadata.version(name.strip()) != expected.strip():
                raise SystemExit(1)

        import ctranslate2
        import faster_whisper
        import huggingface_hub
        """
        return ["-c", script, requirementsURL.path]
    }

    private func processFailureDetails(_ result: ProcessResult) -> String {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return stderr
        }

        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return stdout.isEmpty ? L10n.t("engine.noProcessOutput") : stdout
    }

    private func workerFailureMessage(
        result: ProcessResult,
        payload: [String: Any]?,
        modelID: String
    ) -> String {
        let message = (payload?["error"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let details = (payload?["details"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let message, !message.isEmpty {
            if let details, !details.isEmpty {
                return "\(message)\n\(details)"
            }
            return message
        }

        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return stderr
        }

        if result.terminationReason == .uncaughtSignal {
            if MacProcessorFamily.current == .intel {
                return L10n.f("engine.workerTerminatedIntel", result.exitCode, modelID)
            }
            return L10n.f("engine.workerTerminatedSignal", result.exitCode)
        }

        return L10n.f("engine.workerExitedNoOutput", result.exitCode)
    }

    private func createWorkerLog(
        inputAudioURL: URL,
        modelID: String,
        safeIntelMode: Bool
    ) throws -> URL {
        try fileManager.createDirectory(at: workerLogsDirectory, withIntermediateDirectories: true)
        let timestamp = Int(Date().timeIntervalSince1970 * 1_000)
        let mode = safeIntelMode ? "intel-safe" : "normal"
        let logURL = workerLogsDirectory.appendingPathComponent(
            "worker-\(timestamp)-\(mode)-\(UUID().uuidString.prefix(8)).log"
        )
        let inputSize = (try? inputAudioURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let processorFamily = MacProcessorFamily.current == .appleSilicon ? "apple_silicon" : "intel"
        let header = [
            "started_at: \(ISO8601DateFormatter().string(from: Date()))",
            "app_version: \(appVersion)",
            "app_build: \(appBuild)",
            "processor_family: \(processorFamily)",
            "processor_count: \(ProcessInfo.processInfo.processorCount)",
            "physical_memory_bytes: \(ProcessInfo.processInfo.physicalMemory)",
            "model_id: \(modelID)",
            "input_name: \(inputAudioURL.lastPathComponent)",
            "input_size_bytes: \(inputSize)",
            "safe_intel_mode: \(safeIntelMode)",
        ].joined(separator: "\n") + "\n"
        try Data(header.utf8).write(to: logURL, options: .atomic)
        return logURL
    }

    private func appendWorkerCompletion(_ result: ProcessResult, to logURL: URL) {
        let reason = result.terminationReason == .uncaughtSignal ? "uncaught_signal" : "exit"
        var lines = [
            "finished_at: \(ISO8601DateFormatter().string(from: Date()))",
            "termination_reason: \(reason)",
            "termination_status: \(result.exitCode)",
        ]
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            lines.append("stderr_tail:")
            lines.append(String(stderr.suffix(16_384)))
        }
        appendWorkerLogLine(lines.joined(separator: "\n"), to: logURL)
    }

    private func appendWorkerLogLine(_ line: String, to logURL: URL) {
        guard let data = (line + "\n").data(using: .utf8),
              let handle = try? FileHandle(forWritingTo: logURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.synchronize()
        } catch {
            return
        }
    }

    private func recentWorkerLogURLs(limit: Int) -> [URL] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: workerLogsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls
            .filter { $0.pathExtension == "log" }
            .sorted {
                let lhs = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhs = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhs > rhs
            }
            .prefix(limit)
            .map { $0 }
    }

    private func rotateWorkerLogs(keeping limit: Int) {
        for logURL in recentWorkerLogURLs(limit: Int.max).dropFirst(limit) {
            try? fileManager.removeItem(at: logURL)
        }
    }

    private func runPython(arguments: [String]) throws -> ProcessResult {
        try ProcessRunner.run(
            executableURL: resolvedVenvPythonURL(),
            arguments: arguments,
            environment: pythonEnvironment(includeWorkerSettings: true),
            currentDirectoryURL: supportDirectory
        )
    }

    private func runPythonStreaming(
        arguments: [String],
        environmentOverrides: [String: String] = [:],
        onStart: ((Process) -> Void)? = nil,
        onLine: @escaping (String) -> Void
    ) throws -> ProcessResult {
        try ProcessRunner.runStreaming(
            executableURL: resolvedVenvPythonURL(),
            arguments: arguments,
            environment: pythonEnvironment(includeWorkerSettings: true).merging(environmentOverrides) { _, new in new },
            currentDirectoryURL: supportDirectory,
            onStart: onStart,
            onStdoutLine: onLine,
            onStderrLine: nil
        )
    }

    private func pythonEnvironment(includeWorkerSettings: Bool = false) -> [String: String] {
        var environment = ["PYTHONDONTWRITEBYTECODE": "1"]
        if includeWorkerSettings {
            environment["PYTHONUNBUFFERED"] = "1"
            environment["GZWHISPER_UI_LANG"] = AppLanguage.current.workerCode
        }
        return environment
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

    private func resolvedBootstrapPythonURL() throws -> URL {
        for candidate in bootstrapPythonCandidates() {
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        throw WhisperEngineError.missingBootstrapPython
    }

    private func bootstrapPythonCandidates() -> [URL] {
        var candidates: [URL] = []

        if let resourcesURL = Bundle.main.resourceURL {
            candidates.append(resourcesURL.appendingPathComponent("python/bin/python3"))
        }

        let bundleURL = Bundle.main.bundleURL
        candidates.append(bundleURL.appendingPathComponent("Contents/Frameworks/Python.framework/Versions/Current/bin/python3"))
        candidates.append(bundleURL.appendingPathComponent("Contents/Frameworks/Python.framework/Versions/3.13/bin/python3"))
        candidates.append(bundleURL.appendingPathComponent("Contents/Frameworks/Python.framework/Versions/3.12/bin/python3"))
        candidates.append(bundleURL.appendingPathComponent("Contents/Frameworks/Python.framework/Versions/3.11/bin/python3"))

        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/python3"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/python3"))
        candidates.append(URL(fileURLWithPath: "/Library/Frameworks/Python.framework/Versions/Current/bin/python3"))

        return candidates
    }

    private func bundledWheelhouseURL() -> URL? {
        guard let resourcesURL = Bundle.main.resourceURL else {
            return nil
        }

        let wheelhouseURL = resourcesURL.appendingPathComponent("wheelhouse", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: wheelhouseURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }

        guard let entries = try? fileManager.contentsOfDirectory(atPath: wheelhouseURL.path), !entries.isEmpty else {
            return nil
        }

        return wheelhouseURL
    }

    private func bundledRequirementsURL() -> URL? {
        guard let resourcesURL = Bundle.main.resourceURL else { return nil }
        let url = resourcesURL.appendingPathComponent("requirements-macos.txt")
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    private var venvPythonURL: URL {
        venvDirectory.appendingPathComponent("bin/python3")
    }

    private func shouldReuseVirtualEnvironment(bootstrapPythonURL: URL) -> Bool {
        guard fileManager.fileExists(atPath: venvDirectory.path) else {
            return false
        }

        guard let currentVenvPythonURL = existingVenvPythonURL(), fileManager.isExecutableFile(atPath: currentVenvPythonURL.path) else {
            return false
        }

        let normalizedBootstrapPythonURL = normalizePathURL(bootstrapPythonURL)
        let config = venvConfiguration()

        if
            let recordedExecutable = config["executable"],
            !recordedExecutable.isEmpty
        {
            let recordedExecutableURL = URL(fileURLWithPath: recordedExecutable)
            if normalizePathURL(recordedExecutableURL) != normalizedBootstrapPythonURL {
                return false
            }
        } else if let symlinkTarget = symbolicLinkDestination(for: currentVenvPythonURL) {
            if normalizePathURL(symlinkTarget) != normalizedBootstrapPythonURL {
                return false
            }
        }

        if
            let recordedHome = config["home"],
            !recordedHome.isEmpty
        {
            let recordedHomeURL = URL(fileURLWithPath: recordedHome)
            let normalizedBootstrapHomeURL = normalizePathURL(bootstrapPythonURL.deletingLastPathComponent())
            if normalizePathURL(recordedHomeURL) != normalizedBootstrapHomeURL {
                return false
            }
        }

        return true
    }

    private func existingVenvPythonURL() -> URL? {
        let candidates = [
            venvPythonURL,
            venvDirectory.appendingPathComponent("bin/python"),
        ]

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
            return candidate
        }

        return nil
    }

    private func venvConfiguration() -> [String: String] {
        let configURL = venvDirectory.appendingPathComponent("pyvenv.cfg")
        guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else {
            return [:]
        }

        var values: [String: String] = [:]
        for line in contents.split(separator: "\n") {
            guard let separatorIndex = line.firstIndex(of: "=") else {
                continue
            }

            let key = line[..<separatorIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = line[line.index(after: separatorIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            values[key] = value
        }

        return values
    }

    private func symbolicLinkDestination(for url: URL) -> URL? {
        guard let destination = try? fileManager.destinationOfSymbolicLink(atPath: url.path) else {
            return nil
        }

        let destinationURL = URL(fileURLWithPath: destination)
        if destinationURL.path.hasPrefix("/") {
            return destinationURL
        }

        return url.deletingLastPathComponent().appendingPathComponent(destination)
    }

    private func normalizePathURL(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
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

    private func loadModelRegistry() -> [LocalModelReference] {
        guard
            let data = try? Data(contentsOf: modelRegistryURL),
            let references = try? JSONDecoder().decode([LocalModelReference].self, from: data)
        else {
            return []
        }
        return references
    }

    private func saveModelRegistry(_ references: [LocalModelReference]) throws {
        try fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(references)
        try data.write(to: modelRegistryURL, options: .atomic)
    }

    private func activateAndRegisterModel(_ reference: LocalModelReference) throws {
        let originalReferences = loadModelRegistry()
        var references = originalReferences
        references.removeAll { $0.modelPath == reference.modelPath || $0.modelID == reference.modelID }
        references.append(reference)
        try saveModelRegistry(references)
        do {
            try saveModelReference(reference)
        } catch {
            try? saveModelRegistry(originalReferences)
            throw error
        }
    }

    private func prepareManagedModelMarker(modelID: String, modelDirectory: URL) throws -> String? {
        let markerURL = modelDirectory.appendingPathComponent(Self.managedModelMarkerName)
        var isDirectory: ObjCBool = false

        if fileManager.fileExists(atPath: modelDirectory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue,
                  let data = try? Data(contentsOf: markerURL),
                  let marker = try? JSONDecoder().decode(ManagedModelMarker.self, from: data),
                  marker.modelID == modelID
            else {
                // Existing unmarked directories may belong to the user and are never claimed by the app.
                return nil
            }
            return marker.ownershipToken
        }

        try fileManager.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        let marker = ManagedModelMarker(modelID: modelID, ownershipToken: UUID().uuidString)
        let data = try JSONEncoder().encode(marker)
        try data.write(to: markerURL, options: .atomic)
        return marker.ownershipToken
    }

    private func isAppDownloadedModelDirectory(_ reference: LocalModelReference) -> Bool {
        guard let ownershipToken = reference.ownershipToken else { return false }
        let url = URL(fileURLWithPath: reference.modelPath).standardizedFileURL
        guard url.pathComponents.count > 2 else { return false }
        let markerURL = url.appendingPathComponent(Self.managedModelMarkerName)
        guard
            let markerData = try? Data(contentsOf: markerURL),
            let marker = try? JSONDecoder().decode(ManagedModelMarker.self, from: markerData),
            marker.modelID == reference.modelID,
            marker.ownershipToken == ownershipToken
        else {
            return false
        }
        return fileManager.fileExists(atPath: url.appendingPathComponent("config.json").path)
            && fileManager.fileExists(atPath: url.appendingPathComponent("model.bin").path)
    }

    private func clearModelReference() throws {
        if fileManager.fileExists(atPath: modelReferenceURL.path) {
            try fileManager.removeItem(at: modelReferenceURL)
        }
    }
}
