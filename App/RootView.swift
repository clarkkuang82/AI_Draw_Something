import SwiftUI
import PencilKit
import GameCore
import Drawing
#if canImport(Commerce)
import Commerce
#endif

struct RootView: View {
    let services: AppServices
    let dataset: QuickDrawDataset?
    @State private var showSettings = false
    @State private var showPaywall = false

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
                                start: { startTapped() }
                            )
                        case .loading:
                            ProgressView().tint(DS.Color.primary)
                        case .showWord(let round):
                            ShowWordScreen(round: round, begin: { store.beginRound() })
                        case .aiDrawing(let round):
                            AIDrawingScreen(round: round, dataset: dataset, store: store)
                        case .playerDrawing(let round):
                            PlayerDrawingScreen(round: round, store: store)
                        case .reveal(let round, let outcome):
                            RevealScreen(round: round, outcome: outcome,
                                         score: store.score,
                                         next: { store.acknowledgeReveal(); store.nextRound() })
                        case .roundOver:
                            ProgressView().tint(DS.Color.primary)
                        case .gameOver(let score):
                            GameOverScreen(score: score, again: { startTapped() })
                                .onAppear { Task { await services.leaderboard?.submit(score: score.total) } }
                        }
                    }
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
                        Text("第 \(store.roundIndex)/\(GameStore.totalRounds) 局")
                            .coralPill()
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet(store: store)
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

    private func startTapped() {
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
            store.startGame()
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

// MARK: - Anthropic-style wordmark

private struct AppWordmark: View {
    var body: some View {
        HStack(spacing: 6) {
            // Stand-in for the Anthropic spike-mark — a 4-spoke radial.
            Image(systemName: "asterisk")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DS.Color.ink)
            Text("AI Draw")
                .font(DS.Typo.titleSM())
                .foregroundStyle(DS.Color.ink)
        }
    }
}

// MARK: - Idle

