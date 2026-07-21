import Foundation

public enum MetricMode: String, CaseIterable, Codable, Sendable {
    case both
    case fiveHour
    case sevenDay
    case highest

    public var label: String {
        switch self {
        case .both: "5h + 7d"
        case .fiveHour: "5 hour"
        case .sevenDay: "7 day"
        case .highest: "Highest"
        }
    }
}

public enum DisplayStyle: String, CaseIterable, Codable, Sendable {
    /// Color-coded needle gauge.
    case icon
    /// Plain monochrome progress ring.
    case ring
    case text

    public var label: String {
        switch self {
        case .icon: "Needle"
        case .ring: "Ring"
        case .text: "Text"
        }
    }
}

public struct StatusDisplayFormatter: Sendable {
    public init() {}

    public func title(snapshot: UsageSnapshot?, metricMode: MetricMode) -> String {
        guard let snapshot else { return "—" }

        let value: String
        switch metricMode {
        case .both:
            let five = snapshot.fiveHour.map { rounded($0.usedPercentage) } ?? "—"
            let seven = snapshot.sevenDay.map { rounded($0.usedPercentage) } ?? "—"
            value = "5h \(five) · 7d \(seven)"
        case .fiveHour:
            let percentage = snapshot.fiveHour.map { rounded($0.usedPercentage) } ?? "—"
            value = "5h \(percentage)"
        case .sevenDay:
            let percentage = snapshot.sevenDay.map { rounded($0.usedPercentage) } ?? "—"
            value = "7d \(percentage)"
        case .highest:
            let percentage = snapshot.highestUsage.map(rounded) ?? "—"
            value = "Max \(percentage)"
        }
        return value
    }

    public func percentage(snapshot: UsageSnapshot?, metricMode: MetricMode) -> Double? {
        guard let snapshot else { return nil }
        switch metricMode {
        case .both, .highest:
            return snapshot.highestUsage
        case .fiveHour:
            return snapshot.fiveHour?.usedPercentage
        case .sevenDay:
            return snapshot.sevenDay?.usedPercentage
        }
    }

    private func rounded(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }
}
