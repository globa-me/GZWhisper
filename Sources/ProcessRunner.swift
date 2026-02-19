import Foundation

struct ProcessResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

enum ProcessRunnerError: LocalizedError {
    case cannotLaunch(executable: String, reason: String)

    var errorDescription: String? {
        switch self {
        case let .cannotLaunch(executable, reason):
            return "Не удалось запустить \(executable): \(reason)"
        }
    }
}

enum ProcessRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = [:],
        currentDirectoryURL: URL? = nil
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        process.currentDirectoryURL = currentDirectoryURL

        let tempDirectory = FileManager.default.temporaryDirectory
        let stdoutURL = tempDirectory.appendingPathComponent("gzwhisper-\(UUID().uuidString)-stdout.log")
        let stderrURL = tempDirectory.appendingPathComponent("gzwhisper-\(UUID().uuidString)-stderr.log")

        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)

        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)

        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
        }

        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        do {
            try process.run()
        } catch {
            throw ProcessRunnerError.cannotLaunch(executable: executableURL.path, reason: error.localizedDescription)
        }

        process.waitUntilExit()

        try stdoutHandle.synchronize()
        try stderrHandle.synchronize()

        let stdoutData = try Data(contentsOf: stdoutURL)
        let stderrData = try Data(contentsOf: stderrURL)

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""

        return ProcessResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    static func runStreaming(
        executableURL: URL,
        arguments: [String],
        environment: [String: String] = [:],
        currentDirectoryURL: URL? = nil,
        onStdoutLine: ((String) -> Void)? = nil,
        onStderrLine: ((String) -> Void)? = nil
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        process.currentDirectoryURL = currentDirectoryURL

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let queue = DispatchQueue(label: "gzwhisper.processrunner.stream")

        var stdoutFull = Data()
        var stderrFull = Data()
        var stdoutBuffer = Data()
        var stderrBuffer = Data()

        func consume(
            _ chunk: Data,
            full: inout Data,
            buffer: inout Data,
            lineHandler: ((String) -> Void)?
        ) {
            guard !chunk.isEmpty else { return }

            full.append(chunk)
            buffer.append(chunk)

            while let newlineRange = buffer.firstRange(of: Data([0x0A])) {
                let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
                buffer.removeSubrange(0..<newlineRange.upperBound)

                if let line = String(data: lineData, encoding: .utf8) {
                    lineHandler?(line)
                }
            }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            queue.sync {
                consume(data, full: &stdoutFull, buffer: &stdoutBuffer, lineHandler: onStdoutLine)
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }

            queue.sync {
                consume(data, full: &stderrFull, buffer: &stderrBuffer, lineHandler: onStderrLine)
            }
        }

        do {
            try process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw ProcessRunnerError.cannotLaunch(executable: executableURL.path, reason: error.localizedDescription)
        }

        process.waitUntilExit()

        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        stderrPipe.fileHandleForReading.readabilityHandler = nil

        let stdoutTail = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrTail = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        queue.sync {
            consume(stdoutTail, full: &stdoutFull, buffer: &stdoutBuffer, lineHandler: onStdoutLine)
            consume(stderrTail, full: &stderrFull, buffer: &stderrBuffer, lineHandler: onStderrLine)

            if !stdoutBuffer.isEmpty {
                if let line = String(data: stdoutBuffer, encoding: .utf8) {
                    onStdoutLine?(line)
                }
                stdoutBuffer.removeAll(keepingCapacity: false)
            }

            if !stderrBuffer.isEmpty {
                if let line = String(data: stderrBuffer, encoding: .utf8) {
                    onStderrLine?(line)
                }
                stderrBuffer.removeAll(keepingCapacity: false)
            }
        }

        let stdout = String(data: stdoutFull, encoding: .utf8) ?? ""
        let stderr = String(data: stderrFull, encoding: .utf8) ?? ""

        return ProcessResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
}
