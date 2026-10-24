import Foundation

extension JSONDecoder {
    /// snake_case keys; dates as ISO-8601 with or without fractional seconds, or Postgres `yyyy-MM-dd`.
    static var droplet: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = DropletDates.parse(string) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Unrecognized date: \(string)"
                )
            }
            return date
        }
        return decoder
    }
}

extension JSONEncoder {
    /// snake_case keys; ISO-8601 dates; sorted keys so output is deterministic.
    static var droplet: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

enum DropletDates {
    private static let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let withoutFraction = Date.ISO8601FormatStyle()

    /// Parses `2026-10-24T16:03:11.482123+00:00`, `2026-10-24T16:03:11Z` or `2026-10-24`.
    static func parse(_ string: String) -> Date? {
        if let date = try? Date(string, strategy: withFraction) { return date }
        if let date = try? Date(string, strategy: withoutFraction) { return date }
        return localMidnight(fromDay: string)
    }

    /// `yyyy-MM-dd` as local midnight in `Calendar.current`.
    static func localMidnight(fromDay string: String) -> Date? {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        return Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// Local calendar day of `date`, formatted `yyyy-MM-dd`.
    static func dayString(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
