import SwiftUI
import GameCore
import Drawing

@main
struct AIDrawSomethingApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var services: AppServices
    @State private var dataset: QuickDrawDataset?

    @MainActor
    init() {
        let loaded = try? QuickDrawDataset()
        let drawableIds = loaded.map { Set($0.categoryIds) }
        _dataset = State(initialValue: loaded)
        _services = State(initialValue: AppServices(
            catalog: StaticWordCatalog.mvpSeed,
            aiDrawableIds: drawableIds
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView(services: services, dataset: dataset)
                .task { if services.isAttestedMode { await services.entitlementStore?.refresh() } }
        }
    }
}
