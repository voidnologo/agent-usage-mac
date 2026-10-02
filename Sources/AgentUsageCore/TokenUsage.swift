import Foundation

/// Token counts for one assistant message, split the way the API bills them.
public struct TokenUsage: Sendable, Equatable {
    public var input: Int
    public var output: Int
    public var cacheRead: Int
    public var cacheWrite5m: Int
    public var cacheWrite1h: Int

    public init(input: Int = 0, output: Int = 0, cacheRead: Int = 0, cacheWrite5m: Int = 0, cacheWrite1h: Int = 0) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
    }

    public var cacheWrite: Int { cacheWrite5m + cacheWrite1h }

    /// Every token the message moved, cache traffic included; this is the number the Omarchy widget charts.
    public var total: Int { input + output + cacheRead + cacheWrite }

    public static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite5m: lhs.cacheWrite5m + rhs.cacheWrite5m,
            cacheWrite1h: lhs.cacheWrite1h + rhs.cacheWrite1h
        )
    }
}

/// One deduplicated assistant message from a Claude Code transcript.
public struct UsageEntry: Sendable, Equatable {
    public let timestamp: Date
    public let model: String
    public let usage: TokenUsage
    public let cost: Double?

    public init(timestamp: Date, model: String, usage: TokenUsage) {
        self.timestamp = timestamp
        self.model = model
        self.usage = usage
        self.cost = Pricing.cost(of: usage, model: model)
    }
}
