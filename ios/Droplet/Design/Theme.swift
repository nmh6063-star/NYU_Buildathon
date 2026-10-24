import SwiftUI

/// Design tokens. Every value here is deliberate; views use these instead of literals.
enum Theme {
    /// Droplet blue: #2F7BF6 light, #5A9BFF dark (Resources/Assets.xcassets/AccentColor).
    static let accent = Color("AccentColor")

    /// Default motion: critically damped, no bounce.
    static let spring = Animation.spring(response: 0.4, dampingFraction: 1.0)
    /// Sheets and drawers.
    static let sheetSpring = Animation.spring(response: 0.3, dampingFraction: 0.8)

    /// Hero numbers: 56 pt semibold. Pair with `.heroNumber()` for tracking, digits and Dynamic Type.
    static let heroFont = Font.system(size: 56, weight: .semibold)
    /// −0.02 em at 56 pt.
    static let heroTracking: CGFloat = -1.1

    static let cardCornerRadius: CGFloat = 24

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }
}

// MARK: - Hero number

/// 56 pt semibold, tracking −1.1, tabular digits, scaled with Dynamic Type.
struct HeroNumberModifier: ViewModifier {
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 56

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: .semibold))
            .tracking(Theme.heroTracking)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

extension View {
    func heroNumber() -> some View { modifier(HeroNumberModifier()) }
}

// MARK: - Buttons

/// Scales to 0.97 on press-down with `Theme.spring`. Under Reduce Motion it dims instead of scaling.
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(.rect)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.6 : 1)
            .animation(Theme.spring, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

// MARK: - Card

/// Content container. Never glass: cards sit in the content layer.
struct Card<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    init(padding: CGFloat = Theme.Spacing.xl, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: .rect(cornerRadius: Theme.cardCornerRadius))
    }
}

// MARK: - Error banner

/// Floating glass capsule with the error message, an optional Retry and an optional close button.
struct ErrorBanner: View {
    let error: UserFacingError
    let retry: (() -> Void)?
    var dismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
            Text(error.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button("Retry", action: retry)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.pressable)
            }
            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Dismiss")
            }
        }
        .padding(.leading, Theme.Spacing.l)
        .padding(.trailing, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.m)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
    }
}

/// Shows `error` as an `ErrorBanner` floating at the top; clearing the binding hides it.
struct ErrorBannerModifier: ViewModifier {
    @Binding var error: UserFacingError?
    let retry: (() -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let current = error {
                    ErrorBanner(error: current, retry: retry.map(wrapRetry), dismiss: { error = nil })
                        .padding(.horizontal, Theme.Spacing.l)
                        .padding(.top, Theme.Spacing.s)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        .id(current.id)
                }
            }
            .animation(Theme.spring, value: error)
    }

    private func wrapRetry(_ action: @escaping () -> Void) -> () -> Void {
        { error = nil; action() }
    }
}

extension View {
    func errorBanner(_ error: Binding<UserFacingError?>, retry: (() -> Void)? = nil) -> some View {
        modifier(ErrorBannerModifier(error: error, retry: retry))
    }
}

#Preview("Theme") {
    @Previewable @State var error: UserFacingError? = UserFacingError(message: "You're offline. Check your connection and try again.")
    ScrollView {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Text(Money.format(cents: 3_055)).heroNumber()
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Card").font(.headline)
                    Text("Content cards use the secondary background, never glass.")
                        .foregroundStyle(.secondary)
                }
            }
            Button("Pressable") {}
                .buttonStyle(.pressable)
            Button("Show error") {
                error = UserFacingError(message: "Plaid is unavailable. Try again shortly.")
            }
            .buttonStyle(.glassProminent)
        }
        .padding(Theme.Spacing.l)
    }
    .errorBanner($error, retry: {})
}
