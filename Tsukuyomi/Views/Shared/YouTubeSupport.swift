import Foundation
import UIKit
import WebKit

enum YouTubeHelper {
    static var isAppInstalled: Bool {
        guard let url = URL(string: "youtube://") else { return false }
        return UIApplication.shared.canOpenURL(url)
    }

    static func openInApp(url urlString: String) {
        guard let url = URL(string: urlString) else { return }
        if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.scheme = "youtube"
            if let youtubeURL = components.url,
               UIApplication.shared.canOpenURL(youtubeURL) {
                UIApplication.shared.open(youtubeURL)
                return
            }
        }
        UIApplication.shared.open(url)
    }
}

enum YouTubeSessionManager {
    static let mobileSafariUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    @MainActor
    static func hasSession() async -> Bool {
        let store = WKWebsiteDataStore.default()
        let cookies = await store.httpCookieStore.allCookies()
        return cookies.contains { cookie in
            let domain = cookie.domain.lowercased()
            return (domain.contains("youtube.com") || domain.contains("google.com"))
                && (cookie.name == "SID" || cookie.name == "SSID" || cookie.name == "LOGIN_INFO")
        }
    }

    @MainActor
    static func clearSession() async {
        let store = WKWebsiteDataStore.default()
        let cookies = await store.httpCookieStore.allCookies()
        for cookie in cookies where cookie.domain.lowercased().contains("youtube.com")
            || cookie.domain.lowercased().contains("google.com")
            || cookie.domain.lowercased().contains("accounts.google.com") {
            await store.httpCookieStore.deleteCookie(cookie)
        }
    }
}
