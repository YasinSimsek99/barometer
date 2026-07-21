import Foundation

public struct UsageThresholdEvent: Equatable, Sendable {
    public let identifier: String
    public let windowLabel: String
    public let threshold: Int
    public let usedPercentage: Double
}

public struct ThresholdEvaluation: Equatable, Sendable {
    public let events: [UsageThresholdEvent]
    public let sentTokens: Set<String>
}

public struct NotificationThresholdTracker: Sendable {
    public init() {}

    public func evaluate(snapshot: UsageSnapshot, sentTokens: Set<String>) -> ThresholdEvaluation {
        let windows = [("5-hour", snapshot.fiveHour), ("7-day", snapshot.sevenDay)]
        var updatedTokens = sentTokens
        var events: [UsageThresholdEvent] = []

        for (label, optionalWindow) in windows {
            guard let window = optionalWindow else { continue }
            let windowPrefix = prefix(label: label, window: window)
            updatedTokens = Set(updatedTokens.filter { token in
                !token.hasPrefix("\(label)-") || token.hasPrefix("\(windowPrefix)-")
            })
            for threshold in [70, 90] where window.usedPercentage >= Double(threshold) {
                let token = "\(windowPrefix)-\(threshold)"
                guard !updatedTokens.contains(token) else { continue }
                events.append(UsageThresholdEvent(
                    identifier: token,
                    windowLabel: label,
                    threshold: threshold,
                    usedPercentage: window.usedPercentage
                ))
                updatedTokens.insert(token)
            }
        }
        return ThresholdEvaluation(events: events, sentTokens: updatedTokens)
    }

    private func prefix(label: String, window: RateLimitWindow) -> String {
        if let reset = window.resetsAt {
            return "\(label)-\(Int(reset.timeIntervalSince1970))"
        }
        return "\(label)-unknown-window"
    }
}
