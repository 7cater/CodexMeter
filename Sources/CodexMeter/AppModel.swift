import Foundation
import SwiftUI
import ServiceManagement
import CodexMeterCore

@MainActor
final class AppModel: ObservableObject {
    @Published var limits: RateLimitsResponse?
    @Published var daily: [DailyUsage] = []
    @Published var usageError: String?
    @Published var sessionError: String?
    @Published var refreshing = false
    @Published var usageUpdated: Date?
    @Published var sessionsUpdated: Date?
    @Published var fileCount = 0
    @Published var warnings: [String] = []
    @Published var selectedDays = 7
    @Published var settingsVisible = false
    @Published var panelPresentationID = UUID()
    @Published var loginError: String?
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var refreshMinutes: Int {
        didSet { UserDefaults.standard.set(refreshMinutes, forKey: "refreshMinutes"); scheduleRefresh() }
    }
    @Published var estimateCost: Bool {
        didSet { UserDefaults.standard.set(estimateCost, forKey: "estimateCost") }
    }
    @Published var menuMode: String {
        didSet { UserDefaults.standard.set(menuMode, forKey: "menuMode") }
    }
    @Published var cliPath: String {
        didSet { UserDefaults.standard.set(cliPath, forKey: "cliPath") }
    }
    let pricing: PricingService?
    let sessions = SessionService()
    private var timer: Timer?
    private var midnightTimer: Timer?
    init() {
        let defaults = UserDefaults.standard
        let interval = defaults.integer(forKey: "refreshMinutes")
        refreshMinutes = [1, 5, 15].contains(interval) ? interval : 5
        estimateCost = defaults.object(forKey: "estimateCost") == nil ? true : defaults.bool(forKey: "estimateCost")
        menuMode = defaults.string(forKey: "menuMode") ?? "both"
        cliPath = defaults.string(forKey: "cliPath") ?? ""
        pricing = try? PricingService()
    }
    var today: DailyUsage { daily.last ?? DailyUsage(date: Calendar.current.startOfDay(for: Date())) }
    var visibleDays: [DailyUsage] { Array(daily.suffix(selectedDays)) }
    var period: DailyUsage {
        var total = DailyUsage(date: Date())
        for day in visibleDays { total.add(day) }
        return total
    }
    func start() {
        scheduleRefresh()
        // Keep today's date and reset countdown fresh across midnight, sleep and wake.
        midnightTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if let date = self.daily.last?.date, !Calendar.current.isDateInToday(date) { await self.refresh() }
                else { self.objectWillChange.send() }
            }
        }
        Task { await refresh() }
    }
    func scheduleRefresh() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Double(refreshMinutes) * 60, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }
    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        async let usage: Void = refreshUsage()
        async let history: Void = refreshSessions()
        _ = await (usage, history)
        refreshing = false
    }
    private func refreshUsage() async {
        do {
            limits = try await CodexUsageService.fetch(executable: CodexPaths.executable(override: cliPath))
            usageUpdated = Date()
            usageError = nil
        } catch { usageError = error.localizedDescription }
    }
    private func refreshSessions() async {
        do {
            let scan = try await sessions.scan()
            guard let pricing else { throw MeterError.message("无法加载模型价格表") }
            daily = pricing.aggregate(scan.records)
            fileCount = scan.fileCount
            warnings = scan.warnings
            sessionsUpdated = Date()
            sessionError = nil
        } catch { sessionError = error.localizedDescription }
    }
    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginError = SMAppService.mainApp.status == .requiresApproval ? "请在系统设置 → 通用 → 登录项中允许 CodexMeter。" : nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginError = error.localizedDescription
        }
    }
}

enum Display {
    static func tokens(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.2fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return String(value)
    }
    static func cost(_ usage: DailyUsage) -> String {
        if usage.tokens.total > 0 && usage.unpricedTokens == usage.tokens.total { return "—" }
        return (usage.isCostComplete ? "" : "≥ ") + String(format: "$%.2f", usage.cost.total)
    }
    static func reset(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "重置时间未提供" }
        let minutes = max(0, Int(ceil(date.timeIntervalSince(now) / 60)))
        if minutes == 0 { return "等待服务端更新" }
        if minutes >= 1440 { return "\(minutes / 1440)天 \((minutes % 1440) / 60)小时后重置" }
        if minutes >= 60 { return "\(minutes / 60)小时 \(minutes % 60)分钟后重置" }
        return "\(minutes)分钟后重置"
    }
}
