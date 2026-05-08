import SwiftUI
import PencilKit
import GameCore
import Drawing
import Persistence
#if canImport(Commerce)
import Commerce
#endif
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Haptics

enum Haptics {
    private static var enabled: Bool { HapticsPreference.isEnabled }
    static func success() {
        #if canImport(UIKit)
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    static func warning() {
        #if canImport(UIKit)
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
    static func error() {
        #if canImport(UIKit)
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.error)
        #endif
    }
    static func light() {
        #if canImport(UIKit)
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

// MARK: - Root

struct RootView: View {
    let services: AppServices
    let dataset: QuickDrawDataset?
    @State private var showSettings = false
    @State private var showPaywall = false
    @State private var showKeyAlert = false
    @State private var showOnboarding: Bool = !OnboardingState.didOnboard

    private var store: GameStore { services.gameStore }

    var body: some View {
        NavigationStack {
            ZStack {
                DS.Color.canvas.ignoresSafeArea()
                VStack(spacing: 0) {
                    Group {
                        switch store.phase {
                        case .idle:
                            IdleScreen(
                                entitlementHUD: services.entitlementStore?.hudText,
                                start: { rounds, mode in
                                    startTapped(rounds: rounds, mode: mode)
                                }
                            )
                            .transition(.opacity)
                        case .loading:
                            ProgressView().tint(DS.Color.primary)
                        case .showWord(let round):
                            ShowWordScreen(round: round, begin: { store.beginRound() })
                                .transition(.opacity)
                        case .aiDrawing(let round):
                            AIDrawingScreen(round: round, dataset: dataset, store: store)
                                .transition(.opacity)
                        case .playerDrawing(let round):
                            PlayerDrawingScreen(round: round, store: store)
                                .transition(.opacity)
                        case .reveal(let round, let outcome):
                            RevealScreen(round: round, outcome: outcome,
                                         delta: store.lastDelta,
                                         multiplier: store.roundHistory.last?.multiplier ?? 1.0,
                                         score: store.score,
                                         next: {
                                             store.acknowledgeReveal(); store.nextRound()
                                         })
                                .transition(.opacity)
                                .onAppear { hapticForOutcome(outcome) }
                        case .roundOver:
                            ProgressView().tint(DS.Color.primary)
                        case .gameOver(let score):
                            GameOverScreen(score: score,
                                           rounds: store.roundHistory,
                                           again: { startTapped(rounds: store.totalRoundsThisGame,
                                                                 mode: store.difficultyMode) })
                                .transition(.opacity)
                                .onAppear { Task { await services.leaderboard?.submit(score: score.total) } }
                        }
                    }
                    .animation(.easeInOut(duration: 0.25), value: phaseId)
                    .padding(.horizontal, DS.Space.lg)
                    .padding(.vertical, DS.Space.md)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    AdMobBannerView()
                }
            }
            .toolbarBackground(DS.Color.canvas, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    AppWordmark()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .foregroundStyle(DS.Color.ink)
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if case .idle = store.phase {
                        EmptyView()
                    } else {
                        HStack(spacing: 6) {
                            Text("第 \(store.roundIndex)/\(store.totalRoundsThisGame)")
                                .coralPill()
                            if store.streak >= 2 {
                                StreakBadge(streak: store.streak)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(store: store)
            }
            .sheet(isPresented: $showOnboarding) {
                OnboardingSheet()
            }
            .alert("还没填 API key", isPresented: $showKeyAlert) {
                Button("去设置") { showSettings = true }
                Button("先看看", role: .cancel) { }
            } message: {
                Text("AI 猜你画的图需要 Anthropic 或 OpenAI key（设置 → 粘贴）。\n纯猜词回合不需要 key，可以照常玩。")
            }
            #if canImport(Commerce)
            .sheet(isPresented: $showPaywall) {
                if let iap = services.iapStore,
                   let ent = services.entitlementStore,
                   let ref = services.referralFlow {
                    PaywallView(store: iap, entitlement: ent, referral: ref) {
                        Task { await onPaywallDone() }
                    }
                }
            }
            #endif
        }
        .tint(DS.Color.primary)
        .preferredColorScheme(.light)
    }

    private var phaseId: String {
        switch store.phase {
        case .idle: return "idle"
        case .loading: return "loading"
        case .showWord: return "showWord-\(store.roundIndex)"
        case .aiDrawing: return "aiDrawing-\(store.roundIndex)"
        case .playerDrawing: return "playerDrawing-\(store.roundIndex)"
        case .reveal: return "reveal-\(store.roundIndex)"
        case .roundOver: return "roundOver-\(store.roundIndex)"
        case .gameOver: return "gameOver"
        }
    }

    private func hapticForOutcome(_ outcome: Outcome) {
        switch outcome {
        case .correct: Haptics.success()
        case .timedOut: Haptics.warning()
        case .skipped: Haptics.warning()
        }
    }

    private func startTapped(rounds: Int, mode: DifficultyMode) {
        Task {
            #if canImport(Commerce)
            if services.isAttestedMode, let ent = services.entitlementStore {
                await ent.refresh()
                if !ent.canStart {
                    showPaywall = true
                    return
                }
            }
            #endif
            // BYOK mode + no key: prompt before launching, since several rounds
            // will silently fail when the player tries to submit a drawing.
            if !services.isAttestedMode {
                let hasKey = (APIKeyStore.anthropicKey()?.isEmpty == false)
                    || (APIKeyStore.openAIKey()?.isEmpty == false)
                if !hasKey {
                    showKeyAlert = true
                    return
                }
            }
            Haptics.light()
            store.startGame(rounds: rounds, mode: mode)
        }
    }

    @MainActor
    private func onPaywallDone() async {
        #if canImport(Commerce)
        if let ent = services.entitlementStore, ent.canStart {
            store.startGame()
        }
        #endif
    }
}

// MARK: - Wordmark + streak badge

private struct AppWordmark: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "asterisk")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DS.Color.ink)
            Text("AI Draw")
                .font(DS.Typo.titleSM())
                .foregroundStyle(DS.Color.ink)
        }
    }
}

private struct StreakBadge: View {
    let streak: Int
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill").font(.system(size: 11, weight: .bold))
            Text("×\(streak)")
                .font(DS.Typo.captionUpper())
                .tracking(0.5)
        }
        .foregroundStyle(DS.Color.onPrimary)
        .padding(.horizontal, DS.Space.xs)
        .padding(.vertical, 4)
        .background(Capsule().fill(DS.Color.accentAmber))
    }
}

