import SwiftUI

struct PortfolioView: View {
    @Environment(DropletStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    hero
                    if store.holdings.isEmpty {
                        emptyState
                    } else {
                        Card {
                            AllocationChart(holdings: store.holdings)
                        }
                        holdings
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .navigationTitle("Portfolio")
            .refreshable { await store.load() }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.s) {
                Text("Invested from round-ups")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: Theme.Spacing.s)
                SimulatedBadge()
            }
            Text(Money.format(cents: store.totalInvestedCents))
                .heroNumber()
                .contentTransition(.numericText(value: Double(store.totalInvestedCents)))
                .animation(Theme.spring, value: store.totalInvestedCents)
        }
        .padding(.horizontal, Theme.Spacing.xs)
        .accessibilityElement(children: .combine)
    }

    private var holdings: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text("Holdings")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.Spacing.xs)
                .accessibilityAddTraits(.isHeader)
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(store.holdings) { holding in
                        HoldingRow(holding: holding)
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
            }
            Text("Amounts are what was invested, not current value. Fills are simulated at the live True Markets price.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.Spacing.xs)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No drops invested yet",
            systemImage: "chart.pie",
            description: Text("Your first drop lands at \(Money.format(cents: store.summary.thresholdCents)).")
        )
        .padding(.top, Theme.Spacing.l)
    }
}

/// Small capsule that marks investments as simulated. Content layer, so no glass.
struct SimulatedBadge: View {
    var body: some View {
        Text("Simulated")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, Theme.Spacing.xs)
            .background(.fill.tertiary, in: .capsule)
            .accessibilityLabel("Simulated trades")
    }
}

#Preview("Portfolio") {
    let store = DropletStore(api: PreviewDropletAPI())
    PortfolioView()
        .environment(store)
        .task { await store.load() }
}

#Preview("Portfolio, empty") {
    let store = DropletStore(api: PreviewDropletAPI(seed: .empty))
    PortfolioView()
        .environment(store)
        .task { await store.load() }
}
