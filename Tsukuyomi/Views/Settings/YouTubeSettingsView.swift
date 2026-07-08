import SwiftUI
import WebKit

struct YouTubeSettingsView: View {
    @Environment(AppLogger.self) private var appLogger
    @State private var isSignedIn = false
    @State private var showLoginSheet = false

    var body: some View {
        List {
            Section(String(localized: "youtube.settings.section.player", defaultValue: "Player")) {
                LabeledContent(
                    String(localized: "youtube.settings.player", defaultValue: "Playback"),
                    value: String(localized: "youtube.settings.player.value", defaultValue: "Dedicated YouTube Page")
                )
                .listRowBackground(Color.clear)

                Text(String(localized: "youtube.settings.player.footer", defaultValue: "YouTube videos open in a dedicated player page with inline playback, browser access, and session-aware cookies."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            Section(String(localized: "youtube.settings.section.account", defaultValue: "Account")) {
                LabeledContent(
                    String(localized: "youtube.settings.account.status", defaultValue: "Status"),
                    value: isSignedIn
                        ? String(localized: "youtube.settings.account.signedIn", defaultValue: "Signed In")
                        : String(localized: "youtube.settings.account.signedOut", defaultValue: "Not Signed In")
                )
                .listRowBackground(Color.clear)

                if isSignedIn {
                    Button(String(localized: "youtube.settings.signout", defaultValue: "Sign Out")) {
                        Task {
                            await YouTubeSessionManager.clearSession()
                            appLogger.logUI("Signed out of YouTube web session from settings")
                            await refreshSessionState()
                        }
                    }
                    .foregroundStyle(.red)
                    .listRowBackground(Color.clear)
                } else {
                    Button(String(localized: "youtube.settings.signin", defaultValue: "Sign In")) {
                        appLogger.logUI("Opened YouTube login sheet from settings")
                        showLoginSheet = true
                    }
                    .listRowBackground(Color.clear)
                }
            }
        }
        .tsukuyomiListSurface()
        .navigationTitle(String(localized: "youtube.settings.title", defaultValue: "YouTube"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showLoginSheet) {
            YouTubeLoginView {
                Task { await refreshSessionState() }
            }
        }
        .task {
            await refreshSessionState()
        }
    }

    @MainActor
    private func refreshSessionState() async {
        isSignedIn = await YouTubeSessionManager.hasSession()
    }
}

struct YouTubeLoginView: View {
    @Environment(\.dismiss) private var dismiss
    let onCompletion: () -> Void

    @State private var isLoggedIn = false

    var body: some View {
        NavigationStack {
            YouTubeLoginWebView(isLoggedIn: $isLoggedIn)
                .background(TsukuyomiBackdrop())
                .navigationTitle(String(localized: "youtube.login.title", defaultValue: "YouTube Login"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "action.close", defaultValue: "Close")) {
                            dismiss()
                        }
                    }
                }
                .onChange(of: isLoggedIn) { _, loggedIn in
                    guard loggedIn else { return }
                    onCompletion()
                    dismiss()
                }
        }
    }
}

private struct YouTubeLoginWebView: UIViewRepresentable {
    @Binding var isLoggedIn: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isLoggedIn: $isLoggedIn)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.customUserAgent = YouTubeSessionManager.mobileSafariUserAgent
        if let loginURL = URL(string: "https://accounts.google.com/ServiceLogin?service=youtube&continue=https://m.youtube.com/") {
            webView.load(URLRequest(url: loginURL))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isLoggedIn: Bool
        private var checkTask: Task<Void, Never>?

        init(isLoggedIn: Binding<Bool>) {
            _isLoggedIn = isLoggedIn
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            checkTask?.cancel()
            checkTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                if await YouTubeSessionManager.hasSession() {
                    isLoggedIn = true
                }
            }
        }
    }
}