// MARK: - Idle

private struct IdleScreen: View {
    let entitlementHUD: String?
    let start: (_ rounds: Int, _ mode: DifficultyMode) -> Void
    @State private var mode: DifficultyMode = {
        if let raw = GamePreferences.lastDifficultyMode,
           let m = DifficultyMode(rawValue: raw) { return m }
        return .standard
    }()
    @State private var rounds: Int = GamePreferences.lastRoundCount
    @State private var bestScore: BestScoreRecord? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                Spacer().frame(height: DS.Space.xs)
                Text("AI DRAW")
                    .font(DS.Typo.captionUpper())
                    .tracking(DS.Typo.captionUpperTracking)
                    .foregroundStyle(DS.Color.muted)
                Text("Meet your\ndrawing partner.")
                    .font(DS.Typo.displayMD())
                    .tracking(DS.Typo.displayTrackingTight)
                    .foregroundStyle(DS.Color.ink)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("和 AI 轮流出题画画 —— AI 用 QuickDraw 笔画演示，你画的让多模态模型来猜。")
                    .font(DS.Typo.bodyMD())
                    .foregroundStyle(DS.Color.body)
                    .lineSpacing(4)
                if let entitlementHUD {
                    Text(entitlementHUD).creamPill()
                }

                if let bestScore {
                    BestScoreBanner(best: bestScore)
                }

