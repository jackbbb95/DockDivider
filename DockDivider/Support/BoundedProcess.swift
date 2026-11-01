//
//  BoundedProcess.swift
//  DockDivider
//

import Foundation

/// Runs a short-lived helper process with a hard deadline.
///
/// The editor uses this for `shortcuts list`. A helper that ignores `SIGTERM`
/// must never leave the editor waiting forever, so the timeout escalates to
/// `SIGKILL`. Output is drained on a private queue so a chatty child cannot
/// fill the pipe buffer and deadlock, and it is capped so a misbehaving tool
/// cannot grow memory without bound.
nonisolated enum BoundedProcess {

    struct Result: Sendable {
        let terminationStatus: Int32
        let output: Data
        let timedOut: Bool

        var outputText: String {
            String(data: output, encoding: .utf8) ?? ""
        }
    }

    /// Grace period after `SIGTERM` before escalating to `SIGKILL`.
    static let terminationGrace: TimeInterval = 0.5

    private final class OutputBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        private let limit: Int

        init(limit: Int) {
            self.limit = limit
        }

        func append(_ chunk: Data) {
            lock.lock()
            defer { lock.unlock() }
            let remaining = max(0, limit - data.count)
            if remaining > 0 {
                data.append(contentsOf: chunk.prefix(remaining))
            }
        }

        var value: Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    static func run(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval,
        outputLimit: Int = 1 << 20
    ) -> Result? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice

        let collected = OutputBuffer(limit: outputLimit)
        let drainFinished = DispatchSemaphore(value: 0)

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                drainFinished.signal()
                return
            }
            collected.append(chunk)
        }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            return nil
        }

        // Release our copy of the write end so the reader observes EOF when the
        // child exits instead of waiting for this process to exit.
        try? outputPipe.fileHandleForWriting.close()

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }

        var timedOut = false
        if process.isRunning {
            timedOut = true
            process.terminate()

            let graceDeadline = Date().addingTimeInterval(terminationGrace)
            while process.isRunning && Date() < graceDeadline {
                Thread.sleep(forTimeInterval: 0.02)
            }

            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        process.waitUntilExit()

        // The drain handler sees EOF as soon as the child's output closes. The
        // wait is generous but bounded; the deadline above already guarantees
        // this call cannot hang on the child.
        _ = drainFinished.wait(timeout: .now() + 1.0)
        outputPipe.fileHandleForReading.readabilityHandler = nil

        return Result(
            terminationStatus: process.terminationStatus,
            output: collected.value,
            timedOut: timedOut
        )
    }
}
