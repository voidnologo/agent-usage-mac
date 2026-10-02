// Behaviour checks for AgentUsageCore. XCTest and Swift Testing need a full Xcode install, so this runner
// works with Command Line Tools alone: `swift run AgentUsageChecks` (add `--live` to also scan real data).
import Foundation
import AgentUsageCore

nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var passes = 0

func expect(_ condition: @autoclosure () -> Bool, _ name: String, file: String = #fileID, line: Int = #line) {
    if condition() {
        passes += 1
    } else {
        failures += 1
        print("FAIL \(name) (\(file):\(line))")
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ name: String, file: String = #fileID, line: Int = #line) {
    expect(actual == expected, "\(name): got \(actual), expected \(expected)", file: file, line: line)
}

func checkFormatting() {
    expectEqual(Format.modelName("claude-opus-5-5"), "Opus 5.5", "model name joins version parts")
    expectEqual(Format.modelName("claude-haiku-4-5-20251001"), "Haiku 4.5", "model name drops date suffix")
    expectEqual(Format.modelName("claude-sonnet-5"), "Sonnet 5", "single version part")
    expectEqual(Format.modelName("claude-3-5-haiku"), "3.5 Haiku", "legacy ordering")
    expectEqual(Format.tokens(0), "0", "zero tokens")
    expectEqual(Format.tokens(857_900), "857.9K", "thousands")
    expectEqual(Format.tokens(34_700_000), "34.7M", "millions")
    expectEqual(Format.tokens(1_200_000_000), "1.2B", "billions")
    expectEqual(Format.countdown(seconds: 38 * 60), "38m", "minutes")
    expectEqual(Format.countdown(seconds: 20), "1m", "under a minute rounds up to 1m")
    expectEqual(Format.countdown(seconds: 2 * 3600 + 53 * 60), "2h 53m", "hours")
    expectEqual(Format.countdown(seconds: 5 * 86_400 + 13 * 3600 + 59), "5d 13h", "days")
    expectEqual(Format.countdown(seconds: -5), "now", "past reset")
    expectEqual(Format.usd(277.351), "$277.35", "cents under 1000")
    expectEqual(Format.usd(2825.6), "$2,826", "whole dollars from 1000")
}

func checkPricing() {
    expectEqual(Pricing.normalize("claude-haiku-4-5-20251001"), "claude-haiku-4-5", "date suffix")
    expectEqual(Pricing.normalize("us.anthropic.claude-opus-4-1-20250805-v1:0"), "claude-opus-4-1", "bedrock id")
    expectEqual(Pricing.normalize("claude-opus-5-5[1m]"), "claude-opus-5-5", "context tag")
    expect(Pricing.price(for: "claude-opus-5-7") == nil, "unknown model is unpriced, not priced as a sibling")
    let usage = TokenUsage(input: 1_000_000, output: 1_000_000, cacheRead: 1_000_000, cacheWrite5m: 1_000_000, cacheWrite1h: 1_000_000)
    // Opus 5.5: 4 in + 20 out + 0.20 read + 5 (1.25x) 5m write + 8 (2x) 1h write
    expectEqual(Pricing.cost(of: usage, model: "claude-opus-5-5"), 37.2, "opus 5.5 cost per bucket")
    expect(Pricing.cost(of: usage, model: "gpt-9") == nil, "foreign model has no cost")
}

func checkCredentials() throws {
    let max = Data(#"{"claudeAiOauth":{"accessToken":"tok","expiresAt":1790000000000,"subscriptionType":"max","rateLimitTier":"default_claude_max_5x"}}"#.utf8)
    let parsed = try CredentialsLoader.parse(max)
    expectEqual(parsed.accessToken, "tok", "token read")
    expectEqual(parsed.planLabel, "Max 5x", "max tier label")
    expect(parsed.isExpired(now: Date(timeIntervalSince1970: 1_790_000_001)), "expiry from milliseconds")
    expectEqual(CredentialsLoader.planLabel(subscriptionType: "pro", rateLimitTier: nil), "Pro", "pro label")
    let mcpOnly = Data(#"{"mcpOAuth":{}}"#.utf8)
    expect((try? CredentialsLoader.parse(mcpOnly)) == nil, "blob without a subscription login is not signed in")
}

func checkLimits() throws {
    let payload = Data("""
    {"five_hour":{"utilization":100.0,"resets_at":"2026-10-02T17:59:59.606054+00:00"},
     "seven_day":{"utilization":64.0,"resets_at":"2026-10-03T01:59:59.606074+00:00"},
     "seven_day_oauth_apps":null,
     "limits":[{"kind":"session","percent":100,"scope":null},
               {"kind":"weekly_scoped","percent":7,"resets_at":"2026-10-03T02:00:00+00:00","scope":{"model":{"id":null,"display_name":"Fable"}}},
               {"kind":"weekly_scoped","percent":7,"scope":{"model":{"display_name":"Fable"}}}]}
    """.utf8)
    let rows = try LimitsParser.parse(payload)
    expectEqual(rows.map(\.title), ["Session", "Weekly", "Fable Weekly"], "rows in order, scoped deduped")
    expectEqual(rows[0].usedPercent, 100, "session percent")
    expect(rows[0].isCritical, "100% is critical")
    expectEqual(rows[1].leftPercent, 36, "weekly left")
    expect(!rows[1].isCritical, "64% is not critical")
    expect(rows[0].resetsAt != nil, "microsecond timestamp parses")
    expectEqual(rows[2].usedFraction, 0.07, "scoped percent")
    expect((try? LimitsParser.parse(Data("nope".utf8))) == nil, "garbage payload throws")
}

func assistantLine(id: String?, request: String = "req", model: String = "claude-opus-5-5", time: String, input: Int = 10, output: Int = 5, oneHour: Int = 0, creation: Int = 0) -> String {
    let idField = id.map { #""id":"\#($0)","# } ?? ""
    return #"{"type":"assistant","requestId":"\#(request)","timestamp":"\#(time)","message":{\#(idField)"role":"assistant","model":"\#(model)","usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_read_input_tokens":0,"cache_creation_input_tokens":\#(creation),"cache_creation":{"ephemeral_1h_input_tokens":\#(oneHour)}}}}"#
}

func checkScanner() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("agent-usage-checks-\(UUID().uuidString)")
    let project = root.appendingPathComponent("proj")
    try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let now = Date()
    let stamp = now.addingTimeInterval(-60).formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    let file = project.appendingPathComponent("a.jsonl")
    let lines = [
        assistantLine(id: "m1", time: stamp, output: 1),
        assistantLine(id: "m1", time: stamp, output: 5),  // streamed duplicate: last row wins
        #"{"type":"user","message":{"role":"user","content":"hi"},"timestamp":"\#(stamp)"}"#,
        assistantLine(id: "m2", model: "<synthetic>", time: stamp),
        assistantLine(id: "m3", time: stamp, input: 0, output: 0),
        assistantLine(id: "m4", time: stamp, oneHour: 50, creation: 30),
    ]
    try (lines.joined(separator: "\n") + "\n" + #"{"type":"assist"#).write(to: file, atomically: true, encoding: .utf8)
    let scanner = TranscriptScanner(roots: [root])
    let first = await scanner.scan(now: now)
    expectEqual(first.count, 2, "dedupes streaming rows, skips user, synthetic, zero-usage and the partial line")
    expectEqual(first.first { $0.usage.cacheWrite == 0 }?.usage.total, 15, "last streamed row kept")
    expectEqual(first.first { $0.usage.cacheWrite > 0 }?.usage.cacheWrite1h, 30, "1h write clamped to creation total")

    let handle = try FileHandle(forWritingTo: file)
    try handle.seekToEnd()
    try handle.write(contentsOf: Data(("ant\"}\n" + assistantLine(id: "m5", time: stamp) + "\n").utf8))
    try handle.close()
    let second = await scanner.scan(now: now)
    expectEqual(second.count, 3, "appended line picked up incrementally, completed partial line ignored")

    let copy = project.appendingPathComponent("b.jsonl")
    try (assistantLine(id: "m5", time: stamp) + "\n").write(to: copy, atomically: true, encoding: .utf8)
    let third = await scanner.scan(now: now)
    expectEqual(third.count, 3, "a message copied into another transcript counts once")
}

func checkSummary() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
    let now = ISO8601DateFormatter().date(from: "2026-10-02T15:00:00Z") ?? Date()
    let lateYesterdayLocal = ISO8601DateFormatter().date(from: "2026-10-02T03:30:00Z") ?? Date()  // 23:30 on 10/1 in New York
    let entries = [
        UsageEntry(timestamp: now.addingTimeInterval(-60), model: "claude-opus-5-5", usage: TokenUsage(input: 1_000_000)),
        UsageEntry(timestamp: lateYesterdayLocal, model: "claude-haiku-4-5-20251001", usage: TokenUsage(output: 2_000_000)),
        UsageEntry(timestamp: lateYesterdayLocal, model: "claude-haiku-4-5", usage: TokenUsage(output: 1_000_000)),
        UsageEntry(timestamp: now.addingTimeInterval(-40 * 86_400), model: "claude-opus-5-5", usage: TokenUsage(input: 9)),
        UsageEntry(timestamp: now.addingTimeInterval(-120), model: "claude-next-9", usage: TokenUsage(input: 7)),
    ]
    let summary = UsageSummary.build(entries: entries, now: now, calendar: calendar)
    expectEqual(summary.days.count, 7, "seven days")
    expectEqual(summary.days.last?.label, "Today", "ends on today")
    expectEqual(summary.days.last?.tokens, 1_000_007, "today's tokens")
    expectEqual(summary.days[5].label, "Thu", "yesterday by local day, not UTC")
    expectEqual(summary.days[5].tokens, 3_000_000, "yesterday's tokens")
    expectEqual(summary.models.first?.name, "Haiku 4.5", "dated and undated snapshots share a row, top by tokens")
    expectEqual(summary.todayCost, 4.0, "today's cost")
    expectEqual(summary.windowCost, 19.0, "30-day cost excludes older entries")
    expectEqual(summary.unpricedTokens, 7, "unknown model tokens tracked")
    expectEqual(summary.latestModel, "Opus 5.5", "latest model")
}

func runLive() async throws {
    let credentials = try CredentialsLoader.load()
    print("plan:", credentials.planLabel ?? "-", "expired:", credentials.isExpired())
    for row in try await LimitsClient.fetch(token: credentials.accessToken) {
        print("limit:", row.title, "\(row.usedPercent)% used", row.resetsAt.map { Format.countdown(seconds: $0.timeIntervalSinceNow) } ?? "-")
    }
    let started = Date()
    let scanner = TranscriptScanner(roots: [ClaudePaths.projectsRoot()])
    let entries = await scanner.scan()
    let firstScan = Date().timeIntervalSince(started)
    let rescanStart = Date()
    _ = await scanner.scan()
    print(String(format: "scan: %d entries, first %.2fs, rescan %.2fs", entries.count, firstScan, Date().timeIntervalSince(rescanStart)))
    let summary = UsageSummary.build(entries: entries)
    for day in summary.days { print("day:", day.label, Format.tokens(day.tokens), Format.usd(day.cost)) }
    for model in summary.models { print("model:", model.name, Format.tokens(model.usage.total), model.cost.map(Format.usd) ?? "unpriced") }
    print("today:", Format.usd(summary.todayCost), "30d:", Format.usd(summary.windowCost), Format.tokens(summary.windowTokens), "latest:", summary.latestModel ?? "-")
}

checkFormatting()
checkPricing()
try checkCredentials()
try checkLimits()
try await checkScanner()
checkSummary()
print("\(passes) passed, \(failures) failed")
if CommandLine.arguments.contains("--live") { try await runLive() }
exit(failures == 0 ? 0 : 1)