                // Difficulty + round count selectors.
                VStack(alignment: .leading, spacing: DS.Space.sm) {
                    LabeledControl(title: "难度") {
                        Picker("", selection: $mode) {
                            Text("简单").tag(DifficultyMode.casual)
                            Text("标准").tag(DifficultyMode.standard)
                            Text("困难").tag(DifficultyMode.hard)
                        }
                        .pickerStyle(.segmented)
                    }
                    LabeledControl(title: "局数") {
                        Picker("", selection: $rounds) {
                            Text("6 局").tag(6)
                            Text("10 局").tag(10)
                            Text("15 局").tag(15)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding(DS.Space.md)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.lg).fill(DS.Color.surfaceCard)
                )

                Button {
                    GamePreferences.lastDifficultyMode = mode.rawValue
                    GamePreferences.lastRoundCount = rounds
                    start(rounds, mode)
                } label: { Text("开始游戏") }
                    .buttonStyle(CoralPrimaryButtonStyle())

                FeatureStripe()
                Spacer().frame(height: DS.Space.md)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .onAppear { bestScore = BestScoreStore.current() }
    }
}

private struct BestScoreBanner: View {
    let best: BestScoreRecord
    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Image(systemName: "crown.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DS.Color.accentAmber)
            VStack(alignment: .leading, spacing: 2) {
                Text("最佳成绩")
                    .font(DS.Typo.captionUpper())
                    .tracking(DS.Typo.captionUpperTracking)
                    .foregroundStyle(DS.Color.muted)
                HStack(spacing: 6) {
                    Text("\(best.total)")
                        .font(DS.Typo.titleLG())
                        .foregroundStyle(DS.Color.ink)
                    Text("分")
                        .font(DS.Typo.bodySM())
                        .foregroundStyle(DS.Color.muted)
                    Text("·").foregroundStyle(DS.Color.mutedSoft)
                    Text("\(best.correct)/\(best.rounds) 局")
                        .font(DS.Typo.bodySM())
                        .foregroundStyle(DS.Color.muted)
                }
            }
            Spacer()
        }
        .padding(DS.Space.md)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .fill(DS.Color.surfaceSoft)
        )
    }
}

private struct LabeledControl<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(DS.Typo.captionUpper())
                .tracking(DS.Typo.captionUpperTracking)
                .foregroundStyle(DS.Color.muted)
            content()
        }
    }
}

private struct FeatureStripe: View {
    var body: some View {
        HStack(spacing: DS.Space.sm) {
            FeatureChip(label: "60 个词", system: "text.book.closed")
            FeatureChip(label: "AI 视觉猜词", system: "eye")
            FeatureChip(label: "连击加分", system: "flame")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FeatureChip: View {
    let label: String
    let system: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: system).font(.system(size: 12, weight: .medium))
            Text(label).font(DS.Typo.caption())
        }
        .foregroundStyle(DS.Color.muted)
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, 6)
        .overlay(Capsule().stroke(DS.Color.hairline, lineWidth: 1))
    }
}

// MARK: - Show word

private struct ShowWordScreen: View {
    let round: Round
    let begin: () -> Void
    @State private var countdown: Int = 3
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: DS.Space.lg) {
            Spacer()
            Text(round.kind == .aiDraws ? "AI 来画 · 你来猜" : "你来画 · AI 来猜")
                .font(DS.Typo.captionUpper())
                .tracking(DS.Typo.captionUpperTracking)
                .foregroundStyle(DS.Color.muted)
            if round.kind == .playerDraws {
                Text(round.word.text)
                    .font(DS.Typo.displayXL())
                    .tracking(DS.Typo.displayTrackingTight)
                    .foregroundStyle(DS.Color.ink)
            } else {
                Text("?")
                    .font(DS.Typo.displayXL())
                    .foregroundStyle(DS.Color.mutedSoft)
            }
            DifficultyPill(difficulty: round.word.difficulty)
            Spacer()
            Text("\(countdown)")
                .font(DS.Typo.displayMD())
                .foregroundStyle(DS.Color.primary)
                .opacity(countdown > 0 ? 1 : 0)
                .frame(width: 60, height: 60)
                .background(Circle().stroke(DS.Color.primary.opacity(0.25), lineWidth: 2))
            Spacer()
        }
        .onAppear {
            timer?.invalidate()
            countdown = 3
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
                countdown -= 1
                if countdown <= 0 {
                    t.invalidate()
                    begin()
                }
            }
        }
        .onDisappear { timer?.invalidate() }
    }

}

