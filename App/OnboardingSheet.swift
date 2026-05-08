import SwiftUI
import Persistence

/// First-launch tutorial. Three pages walking through what the game is, how
/// to win on AI-draws rounds, and how to win on player-draws rounds. Persists
/// completion in UserDefaults so it never re-shows.
struct OnboardingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page: Int = 0

    private let pages: [OnboardingPage] = [
        .init(eyebrow: "AI DRAW",
              headline: "AI 和你\n轮流出题",
              body: "六个回合，AI 和你轮流出题画画。AI 用 QuickDraw 笔画演示，你画的图让多模态模型来猜。",
              icon: "person.2"),
        .init(eyebrow: "ROUND TYPE 1",
              headline: "AI 画 · 你来猜",
              body: "AI 用动画演示一只猫、一座房子……你在文本框里输入答案。20 秒后会给字数提示，再过会儿露首字。",
              icon: "eye"),
        .init(eyebrow: "ROUND TYPE 2",
              headline: "你画 · AI 来猜",
              body: "用手指或 Apple Pencil 画 45 秒，点「让 AI 猜」上传，AI 流式吐「是不是 X？」。需要在设置里粘 Anthropic 或 OpenAI 的 API key。",
              icon: "scribble.variable")
    ]

    var body: some View {
        ZStack {
            DS.Color.canvas.ignoresSafeArea()
            VStack(spacing: DS.Space.lg) {
                HStack {
                    Spacer()
                    Button("跳过") { finish() }
                        .buttonStyle(CoralTextLinkButtonStyle())
                }
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { idx in
                        OnboardingPageView(page: pages[idx])
                            .tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                HStack(spacing: 6) {
                    ForEach(pages.indices, id: \.self) { idx in
                        Capsule()
                            .fill(idx == page ? DS.Color.primary : DS.Color.hairline)
                            .frame(width: idx == page ? 24 : 8, height: 8)
                            .animation(.easeInOut(duration: 0.2), value: page)
                    }
                }
                Button(page == pages.count - 1 ? "开始游戏" : "下一步") {
                    if page == pages.count - 1 {
                        finish()
                    } else {
                        withAnimation { page += 1 }
                    }
                }
                .buttonStyle(CoralPrimaryButtonStyle())
            }
            .padding(DS.Space.lg)
        }
        .preferredColorScheme(.light)
        .interactiveDismissDisabled()
    }

    private func finish() {
        OnboardingState.didOnboard = true
        dismiss()
    }
}

private struct OnboardingPage: Identifiable {
    let id = UUID()
    let eyebrow: String
    let headline: String
    let body: String
    let icon: String
}

private struct OnboardingPageView: View {
    let page: OnboardingPage
    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            ZStack {
                Circle()
                    .fill(DS.Color.surfaceCard)
                    .frame(width: 96, height: 96)
                Image(systemName: page.icon)
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(DS.Color.primary)
            }
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Text(page.eyebrow)
                    .font(DS.Typo.captionUpper())
                    .tracking(DS.Typo.captionUpperTracking)
                    .foregroundStyle(DS.Color.muted)
                Text(page.headline)
                    .font(DS.Typo.displayMD())
                    .tracking(DS.Typo.displayTrackingTight)
                    .foregroundStyle(DS.Color.ink)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(page.body)
                    .font(DS.Typo.bodyMD())
                    .foregroundStyle(DS.Color.body)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, DS.Space.xs)
    }
}
