import Charts
import SwiftUI
import UIKit

/// Donut of invested cents per asset. At most `maxSlices` sectors; the tail folds into "Other".
struct AllocationChart: View {
    let holdings: [Holding]

    struct Slice: Identifiable, Equatable {
        let id: String
        let cents: Int
        let color: Color
    }

    static let maxSlices = 6

    var body: some View {
        let slices = Self.slices(for: holdings)
        let total = slices.reduce(0) { $0 + $1.cents }
        Chart(slices) { slice in
            SectorMark(
                angle: .value("Invested", slice.cents),
                innerRadius: .ratio(0.618),
                angularInset: 1.5
            )
            .cornerRadius(4)
            .foregroundStyle(by: .value("Asset", slice.id))
            .accessibilityLabel(slice.id)
            .accessibilityValue(Money.format(cents: slice.cents))
        }
        .chartForegroundStyleScale(domain: slices.map(\.id), range: slices.map(\.color))
        .chartLegend(position: .bottom, alignment: .center, spacing: Theme.Spacing.l)
        .chartBackground { proxy in
            GeometryReader { geometry in
                if let plotFrame = proxy.plotFrame, let top = slices.first, total > 0 {
                    let frame = geometry[plotFrame]
                    VStack(spacing: 0) {
                        Text(Double(top.cents) / Double(total), format: .percent.precision(.fractionLength(0)))
                            .font(.title2.weight(.semibold))
                            .monospacedDigit()
                        Text(top.id)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .position(x: frame.midX, y: frame.midY)
                    .accessibilityHidden(true)
                }
            }
        }
        .frame(height: 240)
    }

    static func slices(for holdings: [Holding]) -> [Slice] {
        let sorted = holdings
            .filter { $0.investedCents > 0 }
            .sorted { $0.investedCents > $1.investedCents }
        let slice = { (holding: Holding) in
            Slice(id: holding.assetSymbol, cents: holding.investedCents, color: color(for: holding.assetSymbol))
        }
        guard sorted.count > maxSlices else { return sorted.map(slice) }
        let head = sorted.prefix(maxSlices - 1).map(slice)
        let rest = sorted.dropFirst(maxSlices - 1).reduce(0) { $0 + $1.investedCents }
        return head + [Slice(id: "Other", cents: rest, color: otherColor)]
    }

    /// Fixed color per curated asset, so a color always means the same asset.
    /// Categorical slots 1–6 (light/dark), validated for CVD separation on the card surfaces.
    static func color(for symbol: String) -> Color {
        switch symbol {
        case "SOL": dynamic(light: 0x2A78D6, dark: 0x3987E5)
        case "ETH": dynamic(light: 0xEB6834, dark: 0xD95926)
        case "CBBTC": dynamic(light: 0x1BAF7A, dark: 0x199E70)
        case "AAVE": dynamic(light: 0xEDA100, dark: 0xC98500)
        case "JUP": dynamic(light: 0xE87BA4, dark: 0xD55181)
        case "RENDER": dynamic(light: 0x008300, dark: 0x008300)
        default: dynamic(light: 0x6250D6, dark: 0x9085E9)
        }
    }

    static let otherColor = dynamic(light: 0x8E8E93, dark: 0x8E8E93)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            uiColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    private static func uiColor(hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

#Preview("Allocation") {
    Card {
        AllocationChart(holdings: PreviewSeed.demo.holdings)
    }
    .padding(Theme.Spacing.l)
}
