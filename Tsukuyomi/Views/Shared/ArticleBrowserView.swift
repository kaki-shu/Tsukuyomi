import SwiftUI
import WebKit

struct ArticleBrowserView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FeedStore.self) private var feedStore
    @Environment(AppLogger.self) private var appLogger

    let initialURL: URL
    let onReadArticle: (FeedArticle.ID) -> Void

    @State private var controller = BrowserController()
    @State private var currentURL: URL?
    @State private var currentTitle = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            BrowserWebView(
                initialURL: initialURL,
                controller: controller,
                currentURL: $currentURL,
                currentTitle: $currentTitle,
                isLoading: $isLoading
            )
            .background(TsukuyomiBackdrop())
            .navigationTitle(currentTitle.isEmpty ? (currentURL?.host() ?? initialURL.host() ?? String(localized: "article.browser.open", defaultValue: "Browser")) : currentTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "action.close", defaultValue: "Close")) {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        controller.goBack()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .disabled(!controller.canGoBack)

                    Button {
                        controller.reload()
                    } label: {
                        if isLoading {
                            ProgressView()
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }

                    Button(String(localized: "browser.read", defaultValue: "Read")) {
                        captureCurrentPage()
                    }
                }
            }
            .alert(String(localized: "browser.read.error", defaultValue: "Unable to Read This Page"), isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button(String(localized: "action.ok", defaultValue: "OK"), role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func captureCurrentPage() {
        controller.captureCurrentPage { html, url, title in
            guard let html, let url else {
                errorMessage = String(localized: "browser.read.error.message", defaultValue: "The current page HTML could not be captured.")
                return
            }
            do {
                let articleID = try feedStore.importPageSnapshot(
                    urlString: url.absoluteString,
                    pageTitle: title,
                    html: html,
                    logger: appLogger
                )
                appLogger.logUI("Read current page from in-app browser \(url.absoluteString)")
                dismiss()
                onReadArticle(articleID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

@MainActor
final class BrowserController {
    weak var webView: WKWebView?
    var canGoBack = false

    func attach(_ webView: WKWebView) {
        self.webView = webView
        canGoBack = webView.canGoBack
    }

    func goBack() {
        webView?.goBack()
        canGoBack = webView?.canGoBack ?? false
    }

    func reload() {
        webView?.reload()
    }

    func captureCurrentPage(completion: @escaping (String?, URL?, String?) -> Void) {
        let currentURL = webView?.url
        let currentTitle = webView?.title
        webView?.evaluateJavaScript("document.documentElement.outerHTML.toString()") { result, _ in
            completion(result as? String, currentURL, currentTitle)
        }
    }
}

private struct BrowserWebView: UIViewRepresentable {
    let initialURL: URL
    let controller: BrowserController
    @Binding var currentURL: URL?
    @Binding var currentTitle: String
    @Binding var isLoading: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.navigationDelegate = context.coordinator
        controller.attach(webView)
        webView.load(URLRequest(url: initialURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: BrowserWebView

        init(_ parent: BrowserWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
            parent.currentURL = webView.url
            parent.currentTitle = webView.title ?? ""
            parent.controller.canGoBack = webView.canGoBack
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
            parent.currentURL = webView.url
            parent.currentTitle = webView.title ?? ""
            parent.controller.canGoBack = webView.canGoBack
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.currentURL = webView.url
            parent.currentTitle = webView.title ?? ""
            parent.controller.canGoBack = webView.canGoBack
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
            parent.currentURL = webView.url
            parent.currentTitle = webView.title ?? ""
            parent.controller.canGoBack = webView.canGoBack
        }
    }
}
