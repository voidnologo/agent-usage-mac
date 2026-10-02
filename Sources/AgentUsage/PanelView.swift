import AgentUsageCore
import AppKit
import SwiftUI

/// The dropdown panel: a port of Omarchy's Agents panel (Claude section) plus API-rate cost.
struct PanelView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
            HeroView(planLabel: store.planLabel, latestModel: store.summary.latestModel)
            if let status = store.statusText { StatusBox(text: status) }
            Separator()
            LimitsSection(limits: store.limits, now: store.now, isStale: store.limitsAreStale, fetchedAt: store.limitsFetchedAt)
            Separator()
            DaysSection(days: store.summary.days)
            Separator()
            ModelsSection(models: store.summary.models, windowDays: store.summary.windowDays)
            Separator()
            CostSection(summary: store.summary)
            Footer(store: store)
        }
        .padding(Theme.padding)
        .frame(width: Theme.panelWidth)
        .background(Theme.background)
        .foregroundStyle(Theme.foreground)
        .onAppear { store.panelOpened() }
    }
}

private struct Separator: View {
    var body: some View {
        Rectangle().fill(Theme.separator).frame(height: 1)
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(Theme.mono(Theme.Size.caption, weight: .bold))
            .foregroundStyle(Theme.header)
    }
}

private struct HeroView: View {
    let planLabel: String?
    let latestModel: String?

    var body: some View {
        HStack(spacing: 14) {
            if let mark = ClaudeMark.color {
                Image(nsImage: mark).resizable().frame(width: 24, height: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Claude Code").font(Theme.mono(Theme.Size.title, weight: .bold))
                Text(subtitle)
                    .font(Theme.mono(Theme.Size.caption, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.dim)
            }
        }
    }

    /// Plan, then the model the latest message used, e.g. `MAX 5X · OPUS 5.5`.
    private var subtitle: String {
        [planLabel ?? "Subscription", latestModel].compactMap { $0 }.joined(separator: " · ").uppercased()
    }
}

private struct StatusBox: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.mono(Theme.Size.caption))
            .foregroundStyle(Theme.dim)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.urgent.opacity(0.10))
            .overlay(Rectangle().stroke(Theme.urgent.opacity(0.35), lineWidth: 1))
    }
}

/// A rounded 4pt meter: foreground fill, urgent once the window is 90% used.
private struct Meter: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(color).frame(width: geometry.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 4)
    }
}

private struct LimitsSection: View {
    let limits: [LimitRow]
    let now: Date
    let isStale: Bool
    let fetchedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Limits")
            if limits.isEmpty {
                Text("No limit data yet").font(Theme.mono(Theme.Size.caption)).foregroundStyle(Theme.dim)
            }
            ForEach(limits) { LimitRowView(limit: $0, now: now) }
        }
        .opacity(isStale ? 0.5 : 1)
        .help(staleHelp)
    }

    private var staleHelp: String {
        guard isStale, let fetchedAt else { return "" }
        return "As of \(Format.countdown(seconds: now.timeIntervalSince(fetchedAt))) ago"
    }
}

private struct LimitRowView: View {
    let limit: LimitRow
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(limit.title).font(Theme.mono(Theme.Size.body))
                Spacer()
                Text("\(limit.usedPercent)%")
                    .font(Theme.mono(Theme.Size.caption))
                    .foregroundStyle(limit.isCritical ? Theme.urgent : Theme.foreground)
            }
            Meter(fraction: limit.usedFraction, color: limit.isCritical ? Theme.urgent : Theme.foreground)
            Text(resetText).font(Theme.mono(Theme.Size.caption)).foregroundStyle(Theme.dim)
        }
        .help("\(limit.leftPercent)% left")
    }

    private var resetText: String {
        guard let resetsAt = limit.resetsAt else { return "\(limit.leftPercent)% left" }
        return "\(limit.leftPercent)% left · resets in \(Format.countdown(seconds: resetsAt.timeIntervalSince(now)))"
    }
}

private struct DaysSection: View {
    let days: [DayBucket]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Tokens by day")
            ForEach(days) { DayRowView(day: $0, peak: peak) }
        }
    }

    private var peak: Int { max(1, days.map(\.tokens).max() ?? 1) }
}

