import Foundation

/// One plan limit window: the session (5h), the weekly window, or a model-scoped weekly window.
public struct LimitRow: Sendable, Equatable, Identifiable {
    public var id: String { title }
    public let title: String
    /// Share of the window used, 0...1.
    public let usedFraction: Double
    public let resetsAt: Date?

    public init(title: String, usedFraction: Double, resetsAt: Date?) {
        self.title = title
        self.usedFraction = usedFraction
        self.resetsAt = resetsAt
    }

    public var usedPercent: Int { Int((usedFraction * 100).rounded()) }
    public var leftPercent: Int { 100 - usedPercent }
    /// The Omarchy widget turns a window red at 90% used.
    public var isCritical: Bool { usedFraction >= 0.9 }
}

public enum LimitsError: Error, Equatable {
    case rateLimited(retryAfterSeconds: Int?)
    case unauthorized
    case httpStatus(Int)
    case malformedResponse
    case transport(String)

    public var message: String {
        switch self {
        case .rateLimited(let retryAfter):
            let wait = retryAfter.map { " (retry after \($0)s)" } ?? ""
            return "Anthropic is rate limiting usage checks right now\(wait)"
        case .unauthorized: return "Sign-in rejected. Open Claude Code to sign in again."
        case .httpStatus(let code): return "Usage endpoint returned status \(code)"
        case .malformedResponse: return "Usage endpoint returned an unexpected response"
        case .transport(let detail): return "Couldn't reach Anthropic: \(detail)"
        }
    }
}

public enum LimitsParser {
    /// Reads the `/api/oauth/usage` payload. `utilization` arrives as a percentage (64.0 = 64%).
    public static func parse(_ data: Data) throws -> [LimitRow] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LimitsError.malformedResponse
        }
        var rows: [LimitRow] = []
        if let session = window(root["five_hour"], title: "Session") { rows.append(session) }
        let weeklyPayload = (root["seven_day_oauth_apps"] as? [String: Any]) ?? (root["seven_day"] as? [String: Any])
        if let weekly = window(weeklyPayload, title: "Weekly") { rows.append(weekly) }
        rows.append(contentsOf: scopedRows(root["limits"] as? [[String: Any]] ?? []))
        return rows
    }

    private static func window(_ payload: Any?, title: String) -> LimitRow? {
        guard let dict = payload as? [String: Any], let utilization = (dict["utilization"] as? NSNumber)?.doubleValue else {
            return nil
        }
        return LimitRow(title: title, usedFraction: fraction(fromPercent: utilization), resetsAt: date(dict["resets_at"]))
    }

    /// Model-scoped windows such as "Fable Weekly" come only from the `limits` array, marked by `scope.model`.
    private static func scopedRows(_ limits: [[String: Any]]) -> [LimitRow] {
        var seen = Set<String>()
        return limits.compactMap { limit in
            guard let scope = limit["scope"] as? [String: Any],
                  let model = scope["model"] as? [String: Any],
                  let name = (model["display_name"] as? String) ?? (model["id"] as? String),
                  let percent = (limit["percent"] as? NSNumber)?.doubleValue else { return nil }
            let title = "\(name) \(windowName(kind: limit["kind"] as? String ?? ""))"
            guard seen.insert(title).inserted else { return nil }
            return LimitRow(title: title, usedFraction: fraction(fromPercent: percent), resetsAt: date(limit["resets_at"]))
        }
    }

    static func windowName(kind: String) -> String {
        let lowered = kind.lowercased()
        if lowered.contains("month") { return "Monthly" }
        if lowered.contains("week") || lowered.contains("day") { return "Weekly" }
        return "Session"
    }

    private static func fraction(fromPercent percent: Double) -> Double {
        min(1, max(0, percent / 100))
    }

    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        return Timestamp.parse(text)
    }
}

public enum LimitsClient {
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")

    /// Fetches the plan limits with the Claude Code OAuth token; 10s timeout like the Omarchy collector.
    public static func fetch(token: String, session: URLSession = .shared) async throws -> [LimitRow] {
        guard let endpoint else { throw LimitsError.malformedResponse }
        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LimitsError.transport(error.localizedDescription)
        }
        try check(response)
        return try LimitsParser.parse(data)
    }

    private static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw LimitsError.malformedResponse }
        switch http.statusCode {
        case 200..<300: return
        case 401, 403: throw LimitsError.unauthorized
        case 429: throw LimitsError.rateLimited(retryAfterSeconds: http.value(forHTTPHeaderField: "retry-after").flatMap { Int($0) })
        default: throw LimitsError.httpStatus(http.statusCode)
        }
    }
}

public enum Timestamp {
    /// Transcripts write `2026-10-02T15:03:47.161Z`; the usage endpoint writes microseconds and an offset.
    public static func parse(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle()) { return date }
        return parseTrimmingFraction(text)
    }

    /// ISO8601FormatStyle rejects six fractional digits, so drop the fraction and parse again.
    private static func parseTrimmingFraction(_ text: String) -> Date? {
        guard let dot = text.firstIndex(of: ".") else { return nil }
        let afterDot = text[text.index(after: dot)...]
        let zoneStart = afterDot.firstIndex { !$0.isNumber } ?? afterDot.endIndex
        let trimmed = String(text[..<dot]) + String(afterDot[zoneStart...])
        return try? Date(trimmed, strategy: Date.ISO8601FormatStyle())
    }
}
