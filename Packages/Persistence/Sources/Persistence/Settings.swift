import Foundation

public enum SettingsKey {
    public static let providerHint    = "ai.draw.providerHint"
    public static let highScore       = "ai.draw.highScore"
    public static let highScoreRounds = "ai.draw.highScore.rounds"
    public static let highScoreCorrect = "ai.draw.highScore.correct"
    public static let hapticsEnabled  = "ai.draw.haptics.enabled"
    public static let lastDifficultyMode = "ai.draw.lastMode"
    public static let lastRoundCount  = "ai.draw.lastRounds"
}

public enum GamePreferences {
    private static var defaults: UserDefaults { .standard }

    public static var lastDifficultyMode: String? {
        get { defaults.string(forKey: SettingsKey.lastDifficultyMode) }
        set { defaults.set(newValue, forKey: SettingsKey.lastDifficultyMode) }
    }

    public static var lastRoundCount: Int {
        get {
            let v = defaults.integer(forKey: SettingsKey.lastRoundCount)
            return v == 0 ? 6 : v
        }
        set { defaults.set(newValue, forKey: SettingsKey.lastRoundCount) }
    }
}

/// Persisted best-score record. We track total points plus context (rounds
/// played, rounds won) so the GameOver "personal best" badge has enough
/// information to be honest about across-different-lengths comparison.
public struct BestScoreRecord: Sendable, Hashable, Codable {
    public let total: Int
    public let rounds: Int
    public let correct: Int

    public init(total: Int, rounds: Int, correct: Int) {
        self.total = total
        self.rounds = rounds
        self.correct = correct
    }
}

public enum BestScoreStore {
    private static var defaults: UserDefaults { .standard }

    public static func current() -> BestScoreRecord? {
        let total = defaults.integer(forKey: SettingsKey.highScore)
        let rounds = defaults.integer(forKey: SettingsKey.highScoreRounds)
        let correct = defaults.integer(forKey: SettingsKey.highScoreCorrect)
        guard total > 0 else { return nil }
        return BestScoreRecord(total: total, rounds: rounds, correct: correct)
    }

    /// Saves the candidate if it strictly beats the existing record on total
    /// points. Returns true when a new best was written.
    @discardableResult
    public static func recordIfBest(total: Int, rounds: Int, correct: Int) -> Bool {
        let prev = current()?.total ?? 0
        guard total > prev else { return false }
        defaults.set(total, forKey: SettingsKey.highScore)
        defaults.set(rounds, forKey: SettingsKey.highScoreRounds)
        defaults.set(correct, forKey: SettingsKey.highScoreCorrect)
        return true
    }

    public static func reset() {
        defaults.removeObject(forKey: SettingsKey.highScore)
        defaults.removeObject(forKey: SettingsKey.highScoreRounds)
        defaults.removeObject(forKey: SettingsKey.highScoreCorrect)
    }
}

public enum HapticsPreference {
    private static var defaults: UserDefaults { .standard }

    public static var isEnabled: Bool {
        defaults.object(forKey: SettingsKey.hapticsEnabled) as? Bool ?? true
    }

    public static func set(_ enabled: Bool) {
        defaults.set(enabled, forKey: SettingsKey.hapticsEnabled)
    }
}

public enum APIKeyStore {
    public static let service = "com.aidraw.byok"
    /// Returns the user-supplied Anthropic key, if any.
    public static func anthropicKey() -> String? {
        Keychain.get("anthropic", service: service)
    }
    public static func setAnthropicKey(_ key: String?) {
        if let key, !key.isEmpty {
            try? Keychain.set(key, for: "anthropic", service: service)
        } else {
            Keychain.delete("anthropic", service: service)
        }
    }
    public static func openAIKey() -> String? {
        Keychain.get("openai", service: service)
    }
    public static func setOpenAIKey(_ key: String?) {
        if let key, !key.isEmpty {
            try? Keychain.set(key, for: "openai", service: service)
        } else {
            Keychain.delete("openai", service: service)
        }
    }
}
