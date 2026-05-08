import SwiftUI
import GameCore
import Persistence

struct SettingsSheet: View {
    let store: GameStore
    @Environment(\.dismiss) private var dismiss
    @State private var anthropicKey: String = APIKeyStore.anthropicKey() ?? ""
    @State private var openAIKey: String = APIKeyStore.openAIKey() ?? ""
    @State private var provider: ProviderHint = .anthropic
    @State private var hapticsEnabled: Bool = HapticsPreference.isEnabled
    @State private var soundEnabled: Bool = SoundPreference.isEnabled
    @State private var bestScore: BestScoreRecord? = BestScoreStore.current()
    @State private var showResetConfirm = false
    @State private var showHowToPlay = false

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.canvas.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.Space.lg) {
                        // — Header —
                        VStack(alignment: .leading, spacing: 6) {
                            Text("SETTINGS")
                                .font(DS.Typo.captionUpper())
                                .tracking(DS.Typo.captionUpperTracking)
                                .foregroundStyle(DS.Color.muted)
                            Text("设置")
                                .font(DS.Typo.displayMD())
                                .tracking(DS.Typo.displayTrackingTight)
                                .foregroundStyle(DS.Color.ink)
                        }

                        // — AI 模型 —
                        SettingsSection(title: "AI 模型", caption: "选择用哪个多模态模型来猜你画的图。") {
                            Picker("使用模型", selection: $provider) {
                                Text("Claude Haiku 4.5").tag(ProviderHint.anthropic)
                                Text("GPT-4o-mini").tag(ProviderHint.openai)
                            }
                            .pickerStyle(.segmented)
                        }

                        // — 触觉 / 音效 / 最佳成绩 —
                        SettingsSection(title: "玩法",
                                        caption: "震动 + 音效在猜对、猜错、超时时给你反馈。音效默认关闭。") {
                            VStack(spacing: DS.Space.xs) {
                                ToggleRow(label: "震动反馈", isOn: $hapticsEnabled)
                                ToggleRow(label: "音效", isOn: $soundEnabled)
                            }
                        }

                        // — Lifetime stats —
                        let stats = LifetimeStatsStore.current()
                        if stats.gamesPlayed > 0 {
                            SettingsSection(title: "累计统计",
                                            caption: "本机所有游戏汇总。") {
                                HStack(spacing: DS.Space.lg) {
                                    StatColumn(label: "局数", value: "\(stats.gamesPlayed)")
                                    StatColumn(label: "总分", value: "\(stats.totalScore)")
                                    StatColumn(label: "猜中",
                                               value: "\(stats.totalCorrect)/\(stats.totalRounds)")
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, DS.Space.md)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: DS.Radius.md).fill(DS.Color.canvas)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.Radius.md)
                                        .stroke(DS.Color.hairline, lineWidth: 1)
                                )
                            }
                        }

                        if let bestScore {
                            SettingsSection(title: "最佳成绩",
                                            caption: "本机最高分。点重置将清掉。") {
                                HStack {
                                    HStack(spacing: 6) {
                                        Image(systemName: "crown.fill")
                                            .foregroundStyle(DS.Color.accentAmber)
                                        Text("\(bestScore.total) 分")
                                            .font(DS.Typo.titleSM())
                                            .foregroundStyle(DS.Color.ink)
                                        Text("· \(bestScore.correct)/\(bestScore.rounds) 局")
                                            .font(DS.Typo.caption())
                                            .foregroundStyle(DS.Color.muted)
                                    }
                                    Spacer()
                                    Button("重置") { showResetConfirm = true }
                                        .buttonStyle(CoralTextLinkButtonStyle())
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)
                                .frame(height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: DS.Radius.md).fill(DS.Color.canvas)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: DS.Radius.md)
                                        .stroke(DS.Color.hairline, lineWidth: 1)
                                )
                            }
                        }

                        // — Anthropic Key —
                        SettingsSection(title: "Anthropic API Key",
                                        caption: "MVP：直接调 Anthropic，未经服务器代理。生产版会移除此字段，密钥放在 Cloudflare Worker 中。") {
                            DSKeyField(placeholder: "sk-ant-...", text: $anthropicKey)
                        }

                        // — OpenAI Key —
                        SettingsSection(title: "OpenAI API Key",
                                        caption: "仅当模型选 GPT-4o-mini 时使用。") {
                            DSKeyField(placeholder: "sk-...", text: $openAIKey)
                        }

                        // — Actions —
                        VStack(spacing: DS.Space.sm) {
                            Button("保存") { save() }
                                .buttonStyle(CoralPrimaryButtonStyle())
                            Button("清除所有 Key") {
                                anthropicKey = ""; openAIKey = ""
                                APIKeyStore.setAnthropicKey(nil)
                                APIKeyStore.setOpenAIKey(nil)
                            }
                            .buttonStyle(CreamSecondaryButtonStyle())
                            .frame(maxWidth: .infinity)
                            Button("How to play") { showHowToPlay = true }
                                .buttonStyle(CoralTextLinkButtonStyle())
                        }

                        // — About —
                        VStack(alignment: .leading, spacing: DS.Space.xs) {
                            Text("ABOUT")
                                .font(DS.Typo.captionUpper())
                                .tracking(DS.Typo.captionUpperTracking)
                                .foregroundStyle(DS.Color.muted)
                            Text("草图来自 Google Quick, Draw! 数据集（CC BY 4.0）。MVP 使用极小手绘种子集。")
                                .font(DS.Typo.bodySM())
                                .foregroundStyle(DS.Color.body)
                                .lineSpacing(2)
                            Text(versionLine)
                                .font(DS.Typo.caption())
                                .foregroundStyle(DS.Color.mutedSoft)
                                .padding(.top, DS.Space.xs)
                        }
                        .padding(DS.Space.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .fill(DS.Color.surfaceSoft)
                        )

                        Spacer().frame(height: DS.Space.lg)
                    }
                    .padding(.horizontal, DS.Space.lg)
                    .padding(.top, DS.Space.md)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { save(); dismiss() }
                        .font(DS.Typo.button())
                        .foregroundStyle(DS.Color.primary)
                }
            }
            .toolbarBackground(DS.Color.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showHowToPlay) { OnboardingSheet() }
            .alert("重置最佳成绩？", isPresented: $showResetConfirm) {
                Button("重置", role: .destructive) {
                    BestScoreStore.reset()
                    bestScore = nil
                }
                Button("取消", role: .cancel) { }
            } message: {
                Text("这会清掉本机记录的最高分。GameCenter 上的成绩不受影响。")
            }
            .onChange(of: hapticsEnabled) { _, new in HapticsPreference.set(new) }
            .onChange(of: soundEnabled) { _, new in SoundPreference.set(new) }
            .onAppear {
                if let raw = UserDefaults.standard.string(forKey: SettingsKey.providerHint),
                   let hint = ProviderHint(rawValue: raw) {
                    provider = hint
                } else {
                    provider = store.providerHint
                }
            }
        }
        .tint(DS.Color.primary)
        .preferredColorScheme(.light)
    }

    private func save() {
        APIKeyStore.setAnthropicKey(anthropicKey)
        APIKeyStore.setOpenAIKey(openAIKey)
        UserDefaults.standard.set(provider.rawValue, forKey: SettingsKey.providerHint)
        store.providerHint = provider
    }

    private var versionLine: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "AI Draw v\(v) (\(b))"
    }
}

