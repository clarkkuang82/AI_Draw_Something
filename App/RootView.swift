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
                Color(uiColor: .systemBackground).ignoresSafeArea()
                Group {
                    switch store.phase {
                    case .idle:
                        IdleScreen(
                            entitlementHUD: services.entitlementStore?.hudText,
                            start: { startTapped() }
                        )
                    case .loading:
                        ProgressView()
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
                        ProgressView()
                    case .gameOver(let score):
                        GameOverScreen(score: score, again: { startTapped() })
                            .onAppear { Task { await services.leaderboard?.submit(score: score.total) } }
                    }
                }
                .padding()
            }
            .navigationTitle("AI Draw")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
                ToolbarItem(placement: .topBarLeading) {
                    if case .idle = store.phase { EmptyView() }
                    else { Text("第 \(store.roundIndex)/\(GameStore.totalRounds) 局").font(.caption) }
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

// MARK: - Idle

private struct IdleScreen: View {
    let entitlementHUD: String?
    let start: () -> Void
    var body: some View {
        VStack(spacing: 32) {
            Text("AI Draw Something")
                .font(.largeTitle.bold())
            Text("和 AI 轮流出题画画——AI 用 QuickDraw 笔画演示，你画的让 AI 来猜。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if let entitlementHUD {
                Text(entitlementHUD)
                    .font(.callout)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
            Button(action: start) {
                Text("开始游戏")
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            Spacer()
        }
        .padding(.top, 60)
    }
}

// MARK: - Show word

private struct ShowWordScreen: View {
    let round: Round
    let begin: () -> Void
    @State private var countdown: Int = 3
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(round.kind == .aiDraws ? "AI 来画，你来猜" : "你来画，AI 来猜")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(round.word.text)
                .font(.system(size: 72, weight: .bold))
            Text("难度：\(label(for: round.word.difficulty))")
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(countdown)").font(.system(size: 48, weight: .bold))
                .opacity(countdown > 0 ? 1 : 0)
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

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("剩余 \(timeRemaining)s").monospacedDigit()
                Spacer()
                Button("跳过") { store.handleTimeout() }
                    .foregroundStyle(.red)
            }
            Group {
                if let sketch {
                    QuickDrawPlaybackView(sketch: sketch, speed: 2.0, lineWidth: 4)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.97)))
                } else {
                    ContentUnavailableView("没有 \(round.word.id) 的草图",
                                           systemImage: "exclamationmark.triangle")
                }
            }
            .frame(maxHeight: .infinity)
            HStack {
                TextField("输入答案", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submit() }
                Button("提交") { submit() }.buttonStyle(.borderedProminent)
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
        VStack(spacing: 12) {
            HStack {
                Text("画：\(round.word.text)").font(.headline)
                Spacer()
                Text("剩余 \(timeRemaining)s").monospacedDigit()
            }
            GeometryReader { geo in
                PlayerCanvasView(drawing: $drawing)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.97)))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(.gray.opacity(0.3)))
                    .onAppear { canvasSize = geo.size }
                    .onChange(of: geo.size) { _, new in canvasSize = new }
            }
            .frame(maxHeight: .infinity)
            if !store.currentGuessText.isEmpty {
                Text("AI: \(store.currentGuessText)")
                    .font(.callout)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.blue.opacity(0.08)))
            }
            HStack {
                Button("清空") { drawing = PKDrawing() }
                Spacer()
                Button(didSubmit ? "等待 AI…" : "让 AI 猜") { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(didSubmit)
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
        VStack(spacing: 24) {
            Spacer()
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(isWin ? .green : .red)
            Text("答案：\(round.word.text)").font(.title2)
            Text("当前分数：\(score.total)").font(.title3).foregroundStyle(.secondary)
            Spacer()
            Button("下一局", action: next)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
    private var isWin: Bool { if case .correct = outcome { return true } else { return false } }
    private var title: String {
        switch outcome {
        case .correct: return "猜对了！"
        case .timedOut: return "时间到"
        case .skipped: return "已跳过"
        }
    }
}

// MARK: - Game over

private struct GameOverScreen: View {
    let score: Score
    let again: () -> Void
    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("游戏结束").font(.largeTitle.bold())
            Text("总分：\(score.total)").font(.title)
            Text("猜中：\(score.roundsCorrect) / \(GameStore.totalRounds)")
                .foregroundStyle(.secondary)
            Spacer()
            Button("再来一局", action: again)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }
}
