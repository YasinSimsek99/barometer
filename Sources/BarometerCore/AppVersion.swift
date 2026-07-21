import Foundation

/// A dotted version number ("1.0.0"), compared component by component as
/// integers so "1.10.0" correctly sorts after "1.9.0".
public struct AppVersion: Comparable, Equatable, Sendable {
    public let components: [Int]

    public init?(_ string: String) {
        let cleaned = string.hasPrefix("v") || string.hasPrefix("V") ? String(string.dropFirst()) : string
        let parsed = cleaned.split(separator: ".").map { Int($0) }
        guard !parsed.isEmpty, !parsed.contains(where: { $0 == nil }) else { return nil }
        components = parsed.compactMap { $0 }
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    /// Consistent with `<`'s zero-padding, so "1.0" equals "1.0.0" rather than
    /// falling back to plain array equality on `components`.
    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
