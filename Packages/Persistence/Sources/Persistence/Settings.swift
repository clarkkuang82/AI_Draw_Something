import Foundation

public enum SettingsKey {
    public static let providerHint = "ai.draw.providerHint"
    public static let highScore    = "ai.draw.highScore"
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
