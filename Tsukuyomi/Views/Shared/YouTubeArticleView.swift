import SwiftUI
import WebKit
import UIKit

struct YouTubeArticleView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FeedStore.self) private var feedStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(AppLogger.self) private var appLogger

    let articleID: FeedArticle.ID

    @State private var isPlaying = false
    @State private var currentTime: TimeInterval = 0
    @State private var duration: TimeInterval = 0
    @State private var webView: WKWebView?
    @State private var isAd = false
    @State private var advertiserURL: URL?
    @State private var hasStartedPlaying = false
    @State private var isPiP = false
    @State private var videoAspectRatio: CGFloat = 16 / 9

    @State private var isRunningSummary = false
    @State private var isRunningTranslation = false
    @State private var errorMessage: String?
    @State private var showingSummaryOutput = false
    @State private var showingTranslationOutput = false
    @State private var browserDestination: BrowserSheetDestination?
    @State private var streamingTranslationText = ""
    @State private var lastStreamRenderLength = 0

    var body: some View {
        ScrollView {
            if let article {
                VStack(alignment: .leading, spacing: 18) {
                    YouTubePlayerWebView(
                        urlString: article.url,
                        isPlaying: $isPlaying,
                        currentTime: $currentTime,
                        duration: $duration,
                        webView: $webView,
                        isAd: $isAd,
                        advertiserURL: $advertiserURL,
                        videoAspectRatio: $videoAspectRatio,
                        isPiP: $isPiP
                    )
                    .aspectRatio(videoAspectRatio, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay {
                        if isPiP {
                            Color.black.opacity(0.7)
                                .overlay {
                                    VStack(spacing: 8) {
                                        Image(systemName: "pip.fill")
                                            .font(.largeTitle)
                                        Text(String(localized: "youtube.player.pip", defaultValue: "Playing in Picture in Picture"))
                                            .font(.subheadline)
                                    }
                                    .foregroundStyle(.white)
                                }
                        } else if !hasStartedPlaying {
                            Color.black.opacity(0.28)
                                .overlay {
                                    ProgressView()
                                        .tint(.white)
                                }
                        }
                    }

                    content(for: article)
                }
                .padding(.horizontal, TsukuyomiLayout.horizontalPadding)
                .padding(.vertical, 20)
                .frame(maxWidth: TsukuyomiLayout.readableMaxWidth + TsukuyomiLayout.horizontalPadding * 2)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .background(TsukuyomiBackdrop())
        .navigationTitle(article?.feedTitle ?? "YouTube")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let article {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        appLogger.logUI("Toggled clip state from dedicated YouTube page for \(article.id.uuidString.prefix(8))")
                        toggleClip(for: article)
                    } label: {
                        Image(systemName: isInClip(article) ? "bookmark.fill" : "bookmark")
                    }
                    .accessibilityLabel(isInClip(article)
                        ? String(localized: "pages.clip.remove", defaultValue: "Remove from Clip")
                        : String(localized: "pages.clip.add", defaultValue: "Add to Clip"))
                }
            }
        }
        .sheet(item: $browserDestination) { destination in
            ArticleBrowserView(initialURL: destination.url) { _ in }
        }
        .alert(String(localized: "article.ai.error.title", defaultValue: "AI Request Failed"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button(String(localized: "action.ok", defaultValue: "OK"), role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            if let article {
                appLogger.logUI("Opened dedicated YouTube page for \(article.url)")
                feedStore.markRead(for: article.id)
                await feedStore.prefetchTitleTranslations(
                    for: [article.id],
                    settingsStore: settingsStore,
                    logger: appLogger
                )
            }
        }
        .onChange(of: isPlaying) { _, newValue in
            if newValue && !hasStartedPlaying {
                hasStartedPlaying = true
            }
        }
    }

    private var article: FeedArticle? {
        feedStore.article(id: articleID)
    }

    private func isInClip(_ article: FeedArticle) -> Bool {
        article.sourceKind == .page || article.isSaved
    }

    private func toggleClip(for article: FeedArticle) {
        if isInClip(article) {
            feedStore.removeClip(articleID: article.id, logger: appLogger)
            if article.sourceKind == .page {
                dismiss()
            }
        } else {
            feedStore.toggleClip(for: article.id, logger: appLogger)
        }
    }

    private func content(for article: FeedArticle) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            titleBlock(for: article)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(article.feedTitle)
                    .font(.subheadline.weight(.semibold))
                if let publishedDate = article.publishedDate {
                    Text(publishedDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            actionBar(for: article)

            if shouldShowSummary(for: article) {
                aiOutputSection(
                    title: String(localized: "article.ai.summary", defaultValue: "AI Summary"),
                    content: article.aiSummary,
                    loading: isRunningSummary
                )
            }

            descriptionSection(for: article)
        }
    }

    @ViewBuilder
    private func titleBlock(for article: FeedArticle) -> some View {
        let translatedTitle = nonBlank(article.aiTitleTranslation)
        switch settingsStore.titleTranslationDisplayMode {
        case .original:
            videoTitleText(article.title)
        case .translationOnly:
            videoTitleText(translatedTitle ?? article.title)
        case .bilingual:
            VStack(alignment: .leading, spacing: 8) {
                videoTitleText(article.title)
                if let translatedTitle {
                    videoTitleText(translatedTitle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func videoTitleText(_ title: String) -> some View {
        WordWrappingText(title, font: settingsStore.titleFont.uiFont(textStyle: .title2, weight: .bold))
            .foregroundStyle(Color.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func actionBar(for article: FeedArticle) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                buttonTitle(
                    title: String(localized: "article.ai.summarize", defaultValue: "Summarize"),
                    systemImage: "text.append",
                    isActive: isRunningSummary || showingSummaryOutput
                ) {
                    toggleSummary(for: article)
                } forceAction: {
                    forceRegenerateSummary(for: article)
                }

                buttonTitle(
                    title: String(localized: "article.ai.translate", defaultValue: "Translate"),
                    systemImage: "character.bubble",
                    isActive: shouldShowTranslation(for: article)
                ) {
                    toggleTranslation(for: article)
                } forceAction: {
                    forceRegenerateTranslation(for: article)
                }

                if YouTubeHelper.isAppInstalled {
                    buttonTitle(
                        title: String(localized: "youtube.player.app", defaultValue: "YouTube App"),
                        systemImage: "play.rectangle",
                        isActive: false
                    ) {
                        appLogger.logUI("Opened YouTube app for \(article.url)")
                        YouTubeHelper.openInApp(url: article.url)
                    }
                }

                buttonTitle(
                    title: String(localized: "article.browser.open", defaultValue: "Browser"),
                    systemImage: "safari",
                    isActive: false
                ) {
                    guard let url = URL(string: article.url) else { return }
                    appLogger.logUI("Opened browser from dedicated YouTube page for \(article.url)")
                    browserDestination = BrowserSheetDestination(url: url)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func buttonTitle(
        title: String,
        systemImage: String,
        isActive: Bool,
        action: @escaping () -> Void,
        forceAction: (() -> Void)? = nil
    ) -> some View {
        if let forceAction {
            TsukuyomiForceableActionButton(
                title: title,
                systemImage: systemImage,
                isActive: isActive,
                action: action,
                forceAction: forceAction
            )
        } else {
            Button(action: action) {
                TsukuyomiActionButton(title: title, systemImage: systemImage, isActive: isActive)
            }
            .buttonStyle(.plain)
        }
    }

    private func toggleSummary(for article: FeedArticle) {
        appLogger.logUI("Toggled summarize button from dedicated YouTube page for \(article.id.uuidString.prefix(8))")
        if showingSummaryOutput, !isRunningSummary {
            showingSummaryOutput = false
        } else if article.aiSummary?.isEmpty == false {
            showingSummaryOutput = true
        } else {
            Task { await run(.summarize, for: article) }
        }
    }

    private func toggleTranslation(for article: FeedArticle) {
        appLogger.logUI("Toggled translate button from dedicated YouTube page for \(article.id.uuidString.prefix(8))")
        if showingTranslationOutput, !isRunningTranslation {
            showingTranslationOutput = false
        } else if article.aiTranslation?.isEmpty == false {
            showingTranslationOutput = true
        } else {
            Task { await runTranslation(for: article) }
        }
    }

    private func forceRegenerateSummary(for article: FeedArticle) {
        guard !isRunningSummary else { return }
        appLogger.logUI("Force regenerating YouTube summary from long press for article \(article.id.uuidString.prefix(8))")
        showingSummaryOutput = true
        Task { await run(.summarize, for: article) }
    }

    private func forceRegenerateTranslation(for article: FeedArticle) {
        guard !isRunningTranslation else { return }
        appLogger.logUI("Force regenerating YouTube translation from long press for article \(article.id.uuidString.prefix(8))")
        showingTranslationOutput = true
        Task { await runTranslation(for: article) }
    }

    private func descriptionSection(for article: FeedArticle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let activeTranslation = translatedBody(for: article)
            if shouldShowTranslation(for: article), let translation = activeTranslation {
                switch settingsStore.translationDisplayMode {
                case .translationOnly, .replaceOriginal:
                    translatedContentView(translation, article: article)
                case .bilingual:
                    VStack(alignment: .leading, spacing: 16) {
                        contentSection(
                            title: String(localized: "article.original.title", defaultValue: "Original"),
                            markdown: article.bodyText
                        )
                        VStack(alignment: .leading, spacing: 10) {
                            Text(String(localized: "article.translation.title", defaultValue: "Translation"))
                                .font(.headline)
                                .foregroundStyle(Color.accentCinder)
                            translatedContentView(translation, article: article)
                                .padding(16)
                                .background(Color.buttonSurface.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                    }
                }
            } else {
                MarkdownContentView(markdown: article.bodyText, isStreaming: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func aiOutputSection(title: String, content: String?, loading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.accentCinder)
            if loading {
                ProgressView()
            } else if let content, !content.isEmpty {
                MarkdownContentView(markdown: content)
            }
        }
        .padding(16)
        .background(Color.buttonSurface.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func run(_ action: AIAction, for article: FeedArticle) async {
        switch action {
        case .summarize:
            isRunningSummary = true
        case .translate:
            isRunningTranslation = true
        }
        defer {
            switch action {
            case .summarize:
                isRunningSummary = false
            case .translate:
                isRunningTranslation = false
            }
        }
        do {
            guard let provider = settingsStore.defaultProvider else {
                throw AIServiceError.missingDefaultProvider
            }
            let service = AIService(configuration: provider, logger: appLogger)
            let result = try await service.run(action: action, article: article, outputLanguage: settingsStore.aiOutputLanguage)
            switch action {
            case .summarize:
                feedStore.storeAIResult(summary: result, for: article.id)
                showingSummaryOutput = true
            case .translate:
                feedStore.storeAIResult(translation: result, for: article.id)
                showingTranslationOutput = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runTranslation(for article: FeedArticle) async {
        isRunningTranslation = true
        showingTranslationOutput = true
        streamingTranslationText = ""
        lastStreamRenderLength = 0
        defer { isRunningTranslation = false }
        do {
            guard let provider = settingsStore.defaultProvider else {
                throw AIServiceError.missingDefaultProvider
            }
            await feedStore.ensureArticleContent(for: article.id)
            let articleForRequest = feedStore.article(id: article.id) ?? article
            let service = AIService(configuration: provider, logger: appLogger)
            let result = try await service.streamTranslation(article: articleForRequest, outputLanguage: settingsStore.aiOutputLanguage) { partial in
                let shouldRender = partial.count < 120
                    || partial.count - lastStreamRenderLength >= 120
                    || partial.hasSuffix("\n")
                    || partial.hasSuffix(")")
                guard shouldRender else { return }
                streamingTranslationText = partial
                lastStreamRenderLength = partial.count
            }
            feedStore.storeAIResult(translation: result, for: article.id)
            streamingTranslationText = ""
            lastStreamRenderLength = 0
        } catch {
            showingTranslationOutput = false
            streamingTranslationText = ""
            lastStreamRenderLength = 0
            errorMessage = error.localizedDescription
        }
    }

    private func translatedBody(for article: FeedArticle) -> String? {
        if isRunningTranslation,
           !streamingTranslationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return streamingTranslationText
        }
        guard let translation = article.aiTranslation?.trimmingCharacters(in: .whitespacesAndNewlines),
              !translation.isEmpty else {
            return nil
        }
        return translation
    }

    private func shouldShowSummary(for article: FeedArticle) -> Bool {
        isRunningSummary || (showingSummaryOutput && article.aiSummary?.isEmpty == false)
    }

    private func shouldShowTranslation(for article: FeedArticle) -> Bool {
        if isRunningTranslation {
            return true
        }
        guard translatedBody(for: article) != nil else {
            return false
        }
        if settingsStore.translationDisplayMode.usesTranslatedBodyOnly {
            return true
        }
        return showingTranslationOutput
    }

    @ViewBuilder
    private func translatedContentView(_ translation: String, article: FeedArticle) -> some View {
        let hiddenImages = hiddenImageSet(for: article)
        let restoredTranslation = TranslationImagePreserver.mergeMissingImages(
            into: translation,
            originalMarkdown: article.bodyText,
            hiddenImageURLs: hiddenImages
        )
        MarkdownContentView(markdown: restoredTranslation, hiddenImageURLs: hiddenImages, isStreaming: isRunningTranslation)
    }

    private func contentSection(title: String, markdown: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.accentCinder)
            MarkdownContentView(markdown: markdown, hiddenImageURLs: article.map(hiddenImageSet(for:)) ?? [])
        }
    }

    private func hiddenImageSet(for article: FeedArticle) -> Set<String> {
        guard let imageURL = article.imageURL else { return [] }
        return [imageURL]
    }
}

private struct YouTubePlayerWebView: UIViewRepresentable {
    let urlString: String
    @Binding var isPlaying: Bool
    @Binding var currentTime: TimeInterval
    @Binding var duration: TimeInterval
    @Binding var webView: WKWebView?
    @Binding var isAd: Bool
    @Binding var advertiserURL: URL?
    @Binding var videoAspectRatio: CGFloat
    @Binding var isPiP: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isPlaying: $isPlaying,
            currentTime: $currentTime,
            duration: $duration,
            isAd: $isAd,
            advertiserURL: $advertiserURL,
            videoAspectRatio: $videoAspectRatio,
            isPiP: $isPiP
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsPictureInPictureMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.customUserAgent = YouTubeSessionManager.mobileSafariUserAgent
        webView.isUserInteractionEnabled = true
        if let url = URL(string: urlString) {
            webView.load(URLRequest(url: url))
        }

        DispatchQueue.main.async {
            self.webView = webView
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.invalidateObserver()
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate {
        @Binding var isPlaying: Bool
        @Binding var currentTime: TimeInterval
        @Binding var duration: TimeInterval
        @Binding var isAd: Bool
        @Binding var advertiserURL: URL?
        @Binding var videoAspectRatio: CGFloat
        @Binding var isPiP: Bool
        private var playbackObserver: Timer?

        init(
            isPlaying: Binding<Bool>,
            currentTime: Binding<TimeInterval>,
            duration: Binding<TimeInterval>,
            isAd: Binding<Bool>,
            advertiserURL: Binding<URL?>,
            videoAspectRatio: Binding<CGFloat>,
            isPiP: Binding<Bool>
        ) {
            _isPlaying = isPlaying
            _currentTime = currentTime
            _duration = duration
            _isAd = isAd
            _advertiserURL = advertiserURL
            _videoAspectRatio = videoAspectRatio
            _isPiP = isPiP
        }

        func invalidateObserver() {
            playbackObserver?.invalidate()
            playbackObserver = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            injectStyles(into: webView)
            unmuteVideo(in: webView)
            startPlaybackObserver(for: webView)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .allow }
            let host = url.host?.lowercased() ?? ""
            if host.contains("youtube.com") || host.contains("youtu.be")
                || host.contains("google.com") || host.contains("accounts.google.com")
                || host.contains("consent.youtube.com") {
                return .allow
            }
            return .cancel
        }

        private func unmuteVideo(in webView: WKWebView) {
            let script = """
            (function() {
                function unmute() {
                    var video = document.querySelector('video');
                    if (video) { video.muted = false; }
                }
                unmute();
                var observer = new MutationObserver(function() { unmute(); });
                observer.observe(document.body, { childList: true, subtree: true });
                setTimeout(function() { observer.disconnect(); }, 5000);
            })();
            """
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        private func injectStyles(into webView: WKWebView) {
            webView.evaluateJavaScript(YouTubePlayerStyles.injectionScript(css: YouTubePlayerStyles.css), completionHandler: nil)
        }

        private func startPlaybackObserver(for webView: WKWebView) {
            playbackObserver?.invalidate()
            playbackObserver = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                let script = """
                (function() {
                    var video = document.querySelector('video');
                    if (!video) return null;
                    var player = document.querySelector('.html5-video-player');
                    var isAd = player ? player.classList.contains('ad-showing') : false;
                    var advLink = document.querySelector('.ytp-ad-visit-advertiser-button, .ytp-ad-button, a[class*="visit-advertiser"], .ytp-ad-overlay-link');
                    var advURL = advLink ? (advLink.href || advLink.getAttribute('href') || '') : '';
                    var vw = video.videoWidth || 0;
                    var vh = video.videoHeight || 0;
                    var inPiP = document.pictureInPictureElement === video;
                    return {
                        playing: !video.paused,
                        currentTime: video.currentTime,
                        duration: video.duration || 0,
                        isAd: isAd,
                        advertiserURL: advURL,
                        videoWidth: vw,
                        videoHeight: vh,
                        isPiP: inPiP
                    };
                })();
                """
                webView.evaluateJavaScript(script) { result, _ in
                    guard let dict = result as? [String: Any] else { return }
                    DispatchQueue.main.async {
                        if let playing = dict["playing"] as? Bool {
                            self?.isPlaying = playing
                        }
                        if let time = dict["currentTime"] as? Double {
                            self?.currentTime = time
                        }
                        if let dur = dict["duration"] as? Double, dur > 0 {
                            self?.duration = dur
                        }
                        if let ad = dict["isAd"] as? Bool {
                            self?.isAd = ad
                        }
                        if let urlStr = dict["advertiserURL"] as? String, !urlStr.isEmpty {
                            self?.advertiserURL = URL(string: urlStr)
                        } else {
                            self?.advertiserURL = nil
                        }
                        if let width = dict["videoWidth"] as? Double,
                           let height = dict["videoHeight"] as? Double,
                           width > 0, height > 0 {
                            self?.videoAspectRatio = CGFloat(width / height)
                        }
                        if let pip = dict["isPiP"] as? Bool {
                            self?.isPiP = pip
                        }
                    }
                }
            }
        }
    }
}

private enum YouTubePlayerStyles {
    static let css = """
    * { margin: 0 !important; padding: 0 !important; }
    body { overflow: hidden !important; background: #000 !important; }
    #player, .html5-video-player, video {
        position: fixed !important;
        top: 0 !important;
        left: 0 !important;
        width: 100vw !important;
        height: 100vh !important;
        z-index: 999999 !important;
    }
    #secondary, #related, #comments, #info, #meta,
    #above-the-fold, #below, ytd-watch-metadata,
    #masthead-container, #guide, ytd-masthead,
    ytd-mini-guide-renderer, #chat,
    header, ytm-mobile-topbar-renderer, .ytp-ce-element,
    .ytp-cards-teaser, .ytp-youtube-button, .ytp-watermark {
        display: none !important;
    }
    """

    static func injectionScript(css: String) -> String {
        let escaped = css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
        return """
        (function() {
            let styleId = "tsukuyomi-youtube-style";
            let existing = document.getElementById(styleId);
            if (existing) { existing.remove(); }
            const style = document.createElement("style");
            style.id = styleId;
            style.innerHTML = `\(escaped)`;
            document.head.appendChild(style);
        })();
        """
    }
}

private extension UIFont {
    func bolded() -> UIFont {
        let descriptor = fontDescriptor.withSymbolicTraits(.traitBold) ?? fontDescriptor
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
