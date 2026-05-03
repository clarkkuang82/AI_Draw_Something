import SwiftUI
import GameCore
import Drawing
import Networking
import Persistence

@main
struct AIDrawSomethingApp: App {
    @State private var gameStore: GameStore = {
        let catalog = StaticWordCatalog.mvpSeed
        let guesser = DirectGuessClient(keyResolver: { provider in
            switch provider {
            case .anthropic: return APIKeyStore.anthropicKey()
            case .openai:    return APIKeyStore.openAIKey()
            }
        })
        let store = GameStore(catalog: catalog, guesser: guesser)
        if let raw = UserDefaults.standard.string(forKey: SettingsKey.providerHint),
           let hint = ProviderHint(rawValue: raw) {
            store.providerHint = hint
        }
        return store
    }()

    @State private var dataset: QuickDrawDataset? = {
        try? QuickDrawDataset()  // uses Drawing package's bundle by default
    }()

    var body: some Scene {
        WindowGroup {
            RootView(store: gameStore, dataset: dataset)
        }
    }
}
