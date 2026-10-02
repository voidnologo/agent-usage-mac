import AgentUsageCore
import Foundation

/// Owns the refresh schedule and the state the menu bar label and panel render.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var limits: [LimitRow] = []
    @Published private(set) var limitsFetchedAt: Date?
    @Published private(set) var planLabel: String?
    @Published private(set) var statusText: String?
    @Published private(set) var summary: UsageSummary = .empty
    @Published private(set) var now = Date()

    /// The usage endpoint rate limits aggressive polling; Omarchy polls every 15 minutes plus on open.
    private let limitsInterval: TimeInterval = 300
    private let minimumLimitsGap: TimeInterval = 15
    private let tokensInterval: TimeInterval = 60
    /// Limits older than this render faded, as Omarchy does for stale data.
    private let staleAfter: TimeInterval = 900

    private let scanner = TranscriptScanner(roots: [ClaudePaths.projectsRoot()])
    private var lastLimitsAttempt: Date?
    private var retryNotBefore: Date?
    private var started = false
    private var isSnapshot = false

    /// A store frozen on fixed data, used to render the README screenshot without anyone's real usage.
    static func snapshot(limits: [LimitRow], planLabel: String, summary: UsageSummary, now: Date) -> UsageStore {
        let store = UsageStore()
        store.isSnapshot = true
        store.limits = limits
        store.limitsFetchedAt = now
        store.planLabel = planLabel
        store.summary = summary
        store.now = now
        return store
    }

    var session: LimitRow? { limits.first { $0.title == "Session" } }
    var weekly: LimitRow? { limits.first { $0.title == "Weekly" } }
    var isCritical: Bool { limits.contains(where: \.isCritical) }
    var limitsAreStale: Bool { limitsFetchedAt.map { now.timeIntervalSince($0) > staleAfter } ?? false }

    func start() {
        guard !started, !isSnapshot else { return }
        started = true
        schedule(every: limitsInterval) { await $0.refreshLimits(force: true) }
        schedule(every: tokensInterval) { await $0.refreshTokens() }
        schedule(every: 30) { $0.now = Date() }
    }

    func panelOpened() {
        guard !isSnapshot else { return }
        now = Date()
        Task {
            await refreshLimits(force: false)
            await refreshTokens()
        }
    }

    func refreshAll() {
        Task {
            await refreshLimits(force: true)
            await refreshTokens()
        }
    }

    func refreshTokens() async {
        let entries = await scanner.scan()
        summary = UsageSummary.build(entries: entries)
    }

    func refreshLimits(force: Bool) async {
        let attemptTime = Date()
        if let retryNotBefore, attemptTime < retryNotBefore { return }
        if !force, let lastLimitsAttempt, attemptTime.timeIntervalSince(lastLimitsAttempt) < minimumLimitsGap { return }
        lastLimitsAttempt = attemptTime
        now = attemptTime
        guard let credentials = await loadCredentials() else { return }
        planLabel = credentials.planLabel
        guard !credentials.isExpired() else {
            keepCachedLimits(status: "Sign-in expired. Open Claude Code to refresh it.")
            return
        }
        await fetchLimits(token: credentials.accessToken)
    }

    private func fetchLimits(token: String) async {
        do {
            limits = try await LimitsClient.fetch(token: token)
            limitsFetchedAt = Date()
            statusText = nil
        } catch let error as LimitsError {
            if case .rateLimited(let retryAfter) = error {
                retryNotBefore = Date().addingTimeInterval(TimeInterval(retryAfter ?? 60))
            }
            keepCachedLimits(status: error.message)
        } catch {
            keepCachedLimits(status: error.localizedDescription)
        }
    }

    /// Reading the Keychain spawns `/usr/bin/security`, so it runs off the main actor.
    private func loadCredentials() async -> ClaudeCredentials? {
        let result = await Task.detached { Result { try CredentialsLoader.load() } }.value
        switch result {
        case .success(let credentials):
            return credentials
        case .failure:
            keepCachedLimits(status: "Waiting for Claude Code sign-in. Run `claude` and log in.")
            return nil
        }
    }

    /// A window whose reset has passed no longer describes anything, so it is dropped rather than shown stale.
    private func keepCachedLimits(status: String) {
        statusText = status
        limits = limits.filter { ($0.resetsAt ?? .distantFuture) > Date() }
    }

    private func schedule(every interval: TimeInterval, _ work: @escaping @MainActor (UsageStore) async -> Void) {
        Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await work(self)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }
}