// MARK: - Section + key field

private struct SettingsSection<Content: View>: View {
    let title: String
    let caption: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(title)
                .font(DS.Typo.titleSM())
                .foregroundStyle(DS.Color.ink)
            content()
            if let caption {
                Text(caption)
                    .font(DS.Typo.bodySM())
                    .foregroundStyle(DS.Color.muted)
                    .lineSpacing(2)
            }
        }
    }
}

private struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool
    var body: some View {
        HStack {
            Text(label)
                .font(DS.Typo.bodyMD())
                .foregroundStyle(DS.Color.ink)
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(DS.Color.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md).fill(DS.Color.canvas)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(DS.Color.hairline, lineWidth: 1)
        )
    }
}

private struct StatColumn: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(DS.Typo.captionUpper())
                .tracking(DS.Typo.captionUpperTracking)
                .foregroundStyle(DS.Color.muted)
            Text(value)
                .font(DS.Typo.titleMD())
                .foregroundStyle(DS.Color.ink)
                .monospacedDigit()
        }
    }
}

private struct DSKeyField: View {
    let placeholder: String
    @Binding var text: String
    @State private var revealed = false

    var body: some View {
        HStack(spacing: DS.Space.xs) {
            Group {
                if revealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .font(DS.Typo.code())
            .foregroundStyle(DS.Color.ink)

            Button {
                revealed.toggle()
            } label: {
                Image(systemName: revealed ? "eye.slash" : "eye")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.Color.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md).fill(DS.Color.canvas)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(DS.Color.hairline, lineWidth: 1)
        )
    }
}
