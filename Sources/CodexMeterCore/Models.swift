import Foundation

public struct Tokens: Codable, Hashable, Sendable {
    public var input: Int
    public var cached: Int
    public var output: Int
    public var cacheWrite: Int
    public var total: Int { input + output }
    public var uncached: Int { max(0, input - cached - cacheWrite) }
    public init(input: Int = 0, cached: Int = 0, output: Int = 0, cacheWrite: Int = 0) {
        self.input = max(0, input)
        self.cached = min(max(0, cached), self.input)
        self.output = max(0, output)
        self.cacheWrite = min(max(0, cacheWrite), self.input - self.cached)
    }
    public static func + (lhs: Tokens, rhs: Tokens) -> Tokens {
        Tokens(input: lhs.input + rhs.input, cached: lhs.cached + rhs.cached,
               output: lhs.output + rhs.output, cacheWrite: lhs.cacheWrite + rhs.cacheWrite)
    }
    func delta(from previous: Tokens) -> Tokens {
        Tokens(input: input - previous.input, cached: cached - previous.cached,
               output: output - previous.output, cacheWrite: cacheWrite - previous.cacheWrite)
    }
    init(json: [String: Any]) {
        self.init(input: json["input_tokens"] as? Int ?? 0,
                  cached: json["cached_input_tokens"] as? Int ?? 0,
                  output: json["output_tokens"] as? Int ?? 0,
                  cacheWrite: json["cache_write_input_tokens"] as? Int ?? 0)
    }
}

public struct UsageRecord: Sendable {
    public let timestamp: Date
    public let model: String
    public let provider: String
    public let tokens: Tokens
    public let requestInput: Int
    public let serviceTier: String?
    // The same event can be copied into a fork or an archived rollout.
    let fingerprint: String
    public init(timestamp: Date, model: String, provider: String = "openai", tokens: Tokens,
                requestInput: Int? = nil, serviceTier: String? = nil, fingerprint: String = UUID().uuidString) {
        self.timestamp = timestamp
        self.model = model
        self.provider = provider
        self.tokens = tokens
        self.requestInput = requestInput ?? tokens.input
        self.serviceTier = serviceTier
        self.fingerprint = fingerprint
    }
}

public struct CostBreakdown: Sendable {
    public var input: Double = 0
    public var cached: Double = 0
    public var output: Double = 0
    public var total: Double { input + cached + output }
    public static func + (a: Self, b: Self) -> Self {
        Self(input: a.input + b.input, cached: a.cached + b.cached, output: a.output + b.output)
    }
}

public struct DailyUsage: Identifiable, Sendable {
    public var id: Date { date }
    public let date: Date
    public var tokens = Tokens()
    public var cost = CostBreakdown()
    public var unpricedTokens: Int = 0
    public var unpricedModels: Set<String> = []
    public var isCostComplete: Bool { unpricedTokens == 0 }
    public init(date: Date) { self.date = date }
    public mutating func add(_ other: DailyUsage) {
        tokens = tokens + other.tokens
        cost = cost + other.cost
        unpricedTokens += other.unpricedTokens
        unpricedModels.formUnion(other.unpricedModels)
    }
}

public struct RateWindow: Decodable, Sendable {
    public let usedPercent: Double
    public let windowDurationMins: Int?
    public let resetsAt: Double?
    public var usedFraction: Double { min(1, max(0, usedPercent / 100)) }
    public var remainingPercent: Double { 100 - min(100, max(0, usedPercent)) }
    public var resetDate: Date? { resetsAt.map(Date.init(timeIntervalSince1970:)) }
}

public struct RateSnapshot: Decodable, Sendable {
    public let limitId: String?
    public let planType: String?
    public let primary: RateWindow?
    public let secondary: RateWindow?
}

public struct RateLimitsResponse: Decodable, Sendable {
    public let rateLimits: RateSnapshot
    public let rateLimitsByLimitId: [String: RateSnapshot]?
    public var codex: RateSnapshot? {
        if let buckets = rateLimitsByLimitId, !buckets.isEmpty {
            return buckets["codex"]
        }
        guard rateLimits.limitId == nil || rateLimits.limitId == "codex" else { return nil }
        return rateLimits
    }
    // Primary is not always 5h. Match durations, never assume bucket order.
    public var fiveHour: RateWindow? { window(minutes: 300) }
    public var sevenDay: RateWindow? { window(minutes: 10080) }
    private func window(minutes: Int) -> RateWindow? {
        guard let snapshot = codex else { return nil }
        return [snapshot.primary, snapshot.secondary].compactMap { $0 }
            .first { $0.windowDurationMins == minutes }
    }
}

public enum MeterError: LocalizedError {
    case message(String)
    public var errorDescription: String? {
        if case .message(let text) = self { return text }
        return nil
    }
}
