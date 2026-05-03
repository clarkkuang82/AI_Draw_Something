import SwiftUI
import GameCore
import Persistence

struct SettingsSheet: View {
    let store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var anthropicKey: String = APIKeyStore.anthropicKey() ?? ""
    @State private var openAIKey: String = APIKeyStore.openAIKey() ?? ""
    @State private var provider: ProviderHint = .anthropic

    var body: some View {
        NavigationStack {
            Form {
                Section("AI 模型") {
                    Picker("使用模型", selection: $provider) {
                        Text("Claude Haiku 4.5").tag(ProviderHint.anthropic)
                        Text("GPT-4o-mini").tag(ProviderHint.openai)
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    SecureField("sk-ant-...", text: $anthropicKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Anthropic API Key")
                } footer: {
                    Text("MVP：直接调 Anthropic，未经服务器代理。生产版会移除此字段，密钥放在 Cloudflare Worker 中。")
                }
                Section {
                    SecureField("sk-...", text: $openAIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("OpenAI API Key")
                } footer: {
                    Text("仅当模型选 GPT-4o-mini 时使用。")
                }
                Section {
                    Button("保存") { save() }
                    Button("清除所有 Key", role: .destructive) {
                        anthropicKey = ""; openAIKey = ""
                        APIKeyStore.setAnthropicKey(nil)
                        APIKeyStore.setOpenAIKey(nil)
                    }
                }
                Section("关于") {
                    Text("草图来自 Google Quick, Draw! 数据集（CC BY 4.0）。MVP 使用极小手绘种子集。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { save(); dismiss() }
                }
            }
            .onAppear {
                if let raw = UserDefaults.standard.string(forKey: SettingsKey.providerHint),
                   let hint = ProviderHint(rawValue: raw) {
                    provider = hint
                } else {
                    provider = store.providerHint
                }
            }
        }
    }

    private func save() {
        APIKeyStore.setAnthropicKey(anthropicKey)
        APIKeyStore.setOpenAIKey(openAIKey)
        UserDefaults.standard.set(provider.rawValue, forKey: SettingsKey.providerHint)
        store.providerHint = provider
    }
}