private struct DifficultyPill: View {
    let difficulty: Difficulty
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(i < dotsFilled ? color : DS.Color.hairline)
                    .frame(width: 6, height: 6)
            }
            Text(label)
                .font(DS.Typo.captionUpper())
                .tracking(DS.Typo.captionUpperTracking)
                .foregroundStyle(color)
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, 5)
        .background(Capsule().fill(color.opacity(0.12)))
    }
    private var dotsFilled: Int {
        switch difficulty {
        case .easy: return 1
        case .medium: return 2
        case .hard: return 3
        }
    }
    private var label: String {
        switch difficulty {
        case .easy: return "简单"
        case .medium: return "中等"
        case .hard: return "困难"
        }
    }
    private var color: Color {
        switch difficulty {
        case .easy: return DS.Color.success
        case .medium: return DS.Color.accentTeal
        case .hard: return DS.Color.error
        }
    }
}

// MARK: - AI drawing (player guesses)

private struct AIDrawingScreen: View {
    let round: Round
    let dataset: QuickDrawDataset?
    let store: GameStore
    @State private var input: String = ""
    @State private var sketch: Sketch?
    @State private var timeRemaining: Int = Int(GameStore.aiDrawTimeLimit)
    @State private var ticker: Timer?
    @State private var wrongFlash: Bool = false
    @State private var wrongMessage: String? = nil
    @State private var replayKey: Int = 0

    private var hintLevel: Int {
        let elapsed = Int(GameStore.aiDrawTimeLimit) - timeRemaining
        if elapsed >= 50 { return 3 }
        if elapsed >= 35 { return 2 }
        if elapsed >= 20 { return 1 }
        return 0
    }

    var body: some View {
        VStack(spacing: DS.Space.md) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 12, weight: .medium))
                    Text("\(timeRemaining)s").monospacedDigit()
                }
                .font(DS.Typo.caption())
                .foregroundStyle(timeRemaining <= 10 ? DS.Color.error : DS.Color.muted)
                Spacer()
                Button("跳过 (\(store.skipsRemaining))") { store.requestSkip() }
                    .buttonStyle(CoralTextLinkButtonStyle())
                    .disabled(store.skipsRemaining == 0)
                    .opacity(store.skipsRemaining == 0 ? 0.4 : 1)
            }
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let sketch {
                        QuickDrawPlaybackView(sketch: sketch, speed: 2.0, lineWidth: 4)
                            .id(replayKey)
                            .frame(maxWidth: .infinity)
                    } else {
                        ContentUnavailableView("没有 \(round.word.id) 的草图",
                                               systemImage: "exclamationmark.triangle")
                    }
                }
                .frame(maxHeight: .infinity)
                if sketch != nil {
                    Button {
                        replayKey &+= 1
                        Haptics.light()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 12, weight: .medium))
                            Text("重播")
                                .font(DS.Typo.caption())
                        }
                        .foregroundStyle(DS.Color.muted)
                        .padding(.horizontal, DS.Space.sm)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(DS.Color.canvas))
                        .overlay(Capsule().stroke(DS.Color.hairline, lineWidth: 1))
                    }
                    .padding(DS.Space.xs)
                }
            }
            .creamCard(padding: DS.Space.md)
            HintRow(level: hintLevel, word: round.word)
            if let wrongMessage {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                    Text("「\(wrongMessage)」不对，再试")
                }
                .font(DS.Typo.bodySM())
                .foregroundStyle(DS.Color.error)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: DS.Space.sm) {
                TextField("输入答案", text: $input)
                    .textFieldStyle(.plain)
                    .font(DS.Typo.bodyMD())
                    .foregroundStyle(DS.Color.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .fill(DS.Color.canvas)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .stroke(wrongFlash ? DS.Color.error : DS.Color.hairline,
                                    lineWidth: wrongFlash ? 2 : 1)
                    )
                    .onSubmit { submit() }
                Button("提交") { submit() }
                    .buttonStyle(CoralPrimaryButtonStyle(isFullWidth: false))
            }
        }
        .onChange(of: store.wrongGuessNonce) { _, _ in
            guard let last = store.lastWrongGuess else { return }
            wrongMessage = last
            Haptics.error()
            withAnimation(.easeOut(duration: 0.15)) { wrongFlash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeIn(duration: 0.2)) { wrongFlash = false }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                if wrongMessage == last { wrongMessage = nil }
            }
        }
        .onAppear {
            sketch = (try? dataset?.randomSketch(for: round.word.id))
            timeRemaining = Int(GameStore.aiDrawTimeLimit)
            ticker?.invalidate()
            ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                timeRemaining -= 1
                if timeRemaining <= 0 { store.handleTimeout() }
            }
        }
        .onDisappear { ticker?.invalidate() }
    }

    private func submit() {
        guard !input.isEmpty else { return }
        store.submitPlayerGuess(input)
        input = ""
    }
}

