import SwiftUI

/// Spending hero: a drop that fills as pending round-ups approach the threshold.
struct DropGauge: View {
    let progress: Double
    let pendingCents: Int
    let thresholdCents: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var level: Double = 0

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.l))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.xl))
        layout {
            drop
                .frame(width: 104, height: 136)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(Money.format(cents: pendingCents))
                    .heroNumber()
                    .contentTransition(.numericText(value: Double(pendingCents)))
                Text("of \(Money.format(cents: thresholdCents))")
                    .font(.title3.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text("until your next drop")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Theme.spring, value: pendingCents)
        .onAppear { setLevel(progress) }
        .onChange(of: progress) { _, newValue in setLevel(newValue) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(pendingCents: pendingCents, thresholdCents: thresholdCents))
        .accessibilityValue("\(Int((Self.clamp(progress) * 100).rounded())) percent")
    }

    private var drop: some View {
        ZStack {
            DropShape()
                .fill(Theme.accent.opacity(0.12))
            water
                .clipShape(DropShape())
            DropShape()
                .stroke(Theme.accent.opacity(0.45), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var water: some View {
        if reduceMotion {
            WaterShape(level: level, phase: 0, amplitude: 0)
                .fill(Theme.accent.gradient)
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: level <= 0)) { context in
                let seconds = context.date.timeIntervalSinceReferenceDate
                WaterShape(level: level, phase: seconds * 2 * .pi / 3.2, amplitude: 2.5)
                    .fill(Theme.accent.gradient)
            }
        }
    }

    private func setLevel(_ value: Double) {
        let target = Self.clamp(value)
        if reduceMotion {
            level = target
        } else {
            withAnimation(Theme.spring) { level = target }
        }
    }

    static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }

    /// "3 dollars 21 cents of 5 dollars until your next drop"
    static func accessibilityLabel(pendingCents: Int, thresholdCents: Int) -> String {
        "\(spokenAmount(cents: pendingCents)) of \(spokenAmount(cents: thresholdCents)) until your next drop"
    }

    /// 321 → "3 dollars 21 cents", 500 → "5 dollars", 21 → "21 cents", 0 → "0 dollars".
    static func spokenAmount(cents: Int) -> String {
        let dollars = abs(cents) / 100
        let remainder = abs(cents) % 100
        var parts: [String] = []
        if dollars > 0 || remainder == 0 { parts.append("\(dollars) \(dollars == 1 ? "dollar" : "dollars")") }
        if remainder > 0 { parts.append("\(remainder) \(remainder == 1 ? "cent" : "cents")") }
        return (cents < 0 ? "minus " : "") + parts.joined(separator: " ")
    }
}

/// The water body: filled from the bottom up to `level` (0...1) with a sine-wave surface.
struct WaterShape: Shape {
    var level: Double
    var phase: Double
    var amplitude: CGFloat

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clamped = min(max(level, 0), 1)
        guard clamped > 0 else { return Path() }
        let surfaceY = rect.maxY - rect.height * CGFloat(clamped)
        let steps = 32
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        for step in 0...steps {
            let fraction = Double(step) / Double(steps)
            let x = rect.minX + rect.width * CGFloat(fraction)
            let y = surfaceY + amplitude * CGFloat(sin(fraction * 2 * .pi + phase))
            path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview("DropGauge") {
    @Previewable @State var pending = 321
    VStack(spacing: Theme.Spacing.xl) {
        Card {
            DropGauge(progress: Double(pending) / 500, pendingCents: pending, thresholdCents: 500)
        }
        Button("Add a round-up") { pending = min(500, pending + 33) }
            .buttonStyle(.glassProminent)
        Card {
            DropGauge(progress: 0, pendingCents: 0, thresholdCents: 1_000)
        }
    }
    .padding(Theme.Spacing.l)
}
