import SwiftUI
import Charts
import CodexMeterCore

private let accent = Color(red: 0.28, green: 0.47, blue: 0.96)

struct DashboardView: View {
    @ObservedObject var model: AppModel
    @State private var showCost = false
    @State private var hoveredDay: Date?
    @State private var summaryHeight: CGFloat = 440
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if model.settingsVisible { settings }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        VStack(alignment: .leading, spacing: 22) {
                            limits
                            Divider()
                            today
                        }
                        .padding(20)
                        .fixedSize(horizontal: false, vertical: true)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(key: SummaryHeightKey.self, value: geometry.size.height)
                            }
                        }
                        Divider()
                        history.padding(20)
                    }
                }
                .frame(height: summaryHeight)
                .id(model.panelPresentationID)
                .onPreferenceChange(SummaryHeightKey.self) { height in
                    guard height > 0 else { return }
                    let proposed = min(520, ceil(height))
                    if abs(summaryHeight - proposed) > 0.5 { summaryHeight = proposed }
                }
            }
            Divider()
            HStack {
                Label(model.settingsVisible ? "本地 Codex 数据" : "下滑查看每日图表",
                      systemImage: model.settingsVisible ? "lock.shield" : "chevron.down")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
                    .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(.secondary)
            }.padding(.horizontal, 20).padding(.vertical, 11)
        }
        .frame(width: 380)
        .background(.regularMaterial)
        .tint(accent)
    }
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(accent.opacity(0.12))
                Image(systemName: "chart.bar.xaxis").font(.system(size: 18, weight: .semibold)).foregroundStyle(accent)
            }.frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text("CodexMeter").font(.system(size: 16, weight: .semibold))
                TimelineView(.periodic(from: .now, by: 30)) { _ in
                    if model.refreshing { Text("正在刷新…").font(.system(size: 11)).foregroundStyle(.secondary) }
                    else if let date = model.usageUpdated {
                        Text("额度更新于 \(date.formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    } else { Text("Codex 用量仪表盘").font(.system(size: 11)).foregroundStyle(.secondary) }
                }
            }
            Spacer()
            Button { Task { await model.refresh() } } label: {
                Image(systemName: "arrow.clockwise").frame(width: 24, height: 24)
            }.buttonStyle(.plain).disabled(model.refreshing).help("刷新额度和 Token")
            Button { model.settingsVisible.toggle() } label: {
                Image(systemName: model.settingsVisible ? "xmark" : "gearshape").frame(width: 24, height: 24)
            }.buttonStyle(.plain).help(model.settingsVisible ? "返回仪表盘" : "设置")
        }.padding(20)
    }
    private var limits: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                sectionTitle("使用额度")
                Spacer()
                if let plan = model.limits?.codex?.planType {
                    Text(plan.uppercased()).font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(accent.opacity(0.1), in: Capsule()).foregroundStyle(accent)
                }
            }
            VStack(spacing: 10) {
                LimitRow(title: "5 小时", symbol: "clock", window: model.limits?.fiveHour)
                LimitRow(title: "7 天", symbol: "calendar", window: model.limits?.sevenDay)
            }
            if let error = model.usageError { errorNote(error + (model.limits == nil ? "" : "（上方为上次成功数据）")) }
        }
    }
    private var today: some View {
        VStack(alignment: .leading, spacing: 15) {
            sectionTitle("今日 · \(Date().formatted(.dateTime.month().day()))")
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.sessionsUpdated == nil ? "—" : Display.tokens(model.today.tokens.total))
                        .font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("Tokens").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if model.estimateCost {
                    Button { showCost.toggle() } label: {
                        VStack(alignment: .trailing, spacing: 5) {
                            Text(Display.cost(model.today)).font(.system(size: 26, weight: .medium, design: .rounded)).monospacedDigit()
                            HStack(spacing: 3) {
                                Text("Estimated API Cost")
                                Image(systemName: "chevron.down").font(.system(size: 8))
                            }.font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.plain).popover(isPresented: $showCost) { costDetail.padding(18).frame(width: 280) }
                }
            }
            HStack {
                tokenColumn("Input", value: model.today.tokens.input)
                Spacer()
                tokenColumn("Cached", value: model.today.tokens.cached)
                Spacer()
                tokenColumn("Output", value: model.today.tokens.output)
            }.padding(13).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            if model.estimateCost && !model.today.isCostComplete {
                Text("\(Display.tokens(model.today.unpricedTokens)) Token 暂无价格，金额仅包含已计价部分。")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                    .help(model.today.unpricedModels.sorted().joined(separator: "、"))
            }
            if let error = model.sessionError { errorNote(error) }
        }
    }
    private var history: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionTitle("每日 TOKENS")
                Spacer()
                Picker("时间范围", selection: $model.selectedDays) {
                    Text("7D").tag(7); Text("14D").tag(14); Text("30D").tag(30)
                }.pickerStyle(.segmented).frame(width: 147).labelsHidden()
            }
            Chart(model.visibleDays) { day in
                BarMark(x: .value("日期", day.date, unit: .day), y: .value("Tokens", day.tokens.total))
                    .foregroundStyle(hoveredDay.map { Calendar.current.isDate($0, inSameDayAs: day.date) } == true ? accent : accent.opacity(0.75))
                    .cornerRadius(3)
                    .accessibilityLabel(day.date.formatted(date: .abbreviated, time: .omitted))
                    .accessibilityValue("\(day.tokens.total) Tokens，\(Display.cost(day))")
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.07))
                    AxisValueLabel { if let number = value.as(Int.self) { Text(Display.tokens(number)).font(.system(size: 9)) } }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: model.selectedDays == 7 ? 1 : model.selectedDays == 14 ? 3 : 6)) { _ in
                    AxisValueLabel(format: .dateTime.day(), centered: true).font(.system(size: 9))
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let point):
                                guard let frame = proxy.plotFrame else { return }
                                let x = point.x - geometry[frame].origin.x
                                hoveredDay = proxy.value(atX: x, as: Date.self)
                            case .ended: hoveredDay = nil
                            }
                        }
                }
            }
            .frame(height: 142)
            if let date = hoveredDay, let day = model.visibleDays.first(where: { Calendar.current.isDate($0.date, inSameDayAs: date) }) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(day.date.formatted(date: .abbreviated, time: .omitted)).fontWeight(.medium)
                        Spacer(); Text("\(Display.tokens(day.tokens.total)) Tokens")
                    }
                    Text("Input \(Display.tokens(day.tokens.input)) · Cached \(Display.tokens(day.tokens.cached)) · Output \(Display.tokens(day.tokens.output))")
                    if model.estimateCost { Text("Estimated API Cost  \(Display.cost(day))") }
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            }
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("最近 \(model.selectedDays) 天").font(.system(size: 10)).foregroundStyle(.secondary)
                    Text("\(Display.tokens(model.period.tokens.total)) Tokens").font(.system(size: 14, weight: .semibold)).monospacedDigit()
                }
                Spacer()
                if model.estimateCost { Text(Display.cost(model.period)).font(.system(size: 16, weight: .medium, design: .rounded)).monospacedDigit() }
            }.padding(13).background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            if model.sessionsUpdated != nil && model.period.tokens.total == 0 {
                Text("这段时间还没有 Token 使用记录。").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.onChange(of: model.selectedDays) { _, _ in hoveredDay = nil }
    }
    private var costDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Estimated API Cost").font(.headline)
            costRow("普通输入 / 写缓存", value: model.today.cost.input)
            costRow("缓存输入", value: model.today.cost.cached)
            costRow("输出", value: model.today.cost.output)
            Divider()
            HStack { Text("合计"); Spacer(); Text(Display.cost(model.today)).fontWeight(.semibold) }
            Text("按模型 API 单价估算，不是 ChatGPT 订阅账单。Cached 已包含在 Input 中，Total = Input + Output。")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            if !model.today.isCostComplete {
                Text("未计价模型：\(model.today.unpricedModels.sorted().joined(separator: "、"))")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.font(.system(size: 12))
    }
    private var settings: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("设置").font(.system(size: 18, weight: .semibold))
                Toggle("登录时启动", isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin))
                if let error = model.loginError { errorNote(error) }
                Picker("刷新间隔", selection: $model.refreshMinutes) {
                    Text("1 分钟").tag(1); Text("5 分钟").tag(5); Text("15 分钟").tag(15)
                }
                Picker("菜单栏", selection: $model.menuMode) {
                    Text("单色用量条 · 5h + 7d").tag("both")
                    Text("单色用量条 · 5h").tag("five")
                    Text("今日 Tokens").tag("tokens")
                    Text("今日估算费用").tag("cost")
                }
                Divider()
                Toggle("计算 Estimated API Cost", isOn: $model.estimateCost)
                VStack(alignment: .leading, spacing: 5) {
                    Link("OpenAI 模型价格 ↗", destination: URL(string: "https://developers.openai.com/api/docs/pricing")!)
                    Text("价格表核对：\(model.pricing?.checkedAt ?? "未加载")\n默认按 Standard 费率估算；日志提供时计入 Fast / Flex 和长上下文倍率。未知价格不按零元计算。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Divider()
                sectionTitle("数据来源")
                Label("\(model.fileCount) 个 session 文件", systemImage: model.sessionsUpdated == nil ? "folder" : "checkmark.circle.fill")
                    .font(.system(size: 12)).foregroundStyle(model.sessionsUpdated == nil ? .secondary : .primary)
                Text(CodexPaths.home.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                Text("包含 sessions 和 archived_sessions；按系统本地时区统计日期。Token 数据仅在本机解析。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 7) {
                    Text("Codex CLI 路径（留空自动查找）").font(.system(size: 11))
                    TextField("/path/to/codex", text: $model.cliPath).textFieldStyle(.roundedBorder)
                    Button("重新读取数据") { Task { await model.refresh() } }.disabled(model.refreshing)
                }
                if !model.warnings.isEmpty { errorNote("\(model.warnings.count) 个文件读取提示").help(model.warnings.joined(separator: "\n")) }
            }.padding(20)
        }.frame(height: summaryHeight)
    }
    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 10, weight: .semibold)).tracking(1.1).foregroundStyle(.secondary)
    }
    private func tokenColumn(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(Display.tokens(value)).font(.system(size: 14, weight: .medium)).monospacedDigit()
        }.help(title == "Cached" ? "缓存输入是 Input 的子集" : "\(value.formatted()) Tokens")
    }
    private func costRow(_ title: String, value: Double) -> some View {
        HStack { Text(title); Spacer(); Text(String(format: "$%.4f", value)).monospacedDigit() }
    }
    private func errorNote(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.circle").font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

private struct SummaryHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct LimitRow: View {
    let title: String
    let symbol: String
    let window: RateWindow?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                HStack(spacing: 7) {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    Text(title).font(.system(size: 12, weight: .semibold))
                }
                Spacer()
                if let window {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(window.remainingPercent.rounded()))%")
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("剩余").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                } else {
                    Text("未提供").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            QuotaBar(fraction: window?.usedFraction)
            TimelineView(.periodic(from: .now, by: 60)) { context in
                HStack(alignment: .top, spacing: 5) {
                    if let window {
                        HStack(spacing: 5) {
                            Circle().fill(MeterPalette.used).frame(width: 4, height: 4)
                            Text("已用 \(Int(min(100, max(0, window.usedPercent)).rounded()))%")
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(window.map { Display.reset($0.resetDate, now: context.date) } ?? "服务端未提供该周期额度")
                        if let date = window?.resetDate {
                            Text("重置于 \(Display.resetTime(date, now: context.date))")
                                .monospacedDigit()
                        }
                    }
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            }.help(window?.resetDate?.formatted(date: .complete, time: .standard) ?? "")
        }
        .padding(14)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.055), lineWidth: 0.5))
    }
}

private struct QuotaBar: View {
    let fraction: Double?
    var body: some View {
        GeometryReader { geometry in
            if let fraction {
                let gap: CGFloat = fraction > 0 && fraction < 1 ? 3 : 0
                let width = max(0, geometry.size.width - gap)
                HStack(spacing: gap) {
                    if fraction > 0 {
                        Capsule().fill(LinearGradient(
                            colors: [MeterPalette.used.opacity(0.82), MeterPalette.used],
                            startPoint: .leading, endPoint: .trailing
                        )).frame(width: width * fraction)
                    }
                    if fraction < 1 {
                        Capsule().fill(LinearGradient(
                            colors: [MeterPalette.remaining, MeterPalette.remaining.opacity(0.72)],
                            startPoint: .leading, endPoint: .trailing
                        )).frame(width: width * (1 - fraction))
                    }
                }
            } else {
                Capsule().fill(Color.secondary.opacity(0.12))
            }
        }
        .frame(height: 8)
        .animation(.easeInOut(duration: 0.25), value: fraction)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("使用额度")
        .accessibilityValue(fraction.map { "已用 \(Int(($0 * 100).rounded()))%，剩余 \(Int(((1 - $0) * 100).rounded()))%" } ?? "未提供")
    }
}