private struct HintRow: View {
    let level: Int
    let word: Word

    var body: some View {
        Group {
            switch level {
            case 0:
                EmptyView()
            case 1:
                HintLine(icon: "lightbulb",
                         text: "提示：共 \(word.text.count) 个字")
            case 2:
                HintLine(icon: "lightbulb.fill",
                         text: "提示：首字「\(firstChar(of: word.text))」")
            default:
                HintLine(icon: "lightbulb.fill",
                         text: "提示：英文是「\(word.id)」")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func firstChar(of s: String) -> String {
        guard let f = s.first else { return "?" }
        return String(f)
    }
}

private struct HintLine: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 12, weight: .medium))
            Text(text).font(DS.Typo.bodySM())
        }
        .foregroundStyle(DS.Color.accentAmber)
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.sm)
                .fill(DS.Color.accentAmber.opacity(0.12))
        )
    }
}

// MARK: - Player drawing (AI guesses)

private struct PlayerDrawingScreen: View {
    let round: Round
    let store: GameStore
    @State private var drawing = PKDrawing()
    @State private var canvasSize: CGSize = .zero
    @State private var timeRemaining: Int = Int(GameStore.playerDrawTimeLimit)
    @State private var ticker: Timer?
    @State private var didSubmit = false
    @State private var cursorBlink = false
    @State private var blinkTimer: Timer?

