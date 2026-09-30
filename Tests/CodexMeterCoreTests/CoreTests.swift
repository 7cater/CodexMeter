import Foundation
import CodexMeterCore

final class CoreTests {
    func line(_ type: String, _ payload: [String: Any], time: String = "2026-09-29T18:00:00.000Z") -> String {
        let data = try! JSONSerialization.data(withJSONObject: ["type": type, "timestamp": time, "payload": payload], options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self) + "\n"
    }
    func counters(_ input: Int, _ cached: Int = 0, _ output: Int = 10) -> [String: Int] {
        ["input_tokens": input, "cached_input_tokens": cached, "output_tokens": output, "reasoning_output_tokens": output / 2, "total_tokens": input + output]
    }
    func token(_ cumulative: [String: Int]?, _ last: [String: Int]?, time: String = "2026-09-29T18:00:00.000Z") -> String {
        var info: [String: Any] = [:]
        info["total_token_usage"] = cumulative
        info["last_token_usage"] = last
        return line("event_msg", ["type": "token_count", "info": info], time: time)
    }
    func testCumulativeDeltasAndRepeatedNotifications() {
        let text = line("turn_context", ["model": "gpt-6.1-sol"])
            + token(counters(100, 40), counters(100, 40))
            + token(counters(100, 40), counters(100, 40))
            + token(counters(250, 140, 30), counters(150, 100, 20), time: "2026-09-29T18:01:00.000Z")
        let parsed = SessionParser.parse(Data(text.utf8))
        checkEqual(parsed.records.count, 2)
        checkEqual(parsed.records.reduce(Tokens()) { $0 + $1.tokens }, Tokens(input: 250, cached: 140, output: 30))
        checkEqual(parsed.records.last?.model, "gpt-6.1-sol")
    }
    func testCacheAndReasoningAreNotDoubleCounted() {
        let parsed = SessionParser.parse(Data(token(counters(100, 80, 20), counters(100, 80, 20)).utf8))
        checkEqual(parsed.records.first?.tokens.total, 120)
        checkEqual(parsed.records.first?.tokens.uncached, 20)
    }
    func testCounterResetAndModelChange() {
        let text = line("turn_context", ["model": "gpt-6-sol"])
            + token(counters(100), counters(100))
            + line("turn_context", ["model": "gpt-6-luna"])
            + token(counters(30, 10, 5), counters(30, 10, 5), time: "2026-09-29T18:02:00.000Z")
        let parsed = SessionParser.parse(Data(text.utf8))
        checkEqual(parsed.records.map(\.tokens.input), [100, 30])
        checkEqual(parsed.records.last?.model, "gpt-6-luna")
    }
    func testCarryInUsesLastRequestRatherThanOldCumulativeHistory() {
        let parsed = SessionParser.parse(Data(token(counters(10000, 5000, 200), counters(100, 40, 10)).utf8))
        checkEqual(parsed.records.first?.tokens.input, 100)
    }
    func testNullInfoAndPartialWriterLine() {
        let text = line("event_msg", ["type": "token_count", "info": NSNull()])
            + token(counters(100), counters(100)) + "{\"type\":\"token_count\""
        let parsed = SessionParser.parse(Data(text.utf8))
        checkEqual(parsed.records.count, 1)
        checkEqual(parsed.malformed, 0)
    }
    func testMalformedCompleteLineIsReported() {
        let parsed = SessionParser.parse(Data("{\"type\":\"token_count\"\n".utf8))
        checkEqual(parsed.malformed, 1)
    }
    func testScanDeduplicatesArchiveAndRefreshAndPicksUpAppend() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let sessions = root.appendingPathComponent("sessions")
        let archive = root.appendingPathComponent("archived_sessions")
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        let text = line("turn_context", ["model": "gpt-6-sol"]) + token(counters(100), counters(100))
        let file = sessions.appendingPathComponent("a.jsonl")
        try Data(text.utf8).write(to: file)
        try Data(text.utf8).write(to: archive.appendingPathComponent("fork.jsonl"))
        let scanner = SessionService(home: root)
        let first = try await scanner.scan()
        let second = try await scanner.scan()
        checkEqual(first.fileCount, 2)
        checkEqual(first.records.count, 1)
        checkEqual(second.records.count, 1)
        try Data((text + token(counters(200, 40, 20), counters(100, 40, 10), time: "2026-09-29T18:02:00.000Z")).utf8).write(to: file)
        let third = try await scanner.scan()
        checkEqual(third.records.reduce(0) { $0 + $1.tokens.input }, 200)
        try FileManager.default.removeItem(at: file)
        let fourth = try await scanner.scan()
        checkEqual(fourth.records.count, 1)
    }
    func record(_ model: String, tokens: Tokens, requestInput: Int? = nil, tier: String? = nil, provider: String = "openai") -> UsageRecord {
        UsageRecord(timestamp: ISO8601DateFormatter().date(from: "2026-09-29T18:00:00Z")!, model: model,
                    provider: provider, tokens: tokens, requestInput: requestInput ?? tokens.input,
                    serviceTier: tier, fingerprint: UUID().uuidString)
    }
    func testPricingCacheSubtractionAndUnknownModel() throws {
        let pricing = try PricingService()
        let result = try unwrap(pricing.estimate(record("gpt-6.1-sol", tokens: Tokens(input: 1_000_000, cached: 800_000, output: 100_000), requestInput: 100000)))
        checkEqual(result.total, 1.48, accuracy: 0.000001)
        checkNil(pricing.estimate(record("unknown", tokens: Tokens(input: 100))))
        checkNil(pricing.estimate(record("gpt-6.1-sol", tokens: Tokens(input: 100), provider: "other")))
        checkNil(pricing.price(for: "gpt-6-super-new"))
        checkNotNil(pricing.price(for: "gpt-6-sol-2026-08-01"))
    }
    func testLongContextFastAndCacheWriteCost() throws {
        let pricing = try PricingService()
        let tokens = Tokens(input: 300000, cached: 100000, output: 10000, cacheWrite: 50000)
        let result = try unwrap(pricing.estimate(record("gpt-6.1-sol", tokens: tokens, tier: "fast")))
        checkEqual(result.input, (150000 * 2.0 + 50000 * 2.5) * 4 / 1000000, accuracy: 0.000001)
        checkEqual(result.cached, 0.04, accuracy: 0.000001)
        checkEqual(result.output, 0.3, accuracy: 0.000001)
    }
    func testDailyAggregationUsesLocalTimeAndZeroFillsDays() throws {
        let pricing = try PricingService()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let now = ISO8601DateFormatter().date(from: "2026-09-30T01:00:00Z")!
        let results = pricing.aggregate([record("gpt-6.1-sol", tokens: Tokens(input: 100)), record("unknown", tokens: Tokens(input: 50))], now: now, days: 7, calendar: calendar)
        checkEqual(results.count, 7)
        checkEqual(results.last?.tokens.total, 150)
        checkEqual(results.last?.unpricedTokens, 50)
        checkEqual(results.first?.tokens.total, 0)
        checkFalse(try unwrap(results.last).isCostComplete)
    }
    func testRateWindowMappingByDuration() throws {
        let data = Data(#"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":41,"windowDurationMins":10080,"resetsAt":1791164126},"secondary":{"usedPercent":9,"windowDurationMins":300}},"rateLimitsByLimitId":null}"#.utf8)
        let limits = try JSONDecoder().decode(RateLimitsResponse.self, from: data)
        checkEqual(limits.fiveHour?.remainingPercent, 91)
        checkEqual(limits.sevenDay?.remainingPercent, 59)
    }
    func testMissingBucketDoesNotBecomeZeroUsage() throws {
        let data = Data(#"{"rateLimits":{"limitId":"codex","primary":{"usedPercent":41,"windowDurationMins":10080},"secondary":null},"rateLimitsByLimitId":{"other":{"primary":{"usedPercent":0,"windowDurationMins":300}}}}"#.utf8)
        let limits = try JSONDecoder().decode(RateLimitsResponse.self, from: data)
        checkNil(limits.fiveHour)
        checkNil(limits.sevenDay)
    }
    func testRPCHandshakeAndResponse() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let cli = root.appendingPathComponent("codex")
        let script = """
        #!/bin/sh
        IFS= read -r initialization
        printf '%s\\n' "$initialization" > "$(dirname "$0")/transcript"
        printf '%s\\n' '{"id":1,"result":{}}'
        IFS= read -r initialized
        printf '%s\\n' "$initialized" >> "$(dirname "$0")/transcript"
        IFS= read -r request
        printf '%s\\n' "$request" >> "$(dirname "$0")/transcript"
        printf '%s\\n' '{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":12,"windowDurationMins":300},"secondary":{"usedPercent":34,"windowDurationMins":10080}}}}'
        """
        try Data(script.utf8).write(to: cli)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
        let result = try await CodexUsageService.fetch(executable: cli, timeout: 2)
        checkEqual(result.fiveHour?.usedPercent, 12)
        checkEqual(result.sevenDay?.usedPercent, 34)
        let lines = try String(contentsOf: root.appendingPathComponent("transcript"), encoding: .utf8).split(separator: "\n")
        let messages = try lines.map { try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any] }
        checkEqual(messages.compactMap { $0["method"] as? String }, ["initialize", "initialized", "account/rateLimits/read"])
    }
    func testRPCDeadline() async throws {
        let cli = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cli) }
        try Data("#!/bin/sh\nexec /bin/sleep 5\n".utf8).write(to: cli)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: cli.path)
        let start = Date()
        do {
            _ = try await CodexUsageService.fetch(executable: cli, timeout: 0.2)
            checkEqual(true, false)
        } catch { checkEqual(Date().timeIntervalSince(start) < 3, true) }
    }

}
