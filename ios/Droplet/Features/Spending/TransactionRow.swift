import SwiftUI

/// One purchase: merchant and date on the left, amount and round-up on the right.
struct TransactionRow: View {
    let transaction: Transaction

    private var isReversed: Bool { transaction.roundupStatus == .reversed }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(transaction.merchantName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                    .strikethrough(isReversed)
                    .foregroundStyle(isReversed ? .tertiary : .primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(isReversed ? .tertiary : .secondary)
            }
            Spacer(minLength: Theme.Spacing.m)
            VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                Text(Money.format(cents: -transaction.amountCents))
                    .font(.body)
                    .monospacedDigit()
                    .strikethrough(isReversed)
                    .foregroundStyle(isReversed ? .tertiary : .primary)
                roundup
            }
        }
        .padding(.vertical, Theme.Spacing.m)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let date = transaction.day.formatted(.dateTime.month(.abbreviated).day())
        if isReversed { return "\(date) · Reversed" }
        if transaction.pending { return "\(date) · Pending" }
        return date
    }

    @ViewBuilder private var roundup: some View {
        switch transaction.roundupStatus {
        case .pending:
            Text(Money.formatSigned(cents: transaction.roundupCents))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.accent)
        case .invested:
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "drop.fill")
                    .font(.caption2)
                    .accessibilityLabel("Invested")
                Text(Money.formatSigned(cents: transaction.roundupCents))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(Theme.accent)
        case .skipped, .reversed:
            Text("—")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("No round-up")
        }
    }
}

#Preview("Rows") {
    ScrollView {
        VStack(spacing: 0) {
            ForEach(PreviewSeed.demo.transactions) { transaction in
                TransactionRow(transaction: transaction)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
    }
}
