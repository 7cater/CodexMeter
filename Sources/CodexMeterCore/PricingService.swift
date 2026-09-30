import Foundation

public struct ModelPrice: Decodable, Sendable {
    public let input: Double
    public let cached: Double
    public let output: Double
    public let cacheWrite: Double?
    public let longContextThreshold: Int?
}

public struct PricingService: Sendable {
    public let checkedAt: String
    public let source: String
    public let models: [String: ModelPrice]
    private struct Table: Decodable {
        let checkedAt: String
        let source: String
        let models: [String: ModelPrice]
    }
    public init() throws {
        let packaged = Bundle.main.resourceURL.map { $0.appendingPathComponent("CodexMeter_CodexMeterCore.bundle") }.flatMap { Bundle(url: $0) }
        guard let url = (packaged ?? Bundle.module).url(forResource: "pricing", withExtension: "json") else {
            throw MeterError.message("找不到模型价格表")
        }
        let table = try JSONDecoder().decode(Table.self, from: Data(contentsOf: url))
        checkedAt = table.checkedAt
        source = table.source
        models = table.models
    }
    public func price(for model: String) -> ModelPrice? {
        if let value = models[model] { return value }
        // Only strip an explicit YYYY-MM-DD snapshot suffix; don't guess model families.
        if model.range(of: #"-\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil {
            return models[String(model.dropLast(11))]
        }
        return nil
    }
    public func estimate(_ record: UsageRecord) -> CostBreakdown? {
        guard record.provider == "openai", let rate = price(for: record.model) else { return nil }
        let long = rate.longContextThreshold.map { record.requestInput > $0 } ?? false
        let tier: Double
        switch record.serviceTier {
        case "fast", "priority": tier = 2
        case "flex", "batch": tier = 0.5
        case nil, "auto", "default", "standard": tier = 1
        default: return nil
        }
        let inputMultiplier = (long ? 2.0 : 1.0) * tier / 1_000_000
        let outputMultiplier = (long ? 1.5 : 1.0) * tier / 1_000_000
        return CostBreakdown(
            input: (Double(record.tokens.uncached) * rate.input
                + Double(record.tokens.cacheWrite) * (rate.cacheWrite ?? rate.input * 1.25)) * inputMultiplier,
            cached: Double(record.tokens.cached) * rate.cached * inputMultiplier,
            output: Double(record.tokens.output) * rate.output * outputMultiplier
        )
    }
    public func aggregate(_ records: [UsageRecord], now: Date = Date(), days: Int = 30,
                          calendar: Calendar = .current) -> [DailyUsage] {
        let today = calendar.startOfDay(for: now)
        let dates = (0..<days).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        var totals = Dictionary(uniqueKeysWithValues: dates.map { ($0, DailyUsage(date: $0)) })
        for record in records {
            let day = calendar.startOfDay(for: record.timestamp)
            guard var daily = totals[day] else { continue }
            daily.tokens = daily.tokens + record.tokens
            if let cost = estimate(record) { daily.cost = daily.cost + cost }
            else {
                daily.unpricedTokens += record.tokens.total
                daily.unpricedModels.insert(record.model)
            }
            totals[day] = daily
        }
        return dates.compactMap { totals[$0] }
    }
}
