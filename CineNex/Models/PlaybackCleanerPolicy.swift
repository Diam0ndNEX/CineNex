import Foundation

enum PlaybackCleanerPolicy {
    static let enabledStorageKey = "cinenex.playbackCleaner.enabled"
    static let disabledProvidersStorageKey = "cinenex.playbackCleaner.disabledProviders"

    static let blockedHosts: Set<String> = [
        "doubleclick.net",
        "googlesyndication.com",
        "googleadservices.com",
        "adnxs.com",
        "adsrvr.org",
        "adform.net",
        "taboola.com",
        "outbrain.com",
        "popads.net",
        "popcash.net",
        "exoclick.com",
        "trafficjunky.net"
    ]

    static func isEnabled(
        globallyEnabled: Bool,
        providerID: String,
        disabledProviderIDs: Set<String>
    ) -> Bool {
        globallyEnabled && !disabledProviderIDs.contains(providerID)
    }

    static func disabledProviderIDs(from storedValue: String) -> Set<String> {
        Set(
            storedValue
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    static func storedValue(for providerIDs: Set<String>) -> String {
        providerIDs.sorted().joined(separator: ",")
    }

    static func shouldAllowNavigation(to url: URL, cleanerEnabled: Bool) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              !host.isEmpty,
              url.user == nil,
              url.password == nil else {
            return false
        }

        guard cleanerEnabled else { return true }
        return !isBlockedHost(host)
    }

    static func isBlockedHost(_ host: String) -> Bool {
        let normalizedHost = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return blockedHosts.contains { blockedHost in
            normalizedHost == blockedHost || normalizedHost.hasSuffix("." + blockedHost)
        }
    }

    static func contentBlockerJSON() throws -> String {
        let domains = blockedHosts.sorted().map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        let rule: [String: Any] = [
            "trigger": [
                "url-filter": "^https?://([^/]+\\.)?(" + domains + ")(/|$)",
                "load-type": ["third-party"]
            ],
            "action": ["type": "block"]
        ]
        let data = try JSONSerialization.data(withJSONObject: [rule], options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return json
    }
}
