# AI Draw Something

iOS 单机猜词游戏：AI 用 QuickDraw 笔画演示让玩家猜，玩家画的图片由多模态模型来猜。

**当前状态：MVP（无服务器，BYOK 测试游戏性）**

完整设计见 `/root/.claude/plans/ai-draw-something-ios-api-key-squishy-narwhal.md`，
包含 App Attest、Cloudflare Worker、StoreKit IAP、邀请码等生产级组件。本仓库
当前只实现 MVP，验证核心循环。

## 目录结构

```
App/                              # iOS app target
  AIDrawSomethingApp.swift
  RootView.swift                  # 阶段路由 + 各 Phase 视图
  SettingsSheet.swift             # BYOK key 输入 + provider 选择
  Info.plist
Packages/
  GameCore/                       # 状态机、计分、出题、GuessClient 协议
  Drawing/                        # 笔画模型、QuickDraw 回放、PencilKit 包装、JPEG 导出
                                  #   - 内置 sketches.json 种子集（6 类 × 1 张）
  Networking/                     # SSEStream + DirectGuessClient（BYOK，直连模型 API）
  Persistence/                    # Keychain + UserDefaults helper
Worker/                           # Cloudflare Worker（生产路径，未来替换 BYOK）
  src/
    index.ts                      # 路由 + 防滥用栈
    schema.ts                     # zod 形状锁
    provider.ts + anthropic.ts + openai.ts + parser.ts
    sse.ts                        # 下行 SSE 通道（仅 guess/final/giveUp）
    attest/verify.ts              # App Attest 验证（attestation + assertion）
    durable/{nonce,ratelimit,entitlement}.ts
  test/                           # vitest（22 用例）
  wrangler.toml
```

## 在 Xcode 里跑起来

1. **新建 iOS App 工程**（Xcode → File → New → Project → App，SwiftUI、Swift、iOS 17+）
   - Bundle ID 任意，例如 `com.example.aidraw`
   - 把工程文件放到 `AI_Draw_Something/` 目录下，与 `Packages/` 同级

2. **添加本地 SPM 依赖**：File → Add Package Dependencies → Add Local
   - 依次加 `Packages/GameCore`、`Packages/Drawing`、`Packages/Networking`、`Packages/Persistence`
   - 在 App target 的 General → Frameworks 里把这四个 library 加进去

3. **替换 App 模板文件**：
   - 删掉 Xcode 默认生成的 `ContentView.swift` 和 `<YourApp>App.swift`
   - 把仓库里的 `App/AIDrawSomethingApp.swift`、`App/RootView.swift`、`App/SettingsSheet.swift` 拖到 App target
   - 把 `App/Info.plist` 内容合并到 Xcode 自动生成的 Info.plist（或直接替换）

4. **真机或模拟器跑起来**

5. **填 API Key**：右上角齿轮 → 设置页 → 粘贴你自己的 Anthropic 或 OpenAI key
   - Anthropic key: <https://console.anthropic.com/settings/keys>
   - OpenAI key: <https://platform.openai.com/api-keys>
   - Key 存进设备 Keychain，不出设备

## MVP 限制（与生产版的差距）

| 能力 | MVP | 生产 |
|---|---|---|
| API key 保护 | 用户 BYOK 存 Keychain | Cloudflare Worker secret + App Attest |
| QuickDraw 数据 | 6 类 × 1 张手绘种子 | ~100 类 × 30 张 zstd 压缩二进制 |
| 反滥用 | 无 | App Attest + 限流 + 花费熔断 + 形状锁 |
| 付费 / 订阅 | 无 | StoreKit 2 IAP + EntitlementDO |
| 邀请奖励 | 无 | 邀请码 + 反作弊聚合 |
| GameCenter 排行 | 无 | 单一榜单 ID |
| Provider 切换 | 用户在设置里选 | 同上 + Worker 自动 fallback |

## 玩法

- 6 局，AI 和玩家轮流画
- AI 画时：屏幕回放笔画，玩家在文本框输入猜测，匹配即得分
- 玩家画时：用 PencilKit 在画布上画，点"让 AI 猜"上传，AI 流式输出 `是不是 X？`，匹配 round 答案就算赢
- 难度递增：1-2 简单，3-4 中等，5-6 困难
- 计分按难度 base × 时间 ratio（time-bonus 越快越高）

## 开发与测试

```bash
# 跑 GameCore 单测（在 Packages/GameCore 下）
cd Packages/GameCore && swift test

# 跑 Worker 测试 + 类型检查
cd Worker
npm install
npx tsc --noEmit
npx vitest run
```

iOS UI 必须在 Xcode + macOS 上跑，本仓库里的命令行工具链不能编译 PencilKit / SwiftUI iOS 部分。

## Worker 部署（生产路径，可选）

MVP 不需要 Worker 也能跑（BYOK 直连）。要切到 Attest+Worker 模式：

```bash
cd Worker
npx wrangler kv:namespace create "KV"     # 把返回的 id 填进 wrangler.toml
npx wrangler secret put ANTHROPIC_API_KEY # 粘贴 key
npx wrangler secret put OPENAI_API_KEY    # 可选
npx wrangler secret put REFERRAL_HMAC_SECRET
npx wrangler secret put DEV_BYPASS_SECRET # 仅 ENV=dev 时生效
npx wrangler deploy
```

然后修改 `wrangler.toml` 里的 `APPLE_TEAM_ID` 和 `APPLE_BUNDLE_ID`。
iOS 端把 `DirectGuessClient` 换成（待写的）`AttestedGuessClient`，指向部署后的 Worker URL。

## License & Attribution

- 代码：MIT（待加 LICENSE）
- 草图风格：将来切到 Google Quick, Draw! 数据集时，必须在"关于"页声明
  *Sketches from the Google Quick, Draw! dataset, CC BY 4.0*。
  当前 `sketches.json` 是手工画的合成数据，不需要署名。
