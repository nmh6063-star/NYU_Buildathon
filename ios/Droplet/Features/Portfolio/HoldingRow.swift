import SwiftUI

/// One asset: icon, symbol and name, then invested dollars and quantity.
struct HoldingRow: View {
    let holding: Holding

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            icon
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(holding.assetSymbol)
                    .font(.body.weight(.semibold))
                Text(holding.assetName)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.m)
            VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                Text(Money.format(cents: holding.investedCents))
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                Text("\(Money.formatQuantity(holding.quantity)) \(holding.assetSymbol)")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, Theme.Spacing.m)
        .accessibilityElement(children: .combine)
    }

    private var icon: some View {
        AsyncImage(url: holding.iconUrl) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .scaledToFit()
            } else {
                Circle()
                    .fill(AllocationChart.color(for: holding.assetSymbol).opacity(0.18))
                    .overlay {
                        Text(holding.assetSymbol.prefix(1))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}

#Preview("Holdings") {
    VStack(spacing: 0) {
        ForEach(PreviewSeed.demo.holdings) { holding in
            HoldingRow(holding: holding)
        }
    }
    .padding(.horizontal, Theme.Spacing.l)
}
