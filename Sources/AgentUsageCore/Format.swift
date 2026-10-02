import Foundation

/// Display formatting shared by the panel and the menu bar label, matching the Omarchy Agents widget.
public enum Format {
    /// Turns a model id into a display name: `claude-opus-5-5` → `Opus 5.5`, `claude-haiku-4-5-20251001` → `Haiku 4.5`.
    public static func modelName(_ modelID: String) -> String {
        var parts = modelID.split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) { parts.removeLast() }
        guard !parts.isEmpty else { return modelID }
        return groupNumericRuns(parts).joined(separator: " ")
    }

    /// Joins consecutive numeric parts with "." (`5`,`5` → `5.5`) and title-cases words.
    private static func groupNumericRuns(_ parts: [String]) -> [String] {
        var groups: [String] = []
        var previousWasNumeric = false
        for part in parts {
            let isNumeric = part.allSatisfy(\.isNumber)
            if isNumeric && previousWasNumeric, let last = groups.popLast() {
                groups.append(last + "." + part)
            } else {
                groups.append(isNumeric ? part : part.prefix(1).uppercased() + part.dropFirst())
            }
            previousWasNumeric = isNumeric
        }
        return groups
    }

    /// Compact token count: `34.7M`, `857.9K`, `1.2B`, or the plain integer below a thousand.
    public static func tokens(_ count: Int) -> String {
        let value = Double(count)
        switch value {
        case 1e9...: return String(format: "%.1fB", value / 1e9)
        case 1e6...: return String(format: "%.1fM", value / 1e6)
        case 1e3...: return String(format: "%.1fK", value / 1e3)
        default: return String(count)
        }
    }

    /// Countdown text for a limit reset: `5d 13h`, `2h 53m`, `38m`, or `now` once the reset has passed.
    public static func countdown(seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "now" }
        let totalMinutes = Int(seconds / 60)
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60
        if days >= 1 { return "\(days)d \(hours)h" }
        if hours >= 1 { return "\(hours)h \(minutes)m" }
        return "\(max(1, minutes))m"
    }

    /// Dollar amount with cents below $1,000 and whole dollars above, so wide values fit the value column.
    public static func usd(_ amount: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.maximumFractionDigits = amount >= 1000 ? 0 : 2
        formatter.minimumFractionDigits = amount >= 1000 ? 0 : 2
        return formatter.string(from: NSNumber(value: amount)) ?? String(format: "$%.2f", amount)
    }
}
