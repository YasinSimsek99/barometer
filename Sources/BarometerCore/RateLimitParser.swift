import CoreFoundation
import Foundation

public enum RateLimitParserError: Error, Equatable {
    case invalidJSON
    case invalidTopLevel
    case invalidWindow(String)
    case noRateLimits
}

public struct RateLimitParser: Sendable {
    public init() {}

    public func parse(_ data: Data, capturedAt: Date = Date()) throws -> UsageSnapshot {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw RateLimitParserError.invalidJSON
        }

        guard let root = object as? [String: Any] else {
            throw RateLimitParserError.invalidTopLevel
        }

        guard let rateLimits = root["rate_limits"] as? [String: Any] else {
            throw RateLimitParserError.noRateLimits
        }

        let fiveHour = try parseWindow(rateLimits["five_hour"], name: "five_hour")
        let sevenDay = try parseWindow(rateLimits["seven_day"], name: "seven_day")

        guard fiveHour != nil || sevenDay != nil else {
            throw RateLimitParserError.noRateLimits
        }

        return UsageSnapshot(
            capturedAt: capturedAt,
            fiveHour: fiveHour,
            sevenDay: sevenDay
        )
    }

    private func parseWindow(_ value: Any?, name: String) throws -> RateLimitWindow? {
        guard let value else { return nil }
        guard let dictionary = value as? [String: Any] else {
            throw RateLimitParserError.invalidWindow(name)
        }
        guard let percentage = number(dictionary["used_percentage"]),
              percentage.isFinite,
              (0...100).contains(percentage)
        else {
            throw RateLimitParserError.invalidWindow(name)
        }

        let reset: Date?
        if dictionary["resets_at"] == nil || dictionary["resets_at"] is NSNull {
            reset = nil
        } else if let epoch = number(dictionary["resets_at"]), epoch.isFinite, epoch > 0 {
            reset = Date(timeIntervalSince1970: epoch)
        } else {
            throw RateLimitParserError.invalidWindow(name)
        }

        return RateLimitWindow(usedPercentage: percentage, resetsAt: reset)
    }

    private func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID():
            return number.doubleValue
        case let string as String:
            return Double(string)
        default:
            return nil
        }
    }

}
