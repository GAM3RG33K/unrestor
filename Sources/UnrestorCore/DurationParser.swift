import Foundation

/// Parses "90m", "2h", "1h30m", "45s". A bare number means minutes.
public enum DurationParser {
    public static func parse(_ text: String) -> TimeInterval? {
        let text = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !text.isEmpty else { return nil }
        if let minutes = Int(text) { return minutes > 0 ? TimeInterval(minutes) * 60 : nil }

        var total: TimeInterval = 0
        var digits = ""
        var seen = Set<Character>()
        for character in text {
            if character.isASCII, character.isNumber {
                digits.append(character)
                continue
            }
            let unit: TimeInterval
            switch character {
            case "d": unit = 86_400
            case "h": unit = 3_600
            case "m": unit = 60
            case "s": unit = 1
            default: return nil
            }
            guard let amount = Int(digits), seen.insert(character).inserted else { return nil }
            total += TimeInterval(amount) * unit
            digits = ""
        }
        guard digits.isEmpty, total > 0 else { return nil }
        return total
    }

    public static func format(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded()))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(seconds)s"
    }

    /// A countdown as a clock: "1:23:45", or "23:45" under an hour.
    public static func clock(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.up)))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let rest = seconds % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, rest) }
        return String(format: "%d:%02d", minutes, rest)
    }
}
