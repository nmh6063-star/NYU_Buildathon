import SwiftUI

struct SpendingView: View {
    @Environment(DropletStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    hero
                    if store.bank?.status == .loginRequired {
                        notice("exclamationmark.triangle.fill", "Your bank needs to be reconnected. Open Profile to reconnect it.")
                    }
                    if store.profile?.roundupsPaused == true {
                        notice("pause.circle.fill", "Round-ups are paused. Resume them in Profile.")
                    }
                    if store.transactions.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.transactionsByDay) { section in
                            daySection(section)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .navigationTitle("Spending")
            .refreshable { await store.sync() }
        }
    }

    private var hero: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                DropGauge(
                    progress: store.summary.progress,
                    pendingCents: store.summary.pendingCents,
                    thresholdCents: store.summary.thresholdCents
                )
                HStack(alignment: .top) {
                    stat("Rounded up so far", Money.format(cents: store.summary.lifetimeRoundupCents))
                    Spacer(minLength: Theme.Spacing.l)
                    stat("Next drop goes to", store.targetAsset?.name ?? "—")
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    private func notice(_ symbol: String, _ text: String) -> some View {
        Card(padding: Theme.Spacing.l) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
                Image(systemName: symbol)
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.subheadline)
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if store.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, Theme.Spacing.xxl)
        } else {
            ContentUnavailableView(
                "No purchases yet",
                systemImage: "drop",
                description: Text("Add a test purchase in Profile to see your first drop.")
            )
            .padding(.top, Theme.Spacing.l)
        }
    }

    private func daySection(_ section: DaySection) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(Self.title(for: section.day))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.Spacing.xs)
                .accessibilityAddTraits(.isHeader)
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(section.items) { transaction in
                        TransactionRow(transaction: transaction)
                    }
                }
                .padding(.horizontal, Theme.Spacing.l)
            }
        }
    }

    /// "Today", "Yesterday", otherwise "Wednesday, Oct 22".
    static func title(for day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

#Preview("Spending") {
    let store = DropletStore(api: PreviewDropletAPI())
    SpendingView()
        .environment(store)
        .task { await store.load() }
}

#Preview("Spending, empty") {
    let store = DropletStore(api: PreviewDropletAPI(seed: .empty))
    SpendingView()
        .environment(store)
        .task { await store.load() }
}
