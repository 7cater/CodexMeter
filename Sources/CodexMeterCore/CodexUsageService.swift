import Foundation

public enum CodexUsageService {
    public static func fetch(executable: URL, timeout: TimeInterval = 30) async throws -> RateLimitsResponse {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do { continuation.resume(returning: try read(executable: executable, timeout: timeout)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    private static func read(executable: URL, timeout: TimeInterval) throws -> RateLimitsResponse {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (environment["PATH"] ?? "")
        process.environment = environment
        try process.run()
        // Enforce a deadline even if the CLI never emits a response.
        let deadline = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        deadline.schedule(deadline: .now() + timeout)
        deadline.setEventHandler { if process.isRunning { process.terminate() } }
        deadline.resume()
        defer {
            deadline.cancel()
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            try? output.fileHandleForReading.close()
        }
        func send(_ message: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: message)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        try send(["id": 1, "method": "initialize", "params": [
            "clientInfo": ["name": "codexmeter", "title": "CodexMeter", "version": "0.1.0"]
        ]])
        var buffer = Data()
        var initialized = false
        while true {
            let chunk = output.fileHandleForReading.availableData
            guard !chunk.isEmpty else {
                throw MeterError.message("Codex 额度读取超时或进程退出。请确认 Codex 已登录，稍后刷新。")
            }
            buffer.append(chunk)
            guard buffer.count < 8_000_000 else { throw MeterError.message("Codex RPC 响应过大") }
            while let newline = buffer.firstIndex(of: 10) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(...newline)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let id = object["id"] as? Int, id == 1 || id == 2 else { continue }
                if let error = object["error"] as? [String: Any] {
                    throw MeterError.message("Codex RPC：\(error["message"] as? String ?? "无法读取额度")")
                }
                if id == 1 && !initialized {
                    initialized = true
                    try send(["method": "initialized"])
                    try send(["id": 2, "method": "account/rateLimits/read"])
                }
                if id == 2, let result = object["result"] as? [String: Any] {
                    return try JSONDecoder().decode(RateLimitsResponse.self,
                        from: JSONSerialization.data(withJSONObject: result))
                }
            }
        }
    }
}