    var body: some View {
        VStack(spacing: DS.Space.sm) {
            HStack {
                HStack(spacing: 6) {
                    Text("画").font(DS.Typo.caption()).foregroundStyle(DS.Color.muted)
                    Text(round.word.text)
                        .font(DS.Typo.titleLG())
                        .foregroundStyle(DS.Color.ink)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 12, weight: .medium))
                    Text("\(timeRemaining)s").monospacedDigit()
                }
                .font(DS.Typo.caption())
                .foregroundStyle(timeRemaining <= 10 ? DS.Color.error : DS.Color.muted)
            }
            GeometryReader { geo in
                PlayerCanvasView(drawing: $drawing)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.lg)
                            .fill(DS.Color.surfaceCard)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.lg)
                            .stroke(DS.Color.hairline, lineWidth: 1)
                    )
                    .onAppear { canvasSize = geo.size }
                    .onChange(of: geo.size) { _, new in canvasSize = new }
            }
            .frame(maxHeight: .infinity)
            if !store.currentGuessText.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Text("AI")
                        .font(DS.Typo.captionUpper())
                        .tracking(DS.Typo.captionUpperTracking)
                        .foregroundStyle(DS.Color.onPrimary)
                        .padding(.horizontal, DS.Space.xs)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(DS.Color.primary))
                    HStack(spacing: 2) {
                        Text(store.currentGuessText)
                            .font(DS.Typo.bodyMD())
                            .foregroundStyle(DS.Color.ink)
                            .contentTransition(.opacity)
                            .id(store.currentGuessText)
                        Rectangle()
                            .fill(DS.Color.primary)
                            .frame(width: 2, height: 16)
                            .opacity(cursorBlink ? 1 : 0)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.sm)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .fill(DS.Color.surfaceSoft)
                )
                .transition(.opacity)
            }
            HStack(spacing: DS.Space.sm) {
                Button("清空") { drawing = PKDrawing() }
                    .buttonStyle(CreamSecondaryButtonStyle())
                Spacer()
                Button(didSubmit ? "等待 AI…" : "让 AI 猜") { submit() }
                    .buttonStyle(CoralPrimaryButtonStyle(isFullWidth: false))
                    .disabled(didSubmit || drawing.strokes.isEmpty)
                    .opacity((didSubmit || drawing.strokes.isEmpty) ? 0.6 : 1)
            }
        }
        .onAppear {
            timeRemaining = Int(GameStore.playerDrawTimeLimit)
            ticker?.invalidate()
            ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                timeRemaining -= 1
                // Auto-submit at 5s remaining if there's anything drawn and we
                // haven't sent it yet.
                if timeRemaining == 5, !didSubmit, !drawing.strokes.isEmpty {
                    Haptics.warning()
                    submit()
                }
                if timeRemaining <= 0 { store.handleTimeout() }
            }
            blinkTimer?.invalidate()
            blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { _ in
                cursorBlink.toggle()
            }
        }
        .onDisappear {
            ticker?.invalidate()
            blinkTimer?.invalidate()
        }
    }

    private func submit() {
        guard let jpeg = DrawingExporter.exportForVLM(drawing, canvasSize: canvasSize) else {
            return
        }
        didSubmit = true
        store.submitPlayerDrawing(jpeg)
    }
}

// MARK: - Reveal

private struct RevealScreen: View {
    let round: Round
    let outcome: Outcome
    let delta: Int
    let multiplier: Double
    let score: Score
    let next: () -> Void

    @State private var displayedTotal: Int = 0
    @State private var autoAdvance: Double = 0
    @State private var advanceTimer: Timer?
    private let advanceWindow: TimeInterval = 4.0

