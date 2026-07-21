import Foundation
import BarometerCore

/// The result of an explicit, user-initiated update check against GitHub's
/// public releases API. Every case only carries plain Sendable values so it
/// can safely cross from the free-standing (non-@MainActor) check function
/// back into AppModel's actor-isolated state.
enum UpdateCheckResult: Equatable, Sendable {
    case upToDate
    case updateAvailable(version: String, url: URL)
    case failed(String)
}

/// Deliberately a free function, not a method on the @MainActor AppModel:
/// this performs the one and only network request Barometer ever makes, and
/// only when the user explicitly asks for it (see PRIVACY.md).
enum UpdateChecker {
    private struct ReleaseResponse: Decodable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    static func checkForUpdate(repository: String, currentVersion: String) async -> UpdateCheckResult {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/releases/latest") else {
            return .failed("Could not build the update check URL.")
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                return .failed("GitHub returned an unexpected response.")
            }
            let release = try JSONDecoder().decode(ReleaseResponse.self, from: data)
            guard let latest = AppVersion(release.tagName), let current = AppVersion(currentVersion) else {
                return .failed("Could not read the version number.")
            }
            return latest > current ? .updateAvailable(version: release.tagName, url: release.htmlURL) : .upToDate
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
