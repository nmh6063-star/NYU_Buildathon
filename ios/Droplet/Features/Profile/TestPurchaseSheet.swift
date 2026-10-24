import SwiftUI

/// Developer sheet: stage a Plaid Sandbox purchase, then sync.
struct TestPurchaseSheet: View {
    @Environment(DropletStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var merchant = ""
    @State private var amount = ""
    @State private var submitting: String?
    @State private var failure: UserFacingError?

    struct Preset: Identifiable {
        let merchant: String
        let amountCents: Int
        let systemImage: String
        var id: String { merchant }
    }

    static let presets = [
        Preset(merchant: "Blue Bottle", amountCents: 567, systemImage: "cup.and.saucer.fill"),
        Preset(merchant: "Sweetgreen", amountCents: 1_342, systemImage: "leaf.fill"),
        Preset(merchant: "Uber", amountCents: 2_318, systemImage: "car.fill"),
    ]

    private var customCents: Int? { Self.cents(from: amount) }
    private var trimmedMerchant: String { merchant.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canAddCustom: Bool {
        customCents != nil && (1...60).contains(trimmedMerchant.count) && submitting == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Self.presets) { preset in
                        Button {
                            add(merchant: preset.merchant, cents: preset.amountCents, tag: preset.id)
                        } label: {
                            presetRow(preset)
                        }
                    }
                } header: {
                    Text("Presets")
                } footer: {
                    Text("Each purchase posts to your Sandbox bank today. Droplet then syncs and rounds it up.")
                }

                Section("Custom") {
                    TextField("Merchant", text: $merchant)
                        .textInputAutocapitalization(.words)
                    LabeledContent("Amount") {
                        TextField("0.00", text: $amount)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                    if let cents = customCents {
                        LabeledContent("Round-up") {
                            Text(Money.formatSigned(cents: Money.roundupCents(forAmountCents: cents)))
                                .monospacedDigit()
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    Button {
                        if let cents = customCents {
                            add(merchant: trimmedMerchant, cents: cents, tag: "custom")
                        }
                    } label: {
                        HStack {
                            Text("Add purchase")
                            Spacer()
                            if submitting == "custom" {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(!canAddCustom)
                }

                if let failure {
                    Section {
                        Label(failure.message, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                }
            }
            .disabled(submitting != nil)
            .animation(Theme.spring, value: customCents)
            .animation(Theme.spring, value: failure)
            .navigationTitle("Add test purchase")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func presetRow(_ preset: Preset) -> some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: preset.systemImage)
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            // Color.primary, not .primary: inside a Form button, .primary resolves to the tint.
            Text(preset.merchant)
                .foregroundStyle(Color.primary)
            Spacer()
            if submitting == preset.id {
                ProgressView()
            } else {
                VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                    Text(Money.format(cents: preset.amountCents))
                        .foregroundStyle(Color.primary)
                    Text(Money.formatSigned(cents: Money.roundupCents(forAmountCents: preset.amountCents)))
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func add(merchant: String, cents: Int, tag: String) {
        submitting = tag
        failure = nil
        Task {
            let succeeded = await store.simulatePurchase(merchant: merchant, amountCents: cents)
            submitting = nil
            if succeeded {
                dismiss()
            } else {
                // Show the error here, under the sheet's own content, instead of the hidden tab banner.
                failure = store.error
                store.error = nil
            }
        }
    }

    /// "5.67" → 567, "12" → 1200, "0.5" → 50. Nil unless 1...100_000 cents with at most 2 decimals.
    static func cents(from text: String) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        let parts = cleaned.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        let digits = Set("0123456789")
        guard (1...2).contains(parts.count),
              (1...4).contains(parts[0].count),
              parts.count == 1 || (1...2).contains(parts[1].count),
              parts.allSatisfy({ $0.allSatisfy(digits.contains) })
        else { return nil }
        let dollars = Int(parts[0]) ?? 0
        let fraction = parts.count == 2 ? (Int(parts[1].count == 1 ? parts[1] + "0" : parts[1]) ?? 0) : 0
        let total = dollars * 100 + fraction
        return (1...100_000).contains(total) ? total : nil
    }
}

#Preview("Test purchase") {
    let store = DropletStore(api: PreviewDropletAPI())
    Color.clear
        .sheet(isPresented: .constant(true)) {
            TestPurchaseSheet()
                .environment(store)
        }
        .task { await store.load() }
}
