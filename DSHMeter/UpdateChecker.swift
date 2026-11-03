import AppKit
import Combine
import Foundation

struct AvailableUpdate: Equatable, Identifiable {
    let version: String
    let title: String?
    let releaseNotes: String?
    let releasePageURL: URL
    let publishedAt: Date?

    var id: String { version }
}

@MainActor
final class UpdateChecker: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable(AvailableUpdate)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var automaticallyInstallsUpdates = false
    @Published private(set) var isDeveloperPreview = false
    @Published private var isChecking = false

    private let releasesURL = URL(string: "https://github.com/HY916-cn/DSHMeter/releases")!
    private var includesPrereleases: Bool
    private var stateBeforeDeveloperPreview: State?

    init(includePrereleases: Bool = false) {
        includesPrereleases = includePrereleases
    }

    var installedVersion: String { BundleInfo.version }
    var installedBuild: String { BundleInfo.build }
    var allowsAutomaticUpdates: Bool { false }
    var canCheckForUpdates: Bool { !isChecking }

    func check(includePrereleases: Bool) {
        guard !isChecking else { return }
        setIncludesPrereleases(includePrereleases)
        clearDeveloperPreview()
        if case .updateAvailable(let release) = state {
            NSWorkspace.shared.open(release.releasePageURL)
            return
        }
        state = .checking
        isChecking = true
        let includePrereleases = includesPrereleases
        Task {
            let result: State
            do {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.timeoutIntervalForRequest = 15
                configuration.timeoutIntervalForResource = 30
                let session = URLSession(configuration: configuration)
                defer { session.finishTasksAndInvalidate() }
                var request = URLRequest(url: URL(
                    string: "https://api.github.com/repos/HY916-cn/DSHMeter/releases?per_page=100"
                )!)
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                request.setValue("DSHMeter/\(installedVersion)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await session.data(for: request)
                guard let response = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }
                guard (200...299).contains(response.statusCode) else {
                    throw URLError(.badServerResponse, userInfo: [
                        NSLocalizedDescriptionKey: "GitHub HTTP \(response.statusCode)"
                    ])
                }
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let releases = try decoder.decode([GitHubRelease].self, from: data)
                guard let installed = SemanticVersion(installedVersion) else {
                    throw URLError(.cannotParseResponse)
                }
                let candidates = releases.compactMap { release -> (GitHubRelease, SemanticVersion)? in
                    guard !release.draft,
                          let version = SemanticVersion(release.tag_name),
                          includePrereleases || (!release.prerelease && version.prerelease.isEmpty),
                          version > installed,
                          release.html_url.scheme == "https",
                          release.html_url.host?.lowercased() == "github.com",
                          release.html_url.path.lowercased().hasPrefix("/hy916-cn/dshmeter/releases/") else { return nil }
                    return (release, version)
                }
                if let (release, _) = candidates.max(by: { $0.1 < $1.1 }) {
                    result = .updateAvailable(AvailableUpdate(
                        version: release.tag_name,
                        title: release.name,
                        releaseNotes: release.body,
                        releasePageURL: release.html_url,
                        publishedAt: release.published_at
                    ))
                } else {
                    result = .upToDate
                }
            } catch {
                result = .failed(error.localizedDescription)
            }
            let currentResult: State = includePrereleases == includesPrereleases ? result : .idle
            if isDeveloperPreview {
                stateBeforeDeveloperPreview = currentResult
            } else {
                state = currentResult
            }
            isChecking = false
        }
    }

    func setIncludesPrereleases(_ includePrereleases: Bool) {
        guard includesPrereleases != includePrereleases else { return }
        includesPrereleases = includePrereleases
        if isDeveloperPreview {
            stateBeforeDeveloperPreview = .idle
        } else if !isChecking {
            state = .idle
        }
    }

    func setAutomaticallyInstallsUpdates(_ enabled: Bool) {
        refreshPreferences()
    }

    func refreshPreferences() {
        automaticallyInstallsUpdates = false
    }

    func showDeveloperUpdatePreview() {
        if !isDeveloperPreview {
            stateBeforeDeveloperPreview = state
        }
        isDeveloperPreview = true
        state = .updateAvailable(AvailableUpdate(
            version: "9.9.9",
            title: "DSHMeter 9.9.9 Preview",
            releaseNotes: nil,
            releasePageURL: releasesURL.appending(path: "tag/v9.9.9"),
            publishedAt: nil
        ))
    }

    func clearDeveloperPreview() {
        guard isDeveloperPreview else { return }
        isDeveloperPreview = false
        state = stateBeforeDeveloperPreview ?? .idle
        stateBeforeDeveloperPreview = nil
    }
}

private struct GitHubRelease: Decodable {
    let tag_name: String
    let name: String?
    let body: String?
    let html_url: URL
    let published_at: Date?
    let draft: Bool
    let prerelease: Bool
}
