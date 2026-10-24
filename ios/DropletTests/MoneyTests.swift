import Testing
@testable import Droplet

struct MoneyTests {
    @Test(arguments: [
        (567, "$5.67"), (0, "$0.00"), (-567, "-$5.67"), (5, "$0.05"), (100_000, "$1,000.00"),
    ])
    func formatsCents(cents: Int, expected: String) {
        #expect(Money.format(cents: cents) == expected)
    }

    @Test(arguments: [(33, "+$0.33"), (0, "$0.00"), (-33, "-$0.33"), (1528, "+$15.28")])
    func formatsSignedCents(cents: Int, expected: String) {
        #expect(Money.formatSigned(cents: cents) == expected)
    }

    @Test(arguments: [(567, 33), (400, 0), (1, 99), (-1200, 0), (0, 0), (1342, 58), (2318, 82), (99, 1)])
    func mirrorsServerRoundupRule(amount: Int, expected: Int) {
        #expect(Money.roundupCents(forAmountCents: amount) == expected)
    }

    @Test(arguments: [
        ("0.053137000000000000", "0.053137"),
        ("12", "12"),
        ("0.0000004", "0"),
        ("1234.5", "1,234.5"),
        ("not-a-number", "not-a-number"),
    ])
    func formatsQuantities(raw: String, expected: String) {
        #expect(Money.formatQuantity(raw) == expected)
    }

    @Test func quantityRespectsMaxFractionDigits() {
        #expect(Money.formatQuantity("3.14159", maxFractionDigits: 2) == "3.14")
        #expect(Money.formatQuantity("0.000046041", maxFractionDigits: 8) == "0.00004604")
    }
}
