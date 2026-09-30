import Foundation

public struct SessionScan: Sendable {
    public let records: [UsageRecord]
    public let fileCount: Int
    public let warnings: [String]
}

public actor SessionService {
    public let home: URL
    private struct CachedFile {
        let size: Int
        let modified: Date
        let records: [UsageRecord]
        let malformed: Int
    }
    private var cache: [URL: CachedFile] = [:]
    public init(home: URL = CodexPaths.home) { self.home = home }
    public func scan() throws -> SessionScan {
        let manager = FileManager.default
        let roots = ["sessions", "archived_sessions"].map { home.appendingPathComponent($0) }
        guard roots.contains(where: { manager.fileExists(atPath: $0.path) }) else {
            throw MeterError.message("未找到 Codex sessions：\(home.path)。请先在 Codex 中使用一次模型。")
        }
        var seenFiles: Set<URL> = []
        var records: [UsageRecord] = []
        var warnings: [String] = []
        var fingerprints: Set<String> = []
        for root in roots where manager.fileExists(atPath: root.path) {
            guard let enumerator = manager.enumerator(at: root, includingPropertiesForKeys:
                [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles], errorHandler: { url, _ in
                    warnings.append("无法读取 \(url.lastPathComponent)"); return true
                }) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                do {
                    let attributes = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey])
                    guard attributes.isRegularFile == true else { continue }
                    seenFiles.insert(url)
                    let size = attributes.fileSize ?? 0
                    let modified = attributes.contentModificationDate ?? .distantPast
                    let item: CachedFile
                    if let old = cache[url], old.size == size, old.modified == modified { item = old }
                    else {
                        let data = try Data(contentsOf: url, options: .mappedIfSafe)
                        let parsed = SessionParser.parse(data)
                        item = CachedFile(size: size, modified: modified, records: parsed.records, malformed: parsed.malformed)
                        cache[url] = item
                    }
                    if item.malformed > 0 { warnings.append("\(url.lastPathComponent)：\(item.malformed) 条记录无法解析") }
                    for record in item.records where fingerprints.insert(record.fingerprint).inserted { records.append(record) }
                } catch { warnings.append("无法读取 \(url.lastPathComponent)：\(error.localizedDescription)") }
            }
        }
        cache = cache.filter { seenFiles.contains($0.key) }
        return SessionScan(records: records.sorted { $0.timestamp < $1.timestamp }, fileCount: seenFiles.count, warnings: warnings)
    }
}

public enum SessionParser {
    public static func parse(_ data: Data) -> (records: [UsageRecord], malformed: Int) {
        var records: [UsageRecord] = []
        var model = "unknown"
        var provider = "openai"
        var tier: String?
        var previous: Tokens?
        var malformed = 0
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let fallback = ISO8601DateFormatter()
        // Only inspect metadata and token events; prompts and tool outputs aren't retained.
        let lines = data.split(separator: 10, omittingEmptySubsequences: true)
        for (index, bytes) in lines.enumerated() {
            guard let text = String(data: Data(bytes), encoding: .utf8),
                  text.contains("token_count") || text.contains("turn_context") || text.contains("session_meta") else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: Data(bytes)) as? [String: Any],
                  let type = object["type"] as? String,
                  let payload = object["payload"] as? [String: Any] else {
                // A live writer may not have finished its last line yet. Retry next scan.
                if index != lines.count - 1 || data.last == 10 { malformed += 1 }
                continue
            }
            if type == "session_meta" {
                provider = payload["model_provider"] as? String ?? provider
                model = payload["model"] as? String ?? model
            }
            if type == "turn_context" {
                model = payload["model"] as? String ?? model
                provider = payload["model_provider"] as? String ?? provider
                tier = payload["service_tier"] as? String
            }
            guard type == "event_msg", payload["type"] as? String == "token_count",
                  let info = payload["info"] as? [String: Any],
                  let stamp = object["timestamp"] as? String,
                  let timestamp = formatter.date(from: stamp) ?? fallback.date(from: stamp) else { continue }
            let cumulative = (info["total_token_usage"] as? [String: Any]).map(Tokens.init(json:))
            let last = (info["last_token_usage"] as? [String: Any]).map(Tokens.init(json:))
            let tokens: Tokens
            if let current = cumulative {
                if let old = previous {
                    if current == old { continue } // Quota notifications often repeat the counters.
                    if current.input >= old.input && current.output >= old.output { tokens = current.delta(from: old) }
                    else { tokens = last ?? current } // Counter reset after compaction/resume.
                } else { tokens = last ?? current }
                previous = current
            } else if let last { tokens = last }
            else { continue }
            guard tokens.total > 0 else { continue }
            let counter = cumulative ?? tokens
            let fingerprint = "\(stamp)|\(counter.input)|\(counter.cached)|\(counter.output)|\(counter.cacheWrite)|\(tokens.input)|\(tokens.output)"
            records.append(UsageRecord(timestamp: timestamp, model: model, provider: provider, tokens: tokens,
                                       requestInput: last?.input ?? tokens.input, serviceTier: tier, fingerprint: fingerprint))
        }
        return (records, malformed)
    }
}

public enum CodexPaths {
    public static var home: URL {
        if let path = ProcessInfo.processInfo.environment["CODEX_HOME"], !path.isEmpty {
            return URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
    }
    public static func executable(override: String? = nil) throws -> URL {
        var candidates: [String] = []
        if let override, !override.isEmpty {
            let path = NSString(string: override).expandingTildeInPath
            guard FileManager.default.isExecutableFile(atPath: path) else {
                throw MeterError.message("Codex CLI 路径无效或不可执行：\(path)")
            }
            return URL(fileURLWithPath: path)
        }
        if let value = ProcessInfo.processInfo.environment["CODEX_BIN"] { candidates.append(value) }
        candidates += [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex"
        ]
        candidates += (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
        guard let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw MeterError.message("未找到 Codex CLI，请安装 Codex 或在设置里填写可执行文件路径。")
        }
        return URL(fileURLWithPath: path)
    }
}
