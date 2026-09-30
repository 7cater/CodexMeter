import AppKit
import SwiftUI
import Combine
import CodexMeterCore

@main
enum CodexMeterApp {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--diagnose") {
            Task {
                var report: [String: Any] = [:]
                do {
                    let scan = try await SessionService().scan()
                    let pricing = try PricingService()
                    let daily = pricing.aggregate(scan.records)
                    report["sessionFiles"] = scan.fileCount
                    report["records"] = scan.records.count
                    report["warnings"] = scan.warnings.count
                    report["todayTokens"] = daily.last?.tokens.total ?? 0
                    report["todayEstimatedCost"] = daily.last?.cost.total ?? 0
                    report["todayUnpricedTokens"] = daily.last?.unpricedTokens ?? 0
                    report["last30DaysTokens"] = daily.reduce(0) { $0 + $1.tokens.total }
                    report["pricingCheckedAt"] = pricing.checkedAt
                } catch { report["sessionsError"] = error.localizedDescription }
                do {
                    let limits = try await CodexUsageService.fetch(executable: CodexPaths.executable())
                    report["fiveHourUsedPercent"] = limits.fiveHour?.usedPercent ?? NSNull()
                    report["sevenDayUsedPercent"] = limits.sevenDay?.usedPercent ?? NSNull()
                } catch { report["usageError"] = error.localizedDescription }
                if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                    print(String(decoding: data, as: UTF8.self))
                }
                exit(report["usageError"] == nil && report["sessionsError"] == nil ? 0 : 1)
            }
            RunLoop.main.run()
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var subscriptions: Set<AnyCancellable> = []
    private var wakeObserver: NSObjectProtocol?
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityLabel("CodexMeter 用量仪表盘")
        }
        popover.behavior = .transient
        let controller = DashboardHostingController(rootView: DashboardView(model: model))
        controller.sizingOptions = [.preferredContentSize]
        popover.contentViewController = controller
        model.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateStatusItem() }
            .store(in: &subscriptions)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { await self?.model.refresh() } }
        updateStatusItem()
        model.start()
    }
    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            model.settingsVisible = false
            model.panelPresentationID = UUID()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            if let window = popover.contentViewController?.view.window {
                window.initialFirstResponder = nil
                window.makeKey()
                window.makeFirstResponder(nil)
                // AppKit can assign a control during the presentation layout pass.
                // Start on the window itself; Tab navigation still reaches the controls.
                DispatchQueue.main.async { [weak window] in
                    window?.makeFirstResponder(nil)
                }
            }
        }
    }
    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        button.title = ""
        switch model.menuMode {
        case "tokens":
            button.image = nil
            button.title = "↑ " + (model.sessionsUpdated == nil ? "—" : Display.tokens(model.today.tokens.total))
        case "cost":
            button.image = nil
            button.title = model.estimateCost ? Display.cost(model.today) : "费用已关闭"
        default:
            button.image = MenuBarGlyph.image(five: model.limits?.fiveHour, seven: model.limits?.sevenDay,
                                     onlyFive: model.menuMode == "five", style: model.menuStyle)
        }
        let five = model.limits?.fiveHour.map { "5h：已用 \(Int($0.usedPercent))%，剩余 \(Int($0.remainingPercent))%，\(Display.reset($0.resetDate))" } ?? "5h：暂无额度数据"
        let seven = model.limits?.sevenDay.map { "7d：已用 \(Int($0.usedPercent))%，剩余 \(Int($0.remainingPercent))%，\(Display.reset($0.resetDate))" } ?? "7d：暂无额度数据"
        let legend = model.menuStyle.legend(onlyFive: model.menuMode == "five")
        button.toolTip = "CodexMeter · 实色已用 / 淡色剩余\n\(legend)\n\(five)\n\(seven)" + (model.usageError == nil ? "" : "\n额度刷新失败，显示上次成功数据")
        button.setAccessibilityValue(button.toolTip)
    }
    func applicationWillTerminate(_ notification: Notification) {
        if let observer = wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
    }
}

@MainActor
private final class DashboardHostingController: NSHostingController<DashboardView> {
    override func viewDidAppear() {
        super.viewDidAppear()
        // Presentation can finish after the initial show() call and assign focus again.
        view.window?.initialFirstResponder = nil
        view.window?.makeFirstResponder(nil)
    }
}