    var body: some View {
        VStack(spacing: DS.Space.lg) {
            Spacer()
            Text(outcomeBadge)
                .font(DS.Typo.captionUpper())
                .tracking(DS.Typo.captionUpperTracking)
                .foregroundStyle(DS.Color.onPrimary)
                .padding(.horizontal, DS.Space.sm)
                .padding(.vertical, 4)
                .background(Capsule().fill(badgeColor))
            Text(title)
                .font(DS.Typo.displayLG())
                .tracking(DS.Typo.displayTrackingTight)
                .foregroundStyle(DS.Color.ink)
            VStack(spacing: 6) {
                Text("答案").font(DS.Typo.caption()).foregroundStyle(DS.Color.muted)
                Text(round.word.text)
                    .font(DS.Typo.displaySM())
                    .foregroundStyle(DS.Color.ink)
            }
            // Delta with optional streak multiplier badge.
            VStack(spacing: 6) {
                if delta > 0 {
                    HStack(spacing: 6) {
                        Text("+\(delta)")
                            .font(DS.Typo.titleLG())
                            .foregroundStyle(DS.Color.success)
                        if multiplier > 1.0 {
                            Text(String(format: "×%.2f streak", multiplier))
                                .font(DS.Typo.caption())
                                .foregroundStyle(DS.Color.accentAmber)
                                .padding(.horizontal, DS.Space.xs)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(DS.Color.accentAmber.opacity(0.15)))
                        }
                    }
                }
                HStack(spacing: DS.Space.xs) {
                    Text("当前分数").font(DS.Typo.caption()).foregroundStyle(DS.Color.muted)
                    Text("\(displayedTotal)")
                        .font(DS.Typo.titleLG())
                        .monospacedDigit()
                        .foregroundStyle(DS.Color.primary)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, DS.Space.md)
                .padding(.vertical, DS.Space.xs)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .stroke(DS.Color.hairline, lineWidth: 1)
                )
            }
            Spacer()
            Button {
                advanceTimer?.invalidate()
                next()
            } label: {
                ZStack(alignment: .leading) {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .fill(DS.Color.primaryActive.opacity(0.55))
                            .frame(width: geo.size.width * autoAdvance)
                    }
                    Text("下一局")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(CoralPrimaryButtonStyle())
            Text("\(Int(advanceWindow - autoAdvance * advanceWindow + 0.5))s 后自动开始")
                .font(DS.Typo.caption())
                .foregroundStyle(DS.Color.muted)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            displayedTotal = score.total - delta
            withAnimation(.easeOut(duration: 0.6)) {
                displayedTotal = score.total
            }
            // Auto-advance after `advanceWindow` seconds. The user can tap to
            // skip the wait. Progress fills the button as a visual cue.
            autoAdvance = 0
            advanceTimer?.invalidate()
            let interval: TimeInterval = 0.05
            let step = interval / advanceWindow
            advanceTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { t in
                autoAdvance += step
                if autoAdvance >= 1 {
                    t.invalidate()
                    next()
                }
            }
        }
        .onDisappear { advanceTimer?.invalidate() }
    }

    private var isWin: Bool { if case .correct = outcome { return true } else { return false } }
    private var outcomeBadge: String {
        switch outcome {
        case .correct: return "WIN"
        case .timedOut: return "TIME OUT"
        case .skipped: return "SKIPPED"
        }
    }
    private var title: String {
        switch outcome {
        case .correct: return "猜对了！"
        case .timedOut: return "时间到了"
        case .skipped: return "已跳过"
        }
    }
    private var badgeColor: Color {
        switch outcome {
        case .correct: return DS.Color.success
        case .timedOut: return DS.Color.error
        case .skipped: return DS.Color.muted
        }
    }
}

// MARK: - Game over

private struct GameOverScreen: View {
    let score: Score
    let rounds: [RoundResult]
    let again: () -> Void
    @State private var isPersonalBest: Bool = false
    @State private var prevBest: Int = 0

