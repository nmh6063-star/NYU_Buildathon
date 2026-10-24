import SwiftUI

struct MainTabs: View {
    enum Destination: Hashable { case portfolio, spending, profile }

    @Environment(DropletStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var selection: Destination = .spending
    @State private var celebrating: Investment?

    var body: some View {
        @Bindable var store = store
        TabView(selection: $selection) {
            Tab("Portfolio", systemImage: "chart.pie.fill", value: Destination.portfolio) {
                PortfolioView()
            }
            Tab("Spending", systemImage: "drop.fill", value: Destination.spending) {
                SpendingView()
            }
            Tab("Profile", systemImage: "person.crop.circle.fill", value: Destination.profile) {
                ProfileView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory {
            Button {
                selection = .spending
            } label: {
                NextDropPill(summary: store.summary, celebrating: celebrating)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows your spending")
        }
        .errorBanner($store.error, retry: { Task { await store.load() } })
        .task { await store.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await store.load() }
            }
        }
        .onChange(of: store.lastInvestment) { _, investment in
            if let investment { celebrating = investment }
        }
        .task(id: celebrating?.id) {
            guard celebrating != nil else { return }
            do {
                try await Task.sleep(for: .seconds(4))
                celebrating = nil
            } catch {
                // Cancelled because a newer investment arrived; that one owns the pill now.
            }
        }
        .sensoryFeedback(.success, trigger: store.lastInvestment) { _, new in new != nil }
        .sensoryFeedback(.error, trigger: store.error) { _, new in new != nil }
    }
}

#Preview("Main tabs") {
    let api = PreviewDropletAPI()
    MainTabs()
        .environment(DropletStore(api: api))
        .environment(AppModel(api: api))
}
