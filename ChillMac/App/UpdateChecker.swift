import Foundation

class UpdateChecker: ObservableObject {
    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var downloadURL: URL?
    @Published var releaseURL: URL?
    @Published var isChecking = false
    @Published var hasChecked = false

    private var timer: Timer?
    private static let checkInterval: TimeInterval = 6 * 3600
    private static let apiURL = URL(string: "https://api.github.com/repos/idevtim/chillmac/releases/latest")!

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func startPeriodicChecks() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.performCheck()
        }
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            self?.performCheck()
        }
    }

    func stopPeriodicChecks() {
        timer?.invalidate()
        timer = nil
    }

    func performCheck() {
        guard !isChecking else { return }
        isChecking = true

        Task {
            await fetchLatestRelease()
            await MainActor.run { self.isChecking = false }
        }
    }

    private func fetchLatestRelease() async {
        do {
            var request = URLRequest(url: Self.apiURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            guard let tagName = json["tag_name"] as? String else { return }

            let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
            let remoteReleaseURL = (json["html_url"] as? String).flatMap { URL(string: $0) }
            var remoteDownloadURL: URL?

            if let assets = json["assets"] as? [[String: Any]],
               let firstAsset = assets.first,
               let browserURL = firstAsset["browser_download_url"] as? String {
                remoteDownloadURL = URL(string: browserURL)
            }

            let newer = isNewer(remoteVersion, than: currentVersion)

            await MainActor.run {
                self.latestVersion = remoteVersion
                self.releaseURL = remoteReleaseURL
                self.downloadURL = remoteDownloadURL
                self.updateAvailable = newer
                self.hasChecked = true
            }
        } catch {
            NSLog("UpdateChecker: failed to check for updates — \(error.localizedDescription)")
        }
    }

    private func isNewer(_ remote: String, than local: String) -> Bool {
        let r = remote.split(separator: ".").compactMap { Int($0) }
        let l = local.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv > lv { return true }
            if rv < lv { return false }
        }
        return false
    }
}