    var body: some View {
        ScrollView {
            VStack(spacing: DS.Space.lg) {
                Text(isPersonalBest ? "NEW BEST" : "GAME OVER")
                    .font(DS.Typo.captionUpper())
                    .tracking(DS.Typo.captionUpperTracking)
                    .foregroundStyle(isPersonalBest ? DS.Color.accentAmber : DS.Color.muted)
                Text(isPersonalBest ? "新的最高分" : "游戏结束")
                    .font(DS.Typo.displayLG())
                    .tracking(DS.Typo.displayTrackingTight)
                    .foregroundStyle(DS.Color.ink)
                VStack(spacing: DS.Space.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Space.xs) {
                        Text("\(score.total)")
                            .font(DS.Typo.displayXL())
                            .tracking(DS.Typo.displayTrackingTight)
                            .foregroundStyle(DS.Color.primary)
                        Text("分").font(DS.Typo.titleMD()).foregroundStyle(DS.Color.muted)
                    }
                    Text("猜中 \(score.roundsCorrect) / \(rounds.count) 局")
                        .font(DS.Typo.bodyMD())
                        .foregroundStyle(DS.Color.body)
                    if isPersonalBest, prevBest > 0 {
                        Text("超过上次最佳 \(score.total - prevBest) 分")
                            .font(DS.Typo.caption())
                            .foregroundStyle(DS.Color.success)
                    }
                    if let bestStreak = computeBestStreak(rounds), bestStreak >= 2 {
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill").font(.system(size: 12))
                            Text("最高连击 ×\(bestStreak)")
                                .font(DS.Typo.caption())
                        }
                        .foregroundStyle(DS.Color.accentAmber)
                        .padding(.horizontal, DS.Space.sm)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(DS.Color.accentAmber.opacity(0.15)))
                    }
                }
                .padding(DS.Space.xl)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .fill(isPersonalBest ? DS.Color.accentAmber.opacity(0.15) : DS.Color.surfaceCard)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .stroke(isPersonalBest ? DS.Color.accentAmber : Color.clear, lineWidth: 2)
                )

                // Per-round breakdown
                if !rounds.isEmpty {
                    VStack(alignment: .leading, spacing: DS.Space.sm) {
                        Text("ROUND BREAKDOWN")
                            .font(DS.Typo.captionUpper())
                            .tracking(DS.Typo.captionUpperTracking)
                            .foregroundStyle(DS.Color.muted)
                        ForEach(Array(rounds.enumerated()), id: \.offset) { idx, r in
                            RoundResultRow(index: idx + 1, result: r)
                        }
                    }
                }

                HStack(spacing: DS.Space.sm) {
                    ShareLink(item: shareSummary) {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                            Text("分享")
                        }
                    }
                    .buttonStyle(CreamSecondaryButtonStyle())
                    Button("再来一局", action: again)
                        .buttonStyle(CoralPrimaryButtonStyle(isFullWidth: true))
                }
                .padding(.top, DS.Space.md)
            }
        }
        .onAppear {
            prevBest = BestScoreStore.current()?.total ?? 0
            isPersonalBest = BestScoreStore.recordIfBest(
                total: score.total,
                rounds: rounds.count,
                correct: score.roundsCorrect
            )
            if isPersonalBest { Haptics.success() }
        }
    }

    private var shareSummary: String {
        var lines: [String] = []
        lines.append("我在 AI Draw Something 拿了 \(score.total) 分")
        lines.append("猜中 \(score.roundsCorrect)/\(rounds.count) 局")
        if let best = computeBestStreak(rounds), best >= 2 {
            lines.append("最高连击 ×\(best) 🔥")
        }
        return lines.joined(separator: "\n")
    }

    private func computeBestStreak(_ rs: [RoundResult]) -> Int? {
        var best = 0
        var current = 0
        for r in rs {
            if r.didWin { current += 1; best = max(best, current) }
            else        { current = 0 }
        }
        return best == 0 ? nil : best
    }
}

private struct RoundResultRow: View {
    let index: Int
    let result: RoundResult

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Text("\(index)")
                .font(DS.Typo.captionUpper())
                .tracking(0.5)
                .foregroundStyle(DS.Color.muted)
                .frame(width: 24, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.round.word.text)
                    .font(DS.Typo.titleSM())
                    .foregroundStyle(DS.Color.ink)
                Text(roundKindLabel)
                    .font(DS.Typo.caption())
                    .foregroundStyle(DS.Color.muted)
            }
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                Text(result.didWin ? "+\(result.points)" : "—")
                    .font(DS.Typo.titleSM())
                    .monospacedDigit()
                    .foregroundStyle(result.didWin ? DS.Color.ink : DS.Color.muted)
            }
        }
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.sm)
        .background(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .fill(DS.Color.surfaceSoft)
        )
    }

    private var roundKindLabel: String {
        result.round.kind == .aiDraws ? "AI 画 · 你猜" : "你画 · AI 猜"
    }
    private var iconName: String {
        switch result.outcome {
        case .correct: return "checkmark.circle.fill"
        case .timedOut: return "clock.badge.exclamationmark"
        case .skipped: return "forward.fill"
        }
    }
    private var iconColor: Color {
        switch result.outcome {
        case .correct: return DS.Color.success
        case .timedOut: return DS.Color.error
        case .skipped: return DS.Color.muted
        }
    }
}
