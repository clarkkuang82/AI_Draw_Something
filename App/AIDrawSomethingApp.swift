import SwiftUI
import GameCore
import Drawing

@main
struct AIDrawSomethingApp: App {
    @State private var services: AppServices = AppServices(catalog: StaticWordCatalog.mvpSeed)
    @State private var dataset: QuickDrawDataset? = {
        try? QuickDrawDataset()
    }()

    var body: some Scene {
        WindowGroup {
            RootView(services: services, dataset: dataset)
                .task { if services.isAttestedMode { await services.entitlementStore?.refresh() } }
        }
    }
}