private struct DayRowView: View {
    let day: DayBucket
    let peak: Int

    var body: some View {
        HStack(spacing: 0) {
            Text(day.label)
                .font(Theme.mono(Theme.Size.caption, weight: day.isToday ? .bold : .regular))
                .foregroundStyle(day.isToday ? Theme.foreground : Theme.dim)
                .frame(width: 52, alignment: .leading)
            Meter(fraction: Double(day.tokens) / Double(peak), color: Theme.foreground.opacity(day.isToday ? 1 : 0.55))
                .padding(.leading, 8)
                .padding(.trailing, 10)
            Text(Format.tokens(day.tokens))
                .font(Theme.mono(Theme.Size.caption, weight: .bold))
                .frame(width: 52, alignment: .trailing)
            Text(Format.usd(day.cost))
                .font(Theme.mono(Theme.Size.caption))
                .foregroundStyle(Theme.dim)
                .frame(width: 64, alignment: .trailing)
        }
        .help("\(day.dateLabel) · \(Format.tokens(day.tokens)) tokens · \(Format.usd(day.cost)) at API rates")
    }
}

private struct ModelsSection: View {
    let models: [ModelBucket]
    let windowDays: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Tokens by model · \(windowDays)d")
            if models.isEmpty {
                Text("No usage yet").font(Theme.mono(Theme.Size.caption)).foregroundStyle(Theme.dim)
            }
            ForEach(models) { ModelRowView(model: $0, topTotal: models.first?.usage.total ?? 1) }
        }
    }
}

/// Omarchy draws the share as a translucent fill behind the row rather than a separate bar.
private struct ModelRowView: View {
    let model: ModelBucket
    let topTotal: Int

    var body: some View {
        HStack {
            Text(model.name).font(Theme.mono(Theme.Size.bodySmall))
            Spacer()
            Text(valueText).font(Theme.mono(Theme.Size.bodySmall, weight: .bold)).foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(alignment: .leading) { shareFill }
        .help(breakdown)
    }

    private var shareFill: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.foreground.opacity(0.05))
                Rectangle()
                    .fill(Theme.foreground.opacity(0.14))
                    .frame(width: geometry.size.width * Double(model.usage.total) / Double(max(1, topTotal)))
            }
        }
    }

    private var valueText: String {
        let tokens = Format.tokens(model.usage.total)
        return model.cost.map { "\(tokens) · \(Format.usd($0))" } ?? tokens
    }

    private var breakdown: String {
        let usage = model.usage
        return "In \(Format.tokens(usage.input)) · out \(Format.tokens(usage.output)) · cache read \(Format.tokens(usage.cacheRead)) · cache write \(Format.tokens(usage.cacheWrite))"
    }
}

private struct CostSection: View {
    let summary: UsageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Cost · API-rate estimate")
            costRow("Today", value: Format.usd(summary.todayCost))
            costRow("\(summary.windowDays) days", value: "\(Format.usd(summary.windowCost)) · \(Format.tokens(summary.windowTokens))")
            if summary.unpricedTokens > 0 {
                Text("\(Format.tokens(summary.unpricedTokens)) tokens from unpriced models not included")
                    .font(Theme.mono(Theme.Size.caption))
                    .foregroundStyle(Theme.dim)
            }
        }
        .help("What these tokens would cost on the Anthropic API. Your subscription is not billed this way.")
    }

    private func costRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).font(Theme.mono(Theme.Size.body))
            Spacer()
            Text(value).font(Theme.mono(Theme.Size.body, weight: .bold))
        }
    }
}

private struct Footer: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        HStack(spacing: 12) {
            Text(updatedText).font(Theme.mono(Theme.Size.caption)).foregroundStyle(Theme.dim)
            Spacer()
            footerButton("Refresh") { store.refreshAll() }
            footerButton("Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(.top, 2)
    }

    private var updatedText: String {
        guard let fetchedAt = store.limitsFetchedAt else { return "Not updated yet" }
        let age = store.now.timeIntervalSince(fetchedAt)
        return age < 60 ? "Updated just now" : "Updated \(Format.countdown(seconds: age)) ago"
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(Theme.mono(Theme.Size.caption, weight: .bold)).foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
    }
}
