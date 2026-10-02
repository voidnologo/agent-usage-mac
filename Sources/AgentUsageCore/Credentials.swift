import Foundation

/// The Claude Code subscription login, read from wherever Claude Code stored it.
public struct ClaudeCredentials: Sendable, Equatable {
    public let accessToken: String
    public let expiresAt: Date?
    public let planLabel: String?

    public func isExpired(now: Date = Date()) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }
}

public enum CredentialsError: Error, Equatable {
    case notSignedIn
    case unreadable(String)
}

public enum CredentialsLoader {
    static let keychainService = "Claude Code-credentials"

    /// Reads the Keychain first because that is where Claude Code keeps the live login on macOS; the
    /// JSON file covers `CLAUDE_CONFIG_DIR` setups and machines that sync a Linux-style config.
    /// The token is never refreshed here: refreshing rotates the refresh token and would sign Claude Code out.
    public static func load(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> ClaudeCredentials {
        if let keychainJSON = readKeychain(), let credentials = try? parse(keychainJSON) {
            return credentials
        }
        let file = ClaudePaths.configRoot(environment: environment).appendingPathComponent(".credentials.json")
        guard let fileJSON = try? Data(contentsOf: file) else { throw CredentialsError.notSignedIn }
        return try parse(fileJSON)
    }

    /// Parses Claude Code's credential blob: `{"claudeAiOauth": {accessToken, expiresAt(ms), subscriptionType, rateLimitTier}}`.
    public static func parse(_ data: Data) throws -> ClaudeCredentials {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CredentialsError.unreadable("credentials are not JSON")
        }
        guard let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else {
            throw CredentialsError.notSignedIn
        }
        let expiresAt = (oauth["expiresAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        let plan = planLabel(subscriptionType: oauth["subscriptionType"] as? String, rateLimitTier: oauth["rateLimitTier"] as? String)
        return ClaudeCredentials(accessToken: token, expiresAt: expiresAt, planLabel: plan)
    }

    /// `default_claude_max_5x` → `Max 5x`; otherwise the capitalized subscription type (`pro` → `Pro`).
    public static func planLabel(subscriptionType: String?, rateLimitTier: String?) -> String? {
        if let tier = rateLimitTier?.lowercased(),
           let match = tier.firstMatch(of: /max_(\d+x)/) {
            return "Max \(match.1)"
        }
        guard let type = subscriptionType, !type.isEmpty else { return nil }
        return type.prefix(1).uppercased() + type.dropFirst()
    }

    /// Shells out to `/usr/bin/security` because Claude Code wrote the item with that tool, so it is already
    /// on the item's access list; reading through the Security framework would raise a Keychain prompt.
    private static func readKeychain() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, !data.isEmpty else { return nil }
        return data
    }
}

public enum ClaudePaths {
    /// `$CLAUDE_CONFIG_DIR` when set, otherwise `~/.claude`, as Claude Code resolves it.
    public static func configRoot(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let custom = environment["CLAUDE_CONFIG_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: (custom as NSString).expandingTildeInPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    }

    public static func projectsRoot(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        configRoot(environment: environment).appendingPathComponent("projects")
    }
}
