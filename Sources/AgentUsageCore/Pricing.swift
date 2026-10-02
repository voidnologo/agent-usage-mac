import Foundation

/// Anthropic first-party API rates in USD per million tokens.
public struct ModelPrice: Sendable, Equatable {
    public let input: Double
    public let output: Double
    public let cacheRead: Double

    /// A 5-minute cache write bills at 1.25× input.
    public var cacheWrite5m: Double { input * 1.25 }
    /// A 1-hour cache write bills at 2× input.
    public var cacheWrite1h: Double { input * 2 }
}

/// Prices Claude Code transcript usage at API rates, the same "API-rate estimate" CodexBar shows.
/// A subscription is not billed this way; the figure answers "what would this have cost on the API".
public enum Pricing {
    /// Model ids are matched exactly after normalization, so an unreleased model is reported as unpriced
    /// rather than silently priced as its nearest sibling.
    static let table: [String: ModelPrice] = [
        "claude-fable-5-1": ModelPrice(input: 10, output: 50, cacheRead: 0.25),
        "claude-mythos-5-1": ModelPrice(input: 10, output: 50, cacheRead: 0.25),
        "claude-fable-5": ModelPrice(input: 10, output: 50, cacheRead: 1.0),
        "claude-opus-5-5": ModelPrice(input: 4, output: 20, cacheRead: 0.20),
        "claude-opus-5": ModelPrice(input: 5, output: 25, cacheRead: 0.50),
        "claude-opus-4-8": ModelPrice(input: 5, output: 25, cacheRead: 0.50),
        "claude-opus-4-7": ModelPrice(input: 5, output: 25, cacheRead: 0.50),
        "claude-opus-4-6": ModelPrice(input: 5, output: 25, cacheRead: 0.50),
        "claude-opus-4-5": ModelPrice(input: 5, output: 25, cacheRead: 0.50),
        "claude-opus-4-1": ModelPrice(input: 15, output: 75, cacheRead: 1.50),
        "claude-opus-4": ModelPrice(input: 15, output: 75, cacheRead: 1.50),
        "claude-sonnet-5-5": ModelPrice(input: 2, output: 10, cacheRead: 0.20),
        "claude-sonnet-5": ModelPrice(input: 2, output: 10, cacheRead: 0.20),
        "claude-sonnet-4-6": ModelPrice(input: 3, output: 15, cacheRead: 0.30),
        "claude-sonnet-4-5": ModelPrice(input: 3, output: 15, cacheRead: 0.30),
        "claude-sonnet-4": ModelPrice(input: 3, output: 15, cacheRead: 0.30),
        "claude-haiku-4-5": ModelPrice(input: 1, output: 5, cacheRead: 0.10),
        "claude-3-5-haiku": ModelPrice(input: 0.8, output: 4, cacheRead: 0.08),
    ]

    /// Strips provider prefixes, context-window tags and date suffixes so `anthropic.claude-opus-4-1-20250805`
    /// and `claude-opus-5-5[1m]` resolve to their table keys.
    public static func normalize(_ modelID: String) -> String {
        var id = modelID.trimmingCharacters(in: .whitespaces)
        if let bracket = id.firstIndex(of: "[") { id = String(id[..<bracket]) }
        if let dotted = id.range(of: "claude-", options: .backwards), dotted.lowerBound != id.startIndex {
            id = String(id[dotted.lowerBound...])
        }
        var parts = id.split(separator: "-").map(String.init)
        if let last = parts.last, last.hasPrefix("v"), last.contains(":") { parts.removeLast() }
        if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) { parts.removeLast() }
        return parts.joined(separator: "-")
    }

    public static func price(for modelID: String) -> ModelPrice? {
        table[normalize(modelID)]
    }

    /// Cost of one assistant message, or nil when the model is not in the table.
    public static func cost(of usage: TokenUsage, model: String) -> Double? {
        guard let price = price(for: model) else { return nil }
        let dollars = Double(usage.input) * price.input
            + Double(usage.output) * price.output
            + Double(usage.cacheRead) * price.cacheRead
            + Double(usage.cacheWrite5m) * price.cacheWrite5m
            + Double(usage.cacheWrite1h) * price.cacheWrite1h
        return dollars / 1_000_000
    }
}
