import SwiftUI

@main
struct DropletApp: App {
    @State private var appModel: AppModel
    @State private var store: DropletStore

    init() {
        let api = LiveDropletAPI(config: .fromBundle())
        _appModel = State(initialValue: AppModel(api: api))
        _store = State(initialValue: DropletStore(api: api))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .environment(store)
                .tint(Theme.accent)
                .task { await appModel.start() }
        }
    }
}
