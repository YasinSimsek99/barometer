import Foundation

public struct RateLimitWindow: Codable, Equatable, Sendable {
    public let usedPercentage: Double
    public let resetsAt: Date?

    public init(usedPercentage: Double, resetsAt: Date?) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let capturedAt: Date
    public let fiveHour: RateLimitWindow?
    public let sevenDay: RateLimitWindow?

    public init(
        schemaVersion: Int = AppIdentity.current.schemaVersion,
        capturedAt: Date,
        fiveHour: RateLimitWindow?,
        sevenDay: RateLimitWindow?
    ) {
        self.schemaVersion = schemaVersion
        self.capturedAt = capturedAt
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    public func isStale(at date: Date = Date(), interval: TimeInterval = 600) -> Bool {
        date.timeIntervalSince(capturedAt) > interval
    }

    /// Returns a display-safe snapshot for the current instant.
    ///
    /// Claude Code can keep invoking a status line with the last JSON value from
    /// an idle session. Once a window's advertised reset time has passed, that
    /// old percentage must not remain visible as current account usage.
    public func normalized(at date: Date = Date()) -> UsageSnapshot {
        UsageSnapshot(
            schemaVersion: schemaVersion,
            capturedAt: capturedAt,
            fiveHour: fiveHour?.normalized(at: date),
            sevenDay: sevenDay?.normalized(at: date)
        )
    }

    /// Combines status-line samples without allowing an idle session from an
    /// older reset period to overwrite a newer account-limit window.
    public func merging(_ incoming: UsageSnapshot) -> UsageSnapshot {
        let fiveHourResult = Self.mergeWindow(existing: fiveHour, incoming: incoming.fiveHour)
        let sevenDayResult = Self.mergeWindow(existing: sevenDay, incoming: incoming.sevenDay)
        let acceptedUsage = fiveHourResult.acceptedIncoming || sevenDayResult.acceptedIncoming

        return UsageSnapshot(
            schemaVersion: schemaVersion,
            capturedAt: acceptedUsage ? max(capturedAt, incoming.capturedAt) : capturedAt,
            fiveHour: fiveHourResult.window,
            sevenDay: sevenDayResult.window
        )
    }

    public var highestUsage: Double? {
        [fiveHour?.usedPercentage, sevenDay?.usedPercentage].compactMap { $0 }.max()
    }

    private static func mergeWindow(
        existing: RateLimitWindow?,
        incoming: RateLimitWindow?
    ) -> (window: RateLimitWindow?, acceptedIncoming: Bool) {
        guard let existing else { return (incoming, incoming != nil) }
        guard let incoming else { return (existing, false) }

        switch (existing.resetsAt, incoming.resetsAt) {
        case let (existingReset?, incomingReset?):
            if incomingReset > existingReset { return (incoming, true) }
            if incomingReset < existingReset { return (existing, false) }

            // Within one fixed reset period, an idle Claude session can replay
            // an older, lower sample. Keep the high-water mark for that period.
            return incoming.usedPercentage >= existing.usedPercentage
                ? (incoming, true)
                : (existing, false)
        case (nil, nil):
            return (incoming, true)
        case (nil, _?):
            return (incoming, true)
        case (_?, nil):
            return (existing, false)
        }
    }
}

private extension RateLimitWindow {
    func normalized(at date: Date) -> RateLimitWindow {
        guard let resetsAt, resetsAt <= date, usedPercentage != 0 else { return self }
        return RateLimitWindow(usedPercentage: 0, resetsAt: resetsAt)
    }
}
