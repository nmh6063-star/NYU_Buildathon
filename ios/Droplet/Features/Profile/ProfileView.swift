import SwiftUI

struct ProfileView: View {
    @Environment(DropletStore.self) private var store
    @Environment(AppModel.self) private var appModel

    // Local mirrors keep the controls responsive while a profile update is in flight.
    @State private var threshold = 500
    @State private var targetSymbol = "SOL"
    @State private var paused = false
    @State private var selectionTick = 0
    @State private var isAddingPurchase = false
    @State private var isReconnecting = false

    static let thresholdOptions = [200, 500, 1_000]

    var body: some View {
        NavigationStack {
            List {
                account
                bank
                roundups
                developer
                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await store.signOut() }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Profile")
            .onAppear(perform: syncFromProfile)
            .onChange(of: store.profile) { syncFromProfile() }
            .onChange(of: threshold) { _, value in
                guard let profile = store.profile, value != profile.thresholdCents else { return }
                selectionTick += 1
                Task {
                    await store.setThreshold(value)
                    syncFromProfile()
                }
            }
            .onChange(of: targetSymbol) { _, value in
                guard let profile = store.profile, value != profile.targetAsset else { return }
                selectionTick += 1
                Task {
                    await store.setTargetAsset(value)
                    syncFromProfile()
                }
            }
            .onChange(of: paused) { _, value in
                guard let profile = store.profile, value != profile.roundupsPaused else { return }
                Task {
                    await store.setPaused(value)
                    syncFromProfile()
                }
            }
            .sensoryFeedback(.selection, trigger: selectionTick)
            .sheet(isPresented: $isAddingPurchase) {
                TestPurchaseSheet()
            }
            .sheet(isPresented: $isReconnecting) {
                ConnectBankView(api: appModel.api) {
                    isReconnecting = false
                    Task { await store.load() }
                }
            }
        }
    }

    private var account: some View {
        Section {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 44))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(displayName)
                        .font(.headline)
                    if let email = store.email {
                        Text(email)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, Theme.Spacing.xs)
            .accessibilityElement(children: .combine)
        }
    }

    private var displayName: String {
        let name = store.profile?.displayName.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "Droplet member" : name
    }

    private var bank: some View {
        Section("Bank") {
            LabeledContent("Institution", value: store.bank?.institutionName ?? "Not connected")
            LabeledContent("Status") {
                bankStatus
            }
            if let lastSynced = store.bank?.lastSyncedAt {
                LabeledContent("Last synced") {
                    Text(lastSynced, format: .relative(presentation: .named))
                }
            }
            if store.bank == nil || store.bank?.status == .loginRequired {
                Button(store.bank == nil ? "Connect bank" : "Reconnect bank") {
                    isReconnecting = true
                }
            }
        }
    }

    @ViewBuilder private var bankStatus: some View {
        switch store.bank?.status {
        case .active:
            statusLabel("Connected", systemImage: "checkmark.circle.fill", color: .green)
        case .loginRequired:
            statusLabel("Needs reconnect", systemImage: "exclamationmark.triangle.fill", color: .orange)
        case .error:
            statusLabel("Sync error", systemImage: "xmark.octagon.fill", color: .red)
        case nil:
            statusLabel("Not connected", systemImage: "minus.circle", color: .secondary)
        }
    }

    private func statusLabel(_ title: String, systemImage: String, color: Color) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(title)
        }
    }

    private var roundups: some View {
        Section {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Text("Invest when drops reach")
                Picker("Threshold", selection: $threshold) {
                    ForEach(Self.thresholdOptions, id: \.self) { cents in
                        Text("$\(cents / 100)").tag(cents)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(.vertical, Theme.Spacing.xs)
            Picker("Invest in", selection: $targetSymbol) {
                ForEach(store.assets) { asset in
                    Text(asset.name).tag(asset.symbol)
                }
            }
            Toggle("Pause round-ups", isOn: $paused)
        } header: {
            Text("Round-ups")
        } footer: {
            Text("When your drops reach \(Money.format(cents: threshold)), Droplet invests them in \(store.targetAsset?.name ?? targetSymbol). Trades are simulated.")
        }
        .disabled(store.profile == nil)
    }

    private var developer: some View {
        Section {
            Button {
                isAddingPurchase = true
            } label: {
                Label("Add test purchase", systemImage: "cart.badge.plus")
            }
            Button {
                Task { await store.sync() }
            } label: {
                HStack {
                    Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                    Spacer()
                    if store.isSyncing {
                        ProgressView()
                    }
                }
            }
            .disabled(store.isSyncing)
        } header: {
            Text("Developer")
        } footer: {
            Text("Sandbox only — creates a fake card purchase in Plaid Sandbox.")
        }
    }

    private func syncFromProfile() {
        guard let profile = store.profile else { return }
        threshold = profile.thresholdCents
        targetSymbol = profile.targetAsset
        paused = profile.roundupsPaused
    }
}

#Preview("Profile") {
    let api = PreviewDropletAPI()
    let store = DropletStore(api: api)
    ProfileView()
        .environment(store)
        .environment(AppModel(api: api))
        .task { await store.load() }
}