private struct IdleScreen: View {
    let entitlementHUD: String?
    let start: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            Spacer().frame(height: DS.Space.xl)
            Text("AI DRAW")
                .font(DS.Typo.captionUpper())
                .tracking(DS.Typo.captionUpperTracking)
                .foregroundStyle(DS.Color.muted)
            Text("Meet your\ndrawing partner.")
                .font(DS.Typo.displayLG())
                .tracking(DS.Typo.displayTrackingTight)
                .foregroundStyle(DS.Color.ink)
                .lineSpacing(2)
            Text("和 AI 轮流出题画画 —— AI 用 QuickDraw 笔画演示，你画的让多模态模型来猜。")
                .font(DS.Typo.bodyMD())
                .foregroundStyle(DS.Color.body)
                .lineSpacing(4)
            if let entitlementHUD {
                Text(entitlementHUD).creamPill()
            }
            Button(action: start) { Text("开始游戏") }
                .buttonStyle(CoralPrimaryButtonStyle())
                .padding(.top, DS.Space.sm)
            Spacer()
            FeatureStripe()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FeatureStripe: View {
    var body: some View {
        HStack(spacing: DS.Space.sm) {
            FeatureChip(label: "30 个词", system: "text.book.closed")
            FeatureChip(label: "AI 视觉猜词", system: "eye")
            FeatureChip(label: "GameCenter", system: "trophy")
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
            Text("难度：\(label(for: round.word.difficulty))")
                .font(DS.Typo.bodySM())
                .foregroundStyle(DS.Color.muted)
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

    private func label(for d: Difficulty) -> String {
        switch d {
        case .easy:   return "简单"
        case .medium: return "中等"
        case .hard:   return "困难"
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

    var body: some View {
        VStack(spacing: DS.Space.md) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 12, weight: .medium))
                    Text("\(timeRemaining)s").monospacedDigit()
                }
                .font(DS.Typo.caption())
                .foregroundStyle(DS.Color.muted)
                Spacer()
                Button("跳过", action: store.handleTimeout)
                    .buttonStyle(CoralTextLinkButtonStyle())
            }
            Group {
                if let sketch {
                    QuickDrawPlaybackView(sketch: sketch, speed: 2.0, lineWidth: 4)
                        .frame(maxWidth: .infinity)
                } else {
                    ContentUnavailableView("没有 \(round.word.id) 的草图",
                                           systemImage: "exclamationmark.triangle")
                }
            }
            .frame(maxHeight: .infinity)
            .creamCard(padding: DS.Space.md)
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

// MARK: - Player drawing (AI guesses)

private struct PlayerDrawingScreen: View {
    let round: Round
    let store: GameStore
    @State private var drawing = PKDrawing()
    @State private var canvasSize: CGSize = .zero
    @State private var timeRemaining: Int = Int(GameStore.playerDrawTimeLimit)
    @State private var ticker: Timer?
    @State private var didSubmit = false

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
                .foregroundStyle(DS.Color.muted)
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
                    Text(store.currentGuessText)
                        .font(DS.Typo.bodyMD())
                        .foregroundStyle(DS.Color.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(DS.Space.sm)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .fill(DS.Color.surfaceSoft)
                )
            }
            HStack(spacing: DS.Space.sm) {
                Button("清空") { drawing = PKDrawing() }
                    .buttonStyle(CreamSecondaryButtonStyle())
                Spacer()
                Button(didSubmit ? "等待 AI…" : "让 AI 猜") { submit() }
                    .buttonStyle(CoralPrimaryButtonStyle(isFullWidth: false))
                    .disabled(didSubmit)
                    .opacity(didSubmit ? 0.6 : 1)
            }
        }
        .onAppear {
            timeRemaining = Int(GameStore.playerDrawTimeLimit)
            ticker?.invalidate()
            ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                timeRemaining -= 1
                if timeRemaining <= 0 { store.handleTimeout() }
            }
        }
        .onDisappear { ticker?.invalidate() }
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
    let score: Score
    let next: () -> Void
    var body: some View {
        VStack(spacing: DS.Space.lg) {
            Spacer()
            Text(outcomeBadge)
                .font(DS.Typo.captionUpper())
                .tracking(DS.Typo.captionUpperTracking)
                .foregroundStyle(DS.Color.onPrimary)
                .padding(.horizontal, DS.Space.sm)
                .padding(.vertical, 4)
                .background(Capsule().fill(isWin ? DS.Color.success : DS.Color.error))
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
            HStack(spacing: DS.Space.xs) {
                Text("当前分数").font(DS.Typo.caption()).foregroundStyle(DS.Color.muted)
                Text("\(score.total)")
                    .font(DS.Typo.titleLG())
                    .foregroundStyle(DS.Color.primary)
            }
            .padding(.horizontal, DS.Space.md)
            .padding(.vertical, DS.Space.xs)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(DS.Color.hairline, lineWidth: 1)
            )
            Spacer()
            Button("下一局", action: next)
                .buttonStyle(CoralPrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
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
}

// MARK: - Game over

private struct GameOverScreen: View {
    let score: Score
    let again: () -> Void
    var body: some View {
        VStack(spacing: DS.Space.lg) {
            Spacer()
            Text("GAME OVER")
                .font(DS.Typo.captionUpper())
                .tracking(DS.Typo.captionUpperTracking)
                .foregroundStyle(DS.Color.muted)
            Text("游戏结束")
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
                Text("猜中 \(score.roundsCorrect) / \(GameStore.totalRounds) 局")
                    .font(DS.Typo.bodyMD())
                    .foregroundStyle(DS.Color.body)
            }
            .padding(DS.Space.xl)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.lg)
                    .fill(DS.Color.surfaceCard)
            )
            Spacer()
            Button("再来一局", action: again)
                .buttonStyle(CoralPrimaryButtonStyle())
        }
        .frame(maxWidth: .infinity)
    }
}
