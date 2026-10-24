import SwiftUI

/// Bottom-accessory content: progress ring plus "$3.21 / $5.00".
/// For a few seconds after an investment it shows "Invested $5.28 in SOL" instead.
/// The system draws the accessory's glass; this view adds none.
struct NextDropPill: View {
    let summary: DropSummary
    var celebrating: Investment? = nil

    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            if let investment = celebrating {
                Image(systemName: "drop.fill")
                    .foregroundStyle(Theme.accent)
                Text("Invested \(Money.format(cents: investment.amountCents)) in \(investment.assetSymbol)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
            } else {
                ProgressRing(progress: summary.progress)
                    .frame(width: 20, height: 20)
                Text("\(Money.format(cents: summary.pendingCents)) / \(Money.format(cents: summary.thresholdCents))")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(summary.pendingCents)))
                    .lineLimit(1)
                if placement != .inline {
                    Text("until your next drop")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .animation(Theme.spring, value: summary)
        .animation(Theme.spring, value: celebrating)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if let investment = celebrating {
            return "Invested \(DropGauge.spokenAmount(cents: investment.amountCents)) in \(investment.assetSymbol)"
        }
        return DropGauge.accessibilityLabel(pendingCents: summary.pendingCents, thresholdCents: summary.thresholdCents)
    }
}

private struct ProgressRing: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.accent.opacity(0.2), lineWidth: 3)
            Circle()
                .trim(from: 0, to: DropGauge.clamp(progress))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .accessibilityHidden(true)
    }
}

#Preview("Next drop pill") {
    VStack(spacing: Theme.Spacing.l) {
        NextDropPill(summary: PreviewSeed.demo.summary)
        NextDropPill(summary: .empty)
    }
    .padding(.vertical, Theme.Spacing.m)
    .glassEffect(.regular, in: .rect(cornerRadius: Theme.cardCornerRadius))
    .padding(Theme.Spacing.l)
}
