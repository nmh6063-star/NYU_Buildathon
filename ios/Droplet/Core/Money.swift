import Foundation

enum Money {
    private static let usd = Decimal.FormatStyle.Currency(code: "USD", locale: Locale(identifier: "en_US"))
    private static let posix = Locale(identifier: "en_US_POSIX")
    private static let display = Locale(identifier: "en_US")

    /// 567 -> "$5.67", 0 -> "$0.00", -567 -> "-$5.67".
    static func format(cents: Int) -> String {
        (Decimal(cents) / 100).formatted(usd)
    }

    /// 33 -> "+$0.33", 0 -> "$0.00", -33 -> "-$0.33".
    static func formatSigned(cents: Int) -> String {
        cents > 0 ? "+" + format(cents: cents) : format(cents: cents)
    }

    /// Mirrors the server rule: next whole dollar minus the amount; 0 for refunds and whole dollars.
    static func roundupCents(forAmountCents amountCents: Int) -> Int {
        amountCents <= 0 ? 0 : (100 - amountCents % 100) % 100
    }

    /// "0.053137000000000000" -> "0.053137". Returns the input unchanged when it is not a number.
    static func formatQuantity(_ decimal: String, maxFractionDigits: Int = 6) -> String {
        guard let value = Decimal(string: decimal, locale: posix) else { return decimal }
        return value.formatted(
            .number.locale(display).precision(.fractionLength(0...max(0, maxFractionDigits)))
        )
    }
}
