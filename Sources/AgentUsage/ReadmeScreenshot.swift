import AgentUsageCore
import AppKit
import SwiftUI

/// Renders the README screenshot from invented sample data, so publishing it shows no one's real usage.
/// Regenerate with `swift run AgentUsage --render-readme-screenshot docs/screenshot.png`.
@MainActor
enum ReadmeScreenshot {
    static func render(to path: String) -> Bool {
        let renderer = ImageRenderer(content: Scene(store: sampleStore()))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return false }
        do {
            try png.write(to: URL(fileURLWithPath: path))
            return true
        } catch {
            FileHandle.standardError.write(Data("Couldn't write \(path): \(error.localizedDescription)\n".utf8))
            return false
        }
    }

    private static func sampleStore() -> UsageStore {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 2, hour: 15)) ?? Date()
        let limits = [
            LimitRow(title: "Session", usedFraction: 0.23, resetsAt: now.addingTimeInterval(38 * 60)),
            LimitRow(title: "Weekly", usedFraction: 0.08, resetsAt: now.addingTimeInterval(5 * 86_400 + 13 * 3600)),
            LimitRow(title: "Fable Weekly", usedFraction: 0.02, resetsAt: now.addingTimeInterval(5 * 86_400 + 13 * 3600)),
        ]
        let summary = UsageSummary.build(entries: sampleEntries(now: now, calendar: calendar), now: now, calendar: calendar)
        return UsageStore.snapshot(limits: limits, planLabel: "Pro", summary: summary, now: now)
    }

    /// Tokens per day, oldest first, ending today.
    private static let dailyTokens = [4_800_000, 0, 34_700_000, 1_400_000, 7_700_000, 3_200_000, 12_100_000]
    /// Listed so the last model is the one the header reports as most recent.
    private static let modelShares: [(model: String, share: Double)] = [
        ("claude-opus-5-5", 0.22), ("claude-haiku-4-5", 0.06), ("claude-fable-5-1", 0.04), ("claude-sonnet-5-5", 0.68),
    ]

    private static func sampleEntries(now: Date, calendar: Calendar) -> [UsageEntry] {
        let today = calendar.startOfDay(for: now)
        return dailyTokens.enumerated().flatMap { index, tokens in
            let dayOffset = index - (dailyTokens.count - 1)
            let day = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
            let base = dayOffset == 0 ? now.addingTimeInterval(-3600) : day.addingTimeInterval(11 * 3600)
            return modelShares.enumerated().map { order, entry in
                UsageEntry(timestamp: base.addingTimeInterval(Double(order) * 60), model: entry.model, usage: typicalSplit(Int(Double(tokens) * entry.share)))
            }
        }
    }

    /// Claude Code traffic is mostly cache reads; this split keeps the sample costs realistic.
    private static func typicalSplit(_ total: Int) -> TokenUsage {
        let value = Double(total)
        return TokenUsage(
            input: Int(value * 0.005),
            output: Int(value * 0.025),
            cacheRead: Int(value * 0.90),
            cacheWrite5m: Int(value * 0.07)
        )
    }

    /// The panel under a menu bar item, on a desktop-like backdrop.
    private struct Scene: View {
        let store: UsageStore

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                menuBarItem
                PanelView(store: store)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.18), lineWidth: 1))
                    .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
            }
            .padding(28)
            .background(LinearGradient(colors: [Color(hex: 0x30375A), Color(hex: 0x1B1F33)], startPoint: .top, endPoint: .bottom))
        }

        private var menuBarItem: some View {
            HStack(spacing: 5) {
                if let mark = ClaudeMark.template {
                    Image(nsImage: mark).renderingMode(.template).resizable().frame(width: 14, height: 14)
                }
                Text("23% · 8%").font(.system(size: 13, weight: .medium).monospacedDigit())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.18)))
        }
    }
}
