import Foundation

public struct DayBucket: Sendable, Equatable, Identifiable {
    public var id: Date { day }
    public let day: Date
    public let label: String
    public let dateLabel: String
    public let isToday: Bool
    public let tokens: Int
    public let cost: Double
}

public struct ModelBucket: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let usage: TokenUsage
    /// Nil when none of the model's messages could be priced.
    public let cost: Double?
}

/// What the panel shows below the limits: seven days of tokens and cost, and the top models.
public struct UsageSummary: Sendable, Equatable {
    public let days: [DayBucket]
    public let models: [ModelBucket]
    public let todayCost: Double
    public let windowCost: Double
    public let windowTokens: Int
    public let windowDays: Int
    public let latestModel: String?
    /// Tokens from models missing from the price table, so the panel can say the cost is a floor.
    public let unpricedTokens: Int

    public static let empty = UsageSummary(
        days: [], models: [], todayCost: 0, windowCost: 0, windowTokens: 0, windowDays: 30, latestModel: nil, unpricedTokens: 0
    )

    /// Buckets entries by local calendar day, the way the Omarchy widget does.
    public static func build(
        entries: [UsageEntry],
        now: Date = Date(),
        calendar: Calendar = .current,
        windowDays: Int = 30,
        modelLimit: Int = 4
    ) -> UsageSummary {
        let today = calendar.startOfDay(for: now)
        let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: today) ?? today
        let inWindow = entries.filter { $0.timestamp >= windowStart && $0.timestamp <= now }
        let days = dayBuckets(inWindow, today: today, calendar: calendar)
        return UsageSummary(
            days: days,
            models: modelBuckets(inWindow, limit: modelLimit),
            todayCost: days.last?.cost ?? 0,
            windowCost: inWindow.reduce(0) { $0 + ($1.cost ?? 0) },
            windowTokens: inWindow.reduce(0) { $0 + $1.usage.total },
            windowDays: windowDays,
            latestModel: inWindow.max { $0.timestamp < $1.timestamp }.map { Format.modelName($0.model) },
            unpricedTokens: inWindow.filter { $0.cost == nil }.reduce(0) { $0 + $1.usage.total }
        )
    }

    private static func dayBuckets(_ entries: [UsageEntry], today: Date, calendar: Calendar) -> [DayBucket] {
        let byDay = Dictionary(grouping: entries) { calendar.startOfDay(for: $0.timestamp) }
        let weekday = DateFormatter()
        weekday.locale = Locale(identifier: "en_US")
        weekday.calendar = calendar
        weekday.timeZone = calendar.timeZone
        weekday.dateFormat = "EEE"
        let shortDate = DateFormatter()
        shortDate.locale = Locale(identifier: "en_US")
        shortDate.calendar = calendar
        shortDate.timeZone = calendar.timeZone
        shortDate.dateFormat = "EEE M/d"
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let dayEntries = byDay[day] ?? []
            return DayBucket(
                day: day,
                label: offset == 0 ? "Today" : weekday.string(from: day),
                dateLabel: shortDate.string(from: day),
                isToday: offset == 0,
                tokens: dayEntries.reduce(0) { $0 + $1.usage.total },
                cost: dayEntries.reduce(0) { $0 + ($1.cost ?? 0) }
            )
        }
    }

    /// Groups by display name so dated snapshots of one model (`…-20251001`) share a row.
    private static func modelBuckets(_ entries: [UsageEntry], limit: Int) -> [ModelBucket] {
        let byName = Dictionary(grouping: entries) { Format.modelName($0.model) }
        let buckets = byName.map { name, group in
            let priced = group.compactMap(\.cost)
            return ModelBucket(
                name: name,
                usage: group.reduce(TokenUsage()) { $0 + $1.usage },
                cost: priced.isEmpty ? nil : priced.reduce(0, +)
            )
        }
        return Array(buckets.sorted { $0.usage.total > $1.usage.total }.prefix(limit))
    }
}
