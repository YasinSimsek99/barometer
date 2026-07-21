import Foundation

public struct ResetCountdownValue: Equatable, Sendable {
    public let windowLabel: String
    public let text: String

    public init(windowLabel: String, text: String) {
        self.windowLabel = windowLabel
        self.text = text
    }
}

public struct ResetCountdownFormatter: Sendable {
    public init() {}

    public func menuBarText(
        snapshot: UsageSnapshot?,
        metricMode: MetricMode,
        now: Date = Date()
    ) -> String? {
        guard let value = menuBarValue(snapshot: snapshot, metricMode: metricMode, now: now) else { return nil }
        switch metricMode {
        case .fiveHour, .sevenDay:
            return value.text
        case .both, .highest:
            return "\(value.windowLabel)\(value.text)"
        }
    }

    public func menuBarValue(
        snapshot: UsageSnapshot?,
        metricMode: MetricMode,
        now: Date = Date()
    ) -> ResetCountdownValue? {
        guard let selection = selectedReset(snapshot: snapshot, metricMode: metricMode) else {
            return nil
        }
        return ResetCountdownValue(
            windowLabel: selection.label,
            text: "↻\(compactDuration(until: selection.date, now: now))"
        )
    }

    public func duration(until reset: Date, now: Date = Date()) -> String {
        let interval = reset.timeIntervalSince(now)
        guard interval > 0 else { return "now" }

        let totalMinutes = max(1, Int(ceil(interval / 60)))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return "\(minutes)m"
    }

    private func compactDuration(until reset: Date, now: Date) -> String {
        let interval = reset.timeIntervalSince(now)
        guard interval > 0 else { return "now" }

        let totalMinutes = max(1, Int(ceil(interval / 60)))
        let days = totalMinutes / (24 * 60)
        let hours = (totalMinutes % (24 * 60)) / 60
        let minutes = totalMinutes % 60

        if days > 0 { return hours > 0 ? "\(days)d\(hours)h" : "\(days)d" }
        if hours > 0 { return String(format: "%d:%02d", hours, minutes) }
        return "\(minutes)m"
    }

    private func selectedReset(
        snapshot: UsageSnapshot?,
        metricMode: MetricMode
    ) -> (label: String, date: Date)? {
        guard let snapshot else { return nil }
        let fiveHour = snapshot.fiveHour?.resetsAt.map { (label: "5h", date: $0) }
        let sevenDay = snapshot.sevenDay?.resetsAt.map { (label: "7d", date: $0) }

        switch metricMode {
        case .fiveHour:
            return fiveHour
        case .sevenDay:
            return sevenDay
        case .both:
            return [fiveHour, sevenDay]
                .compactMap { $0 }
                .min { $0.date < $1.date }
        case .highest:
            switch (snapshot.fiveHour, snapshot.sevenDay) {
            case let (five?, seven?):
                return five.usedPercentage >= seven.usedPercentage ? fiveHour : sevenDay
            case (_?, nil):
                return fiveHour
            case (nil, _?):
                return sevenDay
            case (nil, nil):
                return nil
            }
        }
    }
}
