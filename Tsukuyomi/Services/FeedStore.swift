import Foundation
import Observation

enum FeedStoreError: LocalizedError {
    case duplicateSource

    var errorDescription: String? {
        switch self {
        case .duplicateSource:
            return String(localized: "rss.add.error.duplicate", defaultValue: "This RSS source has already been added.")
        }
    }
}

@MainActor
@Observable
final class FeedStore {
    var sources: [FeedSource] = []
    var articles: [FeedArticle] = []
    var isRefreshing = false
    var highlightedArticleID: FeedArticle.ID?
    private var titleTranslationTasks = Set<FeedArticle.ID>()
    private var isPrefetchingTitleTranslations = false

    private let parser = RSSParser()
    private let fileManager = FileManager.default
    private var logger: AppLogger?

    var unreadCount: Int {
        articles.filter { !$0.isRead }.count
    }

    var pages: [FeedArticle] {
        articles
            .filter { $0.sourceKind == .page }
            .sorted(by: recencySort)
    }

    var clips: [FeedArticle] {
        articles
            .filter { $0.sourceKind == .page || $0.isSaved }
            .sorted(by: recencySort)
    }

    var recentArticles: [FeedArticle] {
        articles
            .filter { $0.sourceKind == .rss }
            .sorted(by: recencySort)
    }

    func bootstrap(logger: AppLogger) async {
        self.logger = logger
        load()
        logger.log("Feed store bootstrapped with \(sources.count) sources and \(articles.count) articles", category: .storage)
    }

    func addFeed(urlString: String) async throws {
        guard let url = URL(string: urlString), let scheme = url.scheme else {
            throw URLError(.badURL)
        }
        logger?.log("Adding feed \(urlString)", category: .rss)
        guard ["http", "https"].contains(scheme.lowercased()) else {
            throw URLError(.unsupportedURL)
        }
        let resolvedURL = try await resolvedFeedURL(from: url)
        let normalizedURL = normalizedSourceURLString(resolvedURL.absoluteString)
        guard !sources.contains(where: { normalizedSourceURLString($0.feedURL) == normalizedURL }) else {
            logger?.log("Blocked duplicate feed add for \(resolvedURL.absoluteString)", category: .rss)
            throw FeedStoreError.duplicateSource
        }
        let parsed = try await fetchFeed(from: resolvedURL)
        var source = FeedSource(
            title: parsed.title.isEmpty ? resolvedURL.host(percentEncoded: false) ?? "Untitled Feed" : parsed.title,
            subtitle: parsed.description,
            feedURL: resolvedURL.absoluteString,
            siteURL: parsed.siteURL.isEmpty ? inferredSiteURL(from: resolvedURL) : parsed.siteURL,
            tintHex: Self.tintPalette[sources.count % Self.tintPalette.count],
            lastRefreshAt: .now,
            articleCount: parsed.articles.count
        )
        source.updatedAt = .now
        sources.insert(source, at: 0)
        mergeArticles(parsed.articles, into: source)
        persist()
        logger?.log("Added feed '\(source.title)' with \(parsed.articles.count) articles", category: .rss)
    }

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        logger?.log("Refreshing all feeds", category: .rss)
        defer { isRefreshing = false }

        for source in sources {
            do {
                try await refresh(sourceID: source.id)
            } catch {
                logger?.log("Failed to refresh \(source.title): \(error.localizedDescription)", category: .network)
            }
        }
    }

    func forceRefreshAll(settingsStore: SettingsStore, logger: AppLogger) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        self.logger = logger
        logger.log("Force refreshing all feeds and clearing title translation cache", category: .rss)
        defer { isRefreshing = false }

        for index in articles.indices where articles[index].sourceKind == .rss {
            articles[index].aiTitleTranslation = nil
            articles[index].updatedAt = .now
        }

        for source in sources {
            do {
                try await refresh(sourceID: source.id)
            } catch {
                logger.log("Failed to refresh \(source.title): \(error.localizedDescription)", category: .network)
            }
        }

        persist()

        guard settingsStore.titleTranslationDisplayMode != .original else { return }
        let articleIDs = recentArticles.map(\.id)
        await prefetchTitleTranslations(for: articleIDs, settingsStore: settingsStore, logger: logger)
    }

    func refresh(sourceID: FeedSource.ID) async throws {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else { return }
        let source = sources[index]
        guard let url = URL(string: source.feedURL) else { throw URLError(.badURL) }
        let parsed = try await fetchFeed(from: url)
        sources[index].title = parsed.title.isEmpty ? source.title : parsed.title
        sources[index].subtitle = parsed.description
        sources[index].siteURL = parsed.siteURL.isEmpty ? source.siteURL : parsed.siteURL
        sources[index].lastRefreshAt = .now
        sources[index].updatedAt = .now
        sources[index].articleCount = parsed.articles.count
        mergeArticles(parsed.articles, into: sources[index])
        persist()
        logger?.log("Refreshed \(sources[index].title)", category: .rss)
    }

    func updateSource(
        sourceID: FeedSource.ID,
        title: String,
        subtitle: String,
        feedURL: String,
        siteURL: String,
        logger: AppLogger
    ) async throws {
        guard let index = sources.firstIndex(where: { $0.id == sourceID }) else { return }
        let trimmedFeedURL = feedURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedFeedURL), let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()) else {
            throw URLError(.badURL)
        }
        let resolvedURL = try await resolvedFeedURL(from: url)
        let normalizedURL = normalizedSourceURLString(resolvedURL.absoluteString)
        guard !sources.contains(where: { $0.id != sourceID && normalizedSourceURLString($0.feedURL) == normalizedURL }) else {
            logger.log("Blocked duplicate feed update for \(resolvedURL.absoluteString)", category: .rss)
            throw FeedStoreError.duplicateSource
        }

        sources[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        sources[index].subtitle = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        sources[index].feedURL = resolvedURL.absoluteString
        sources[index].siteURL = siteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        sources[index].updatedAt = .now

        for articleIndex in articles.indices where articles[articleIndex].feedID == sourceID {
            articles[articleIndex].feedTitle = sources[index].title
            articles[articleIndex].updatedAt = .now
        }

        persist()
        logger.log("Updated RSS source \(sources[index].title)", category: .rss)
    }

    func removeSource(sourceID: FeedSource.ID, logger: AppLogger) {
        guard let source = sources.first(where: { $0.id == sourceID }) else { return }
        let removedArticleCount = articles.filter { $0.feedID == sourceID }.count
        sources.removeAll(where: { $0.id == sourceID })
        articles.removeAll(where: { $0.feedID == sourceID })
        persist()
        logger.log("Removed RSS source \(source.title) and \(removedArticleCount) related articles", category: .rss)
    }

    func toggleRead(for articleID: FeedArticle.ID) {
        guard let index = articles.firstIndex(where: { $0.id == articleID }) else { return }
        articles[index].isRead.toggle()
        articles[index].updatedAt = .now
        persist()
        logger?.log("Toggled read state for \(articles[index].title)", category: .rss)
    }

    func markRead(for articleID: FeedArticle.ID) {
        guard let index = articles.firstIndex(where: { $0.id == articleID }) else { return }
        guard !articles[index].isRead else { return }
        articles[index].isRead = true
        articles[index].updatedAt = .now
        persist()
        logger?.log("Marked article as read: \(articles[index].title)", category: .rss)
    }

    func toggleClip(for articleID: FeedArticle.ID, logger: AppLogger) {
        guard let index = articles.firstIndex(where: { $0.id == articleID }) else { return }
        articles[index].isSaved.toggle()
        articles[index].updatedAt = .now
        persist()
        let state = articles[index].isSaved ? "added to" : "removed from"
        logger.log("Article \(state) clips: \(articles[index].title)", category: .rss)
    }

    func removeClip(articleID: FeedArticle.ID, logger: AppLogger) {
        guard let index = articles.firstIndex(where: { $0.id == articleID }) else { return }
        if articles[index].sourceKind == .page {
            let title = articles[index].title
            articles.remove(at: index)
            persist()
            logger.log("Removed saved page \(title)", category: .rss)
            return
        }

        guard articles[index].isSaved else { return }
        articles[index].isSaved = false
        articles[index].updatedAt = .now
        persist()
        logger.log("Removed article from clips: \(articles[index].title)", category: .rss)
    }

    func article(id: FeedArticle.ID) -> FeedArticle? {
        articles.first(where: { $0.id == id })
    }

    func storeAIResult(summary: String? = nil, translation: String? = nil, for articleID: FeedArticle.ID) {
        guard let index = articles.firstIndex(where: { $0.id == articleID }) else { return }
        if let summary {
            articles[index].aiSummary = summary
        }
        if let translation {
            articles[index].aiTranslation = translation
        }
        articles[index].updatedAt = .now
        persist()
        logger?.log("Stored AI result for \(articles[index].title)", category: .ai)
    }

    func storeTitleTranslation(_ translation: String, for articleID: FeedArticle.ID) {
        guard let index = articles.firstIndex(where: { $0.id == articleID }) else { return }
        articles[index].aiTitleTranslation = translation.trimmingCharacters(in: .whitespacesAndNewlines)
        articles[index].updatedAt = .now
        persist()
        logger?.log("Stored title translation for \(articles[index].title)", category: .ai)
    }

    func prefetchTitleTranslations(
        for articleIDs: [FeedArticle.ID],
        settingsStore: SettingsStore,
        logger: AppLogger
    ) async {
        guard settingsStore.titleTranslationDisplayMode != .original else { return }
        guard let provider = settingsStore.defaultProvider else { return }
        guard !isPrefetchingTitleTranslations else {
            logger.log("Skipped title translation prefetch because another batch is already running", category: .ai)
            return
        }

        var seenArticleIDs = Set<FeedArticle.ID>()
        let uniqueArticleIDs = articleIDs.filter { seenArticleIDs.insert($0).inserted }
        guard !uniqueArticleIDs.isEmpty else { return }

        isPrefetchingTitleTranslations = true
        defer { isPrefetchingTitleTranslations = false }

        for articleID in uniqueArticleIDs {
            guard let article = article(id: articleID) else { continue }
            guard article.aiTitleTranslation?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else { continue }
            guard !titleTranslationTasks.contains(articleID) else { continue }
            titleTranslationTasks.insert(articleID)
            defer { titleTranslationTasks.remove(articleID) }
            do {
                let service = AIService(configuration: provider, logger: logger)
                let translation = try await service.translateTitle(
                    articleTitle: article.title,
                    feedTitle: article.feedTitle,
                    outputLanguage: settingsStore.aiOutputLanguage
                )
                storeTitleTranslation(translation, for: articleID)
            } catch {
                guard !isCancellation(error) else { continue }
                logger.log("Failed to translate article title '\(article.title)': \(error.localizedDescription)", category: .ai)
            }
        }
    }

    @discardableResult
    func addPage(urlString: String) async throws -> FeedArticle.ID {
        guard let url = URL(string: urlString), let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()) else {
            throw URLError(.badURL)
        }
        logger?.log("Adding page \(urlString)", category: .rss)
        let startedAt = logger?.logRequestStart(method: "GET", url: url, context: "page.fetch")
        let (data, response) = try await URLSession.shared.data(from: url)
        if let startedAt {
            logger?.logResponse(method: "GET", url: url, context: "page.fetch", startedAt: startedAt, response: response, dataSize: data.count)
        }
        if let mediaKind = directMediaKind(for: url, response: response) {
            let pageArticle = makeDirectMediaPageArticle(url: url, mediaKind: mediaKind)
            savePageArticle(pageArticle)
            logger?.log("Saved direct media page '\(pageArticle.title)'", category: .rss)
            return pageArticle.id
        }
        let html = String(decoding: data, as: UTF8.self)
        let pageArticle = makePageArticle(
            url: url,
            pageTitle: extractPageTitle(from: html),
            html: html
        )
        savePageArticle(pageArticle)
        logger?.log("Saved page '\(pageArticle.title)'", category: .rss)
        return pageArticle.id
    }

    @discardableResult
    func importPageSnapshot(urlString: String, pageTitle: String?, html: String, logger: AppLogger) throws -> FeedArticle.ID {
        guard let url = URL(string: urlString), let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()) else {
            throw URLError(.badURL)
        }
        let pageArticle = makePageArticle(url: url, pageTitle: pageTitle, html: html)
        savePageArticle(pageArticle)
        logger.log("Imported page snapshot '\(pageArticle.title)' from in-app browser", category: .rss)
        return pageArticle.id
    }

    func updatePage(articleID: FeedArticle.ID, title: String, urlString: String, logger: AppLogger) throws {
        guard let index = articles.firstIndex(where: { $0.id == articleID && $0.sourceKind == .page }) else { return }
        let trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL), let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()) else {
            throw URLError(.badURL)
        }
        articles[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        articles[index].url = trimmedURL
        articles[index].author = url.host()
        articles[index].updatedAt = .now
        persist()
        logger.log("Updated saved page \(articles[index].title)", category: .rss)
    }

    func removePage(articleID: FeedArticle.ID, logger: AppLogger) {
        guard let article = articles.first(where: { $0.id == articleID && $0.sourceKind == .page }) else { return }
        articles.removeAll(where: { $0.id == articleID })
        persist()
        logger.log("Removed saved page \(article.title)", category: .rss)
    }

    func ensureArticleContent(for articleID: FeedArticle.ID) async {
        guard let index = articles.firstIndex(where: { $0.id == articleID }) else { return }
        let article = articles[index]
        guard article.sourceKind == .rss else { return }
        guard let enrichReason = enrichmentReason(for: article) else {
            logger?.log("Skipped article enrichment for '\(article.title)' because current content is already sufficient", category: .rss)
            return
        }
        guard let url = URL(string: article.url) else { return }

        do {
            logger?.log("Fetching article body for '\(article.title)' because \(enrichReason)", category: .rss)
            let enriched = try await fetchReadableArticle(from: url, title: article.title)
            guard let text = enriched.content,
                  text.count > article.bodyText.trimmingCharacters(in: .whitespacesAndNewlines).count else {
                logger?.log("Skipped article body update for '\(article.title)' because fetched content was not longer than stored content", category: .rss)
                return
            }
            articles[index].content = normalizeContent(
                text,
                articleURL: article.url,
                siteURL: sourceURL(for: article.feedID)
            )
            if articles[index].summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                articles[index].summary = enriched.summary
            }
            if articles[index].imageURL == nil {
                articles[index].imageURL = normalizedImageURL(
                    enriched.imageURL,
                    articleURL: article.url,
                    siteURL: sourceURL(for: article.feedID)
                )
            }
            articles[index].updatedAt = .now
            persist()
            logger?.log("Updated article body for '\(article.title)'", category: .rss)
        } catch {
            logger?.log("Failed to fetch article body for '\(article.title)': \(error.localizedDescription)", category: .network)
        }
    }

    private func fetchFeed(from url: URL) async throws -> ParsedFeed {
        logger?.log("Fetching feed \(url.absoluteString)", category: .network)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        let startedAt = logger?.logRequestStart(method: "GET", url: url, context: "rss.feed")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let startedAt {
            logger?.logResponse(method: "GET", url: url, context: "rss.feed", startedAt: startedAt, response: response, dataSize: data.count)
        }
        guard let parsed = parser.parse(data: data) else {
            throw URLError(.cannotParseResponse)
        }
        logger?.log("Parsed feed '\(parsed.title)' with \(parsed.articles.count) articles", category: .rss)
        return parsed
    }

    private func mergeArticles(_ parsedArticles: [ParsedArticle], into source: FeedSource) {
        var newArticles: [FeedArticle] = []

        for item in parsedArticles {
            let existing = articles.first(where: { $0.url == item.url })
            var article = existing ?? FeedArticle(
                feedID: source.id,
                feedTitle: source.title,
                sourceKind: .rss,
                title: item.title,
                url: item.url,
                author: item.author,
                summary: item.summary ?? "",
                content: item.content ?? item.summary ?? "",
                imageURL: item.imageURL,
                videoURL: item.videoURL,
                audioURL: item.audioURL,
                mediaDuration: item.duration,
                publishedDate: item.publishedDate
            )
            article.feedID = source.id
            article.feedTitle = source.title
            article.title = item.title
            article.author = item.author
            article.summary = item.summary ?? article.summary
            article.content = normalizeContent(
                item.content ?? item.summary ?? article.content,
                articleURL: item.url,
                siteURL: source.siteURL
            )
            article.imageURL = normalizedImageURL(
                item.imageURL ?? article.imageURL,
                articleURL: item.url,
                siteURL: source.siteURL
            )
            article.videoURL = item.videoURL ?? article.videoURL
            article.audioURL = item.audioURL ?? article.audioURL
            article.mediaDuration = item.duration ?? article.mediaDuration
            article.publishedDate = item.publishedDate ?? article.publishedDate
            article.updatedAt = .now
            newArticles.append(article)
        }

        let incomingURLs = Set(newArticles.map(\.url))
        let retained = articles.filter { existingArticle in
            existingArticle.feedID != source.id && !incomingURLs.contains(existingArticle.url)
        }
        articles = (retained + newArticles)
            .uniqued(by: \.url)
            .sorted(by: recencySort)
    }

    private func persist() {
        let payload = FeedStorePayload(
            schemaVersion: 2,
            savedAt: .now,
            appVersion: AppBuild.version,
            sources: sources,
            articles: articles
        )
        do {
            try writePayload(payload, to: storeURL, backupExistingPrimary: true)
            logger?.log("Persisted feed store to disk", category: .storage)
        } catch {
            logger?.log("Failed to persist feed store: \(error.localizedDescription)", category: .storage)
        }
    }

    private func load() {
        do {
            let payload = try loadPayload(from: storeURL)
            apply(payload: payload, origin: "primary")
            return
        } catch {
            logger?.log("Primary feed store load failed: \(error.localizedDescription)", category: .storage)
        }

        do {
            let payload = try loadPayload(from: backupStoreURL)
            apply(payload: payload, origin: "backup")
            try writePayload(payload, to: storeURL, backupExistingPrimary: false)
            logger?.log("Recovered feed store from backup after primary load failure", category: .storage)
        } catch {
            sources = []
            articles = []
            logger?.log("Failed to recover feed store from disk or backup: \(error.localizedDescription)", category: .storage)
        }
    }

    private var storeURL: URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appending(path: "Tsukuyomi/feed-store.json")
    }

    private var backupStoreURL: URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return root.appending(path: "Tsukuyomi/feed-store.backup.json")
    }

    private let recencySort: (FeedArticle, FeedArticle) -> Bool = { lhs, rhs in
        (lhs.publishedDate ?? lhs.updatedAt) > (rhs.publishedDate ?? rhs.updatedAt)
    }

    private struct FeedStorePayload: Codable {
        var schemaVersion: Int = 1
        var savedAt: Date?
        var appVersion: String?
        var sources: [FeedSource]
        var articles: [FeedArticle]

        private enum CodingKeys: String, CodingKey {
            case schemaVersion
            case savedAt
            case appVersion
            case sources
            case articles
        }

        init(
            schemaVersion: Int = 1,
            savedAt: Date? = nil,
            appVersion: String? = nil,
            sources: [FeedSource],
            articles: [FeedArticle]
        ) {
            self.schemaVersion = schemaVersion
            self.savedAt = savedAt
            self.appVersion = appVersion
            self.sources = sources
            self.articles = articles
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
            savedAt = try container.decodeIfPresent(Date.self, forKey: .savedAt)
            appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion)
            sources = try container.decode([FeedSource].self, forKey: .sources)
            articles = try container.decode([FeedArticle].self, forKey: .articles)
        }
    }

    private struct LegacyFeedStorePayload: Codable {
        var sources: [FeedSource]
        var articles: [FeedArticle]
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }

    private static let tintPalette = [
        "#B6542D",
        "#2F5D62",
        "#85754D",
        "#6D597A",
        "#3C6E71"
    ]

    private func enrichmentReason(for article: FeedArticle) -> String? {
        let summary = article.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = article.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
            return "content is empty"
        }
        if content.count < 420 {
            return "content is shorter than 420 characters"
        }
        if !summary.isEmpty && content == summary {
            return "content is identical to summary"
        }
        if !content.contains("!["),
           content.count < 2_400 {
            return "content has no inline images and is shorter than 2400 characters"
        }
        return nil
    }

    private func fetchReadableArticle(from url: URL, title: String) async throws -> EnrichedArticle {
        var request = URLRequest(url: url)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        let startedAt = logger?.logRequestStart(method: request.httpMethod ?? "GET", url: url, context: "rss.article")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let startedAt {
            logger?.logResponse(method: request.httpMethod ?? "GET", url: url, context: "rss.article", startedAt: startedAt, response: response, dataSize: data.count)
        }
        let html = decodeHTML(from: data, response: response)
        let content = ArticleExtractor.extractText(fromHTML: html, excludeTitle: title) ?? extractPageText(from: html)
        let summary = extractPageSummary(from: html)
        let imageURL = normalizedImageURL(
            extractOpenGraphImage(from: html),
            articleURL: url.absoluteString,
            siteURL: url.deletingLastPathComponent().absoluteString
        )
        return EnrichedArticle(
            content: content?.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary,
            imageURL: imageURL
        )
    }

    private func decodeHTML(from data: Data, response: URLResponse) -> String {
        if let response = response as? HTTPURLResponse,
           let encodingName = response.textEncodingName {
            let cfEncoding = CFStringConvertIANACharSetNameToEncoding(encodingName as CFString)
            if cfEncoding != kCFStringEncodingInvalidId {
                let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
                let stringEncoding = String.Encoding(rawValue: nsEncoding)
                if let html = String(data: data, encoding: stringEncoding) {
                    return html
                }
            }
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    private func extractPageTitle(from html: String) -> String? {
        firstMatch(in: html, pattern: #"<meta property=["']og:title["'] content=["']([^"']+)["']"#)
            ?? firstMatch(in: html, pattern: #"<title[^>]*>(.*?)</title>"#)
    }

    private func extractOpenGraphImage(from html: String) -> String? {
        firstMatch(in: html, pattern: #"<meta property=["']og:image["'] content=["']([^"']+)["']"#)
            ?? firstMatch(in: html, pattern: #"<meta name=["']twitter:image["'] content=["']([^"']+)["']"#)
    }

    private func extractOpenGraphVideo(from html: String) -> String? {
        firstMatch(in: html, pattern: #"<meta property=["']og:video(?::secure_url|:url)?["'] content=["']([^"']+)["']"#)
            ?? firstMatch(in: html, pattern: #"<meta name=["']twitter:player:stream["'] content=["']([^"']+)["']"#)
            ?? firstMatch(in: html, pattern: #"<video[^>]+src=["']([^"']+)["']"#)
            ?? firstMatch(in: html, pattern: #"<source[^>]+src=["']([^"']+)["'][^>]+type=["']video/[^"']+["']"#)
    }

    private func extractOpenGraphAudio(from html: String) -> String? {
        firstMatch(in: html, pattern: #"<meta property=["']og:audio(?::secure_url|:url)?["'] content=["']([^"']+)["']"#)
            ?? firstMatch(in: html, pattern: #"<audio[^>]+src=["']([^"']+)["']"#)
            ?? firstMatch(in: html, pattern: #"<source[^>]+src=["']([^"']+)["'][^>]+type=["']audio/[^"']+["']"#)
    }

    private func sourceURL(for feedID: FeedSource.ID) -> String? {
        sources.first(where: { $0.id == feedID })?.siteURL
    }

    private func inferredSiteURL(from feedURL: URL) -> String {
        if let host = feedURL.host(percentEncoded: false) {
            let scheme = feedURL.scheme ?? "https"
            return "\(scheme)://\(host)"
        }
        return feedURL.deletingLastPathComponent().absoluteString
    }

    private func resolvedFeedURL(from url: URL) async throws -> URL {
        guard let host = url.host(percentEncoded: false)?.lowercased(),
              host.contains("youtube.com") || host.contains("youtu.be") else {
            return url
        }

        if url.path.lowercased().contains("/feeds/videos.xml") {
            return url
        }

        if let playlistID = youtubePlaylistID(from: url) {
            let feedURL = youtubePlaylistFeedURL(for: playlistID)
            logger?.log("Resolved YouTube playlist \(url.absoluteString) to \(feedURL.absoluteString)", category: .rss)
            return feedURL
        }

        if let channelID = youtubeChannelID(from: url) {
            return youtubeFeedURL(for: channelID)
        }

        let lookupURL = youtubeLookupURL(from: url)
        let requestStartedAt = logger?.logRequestStart(method: "GET", url: lookupURL, context: "rss.youtube.resolve")
        let (data, response) = try await URLSession.shared.data(from: lookupURL)
        if let requestStartedAt {
            logger?.logResponse(method: "GET", url: lookupURL, context: "rss.youtube.resolve", startedAt: requestStartedAt, response: response, dataSize: data.count)
        }
        let html = decodeHTML(from: data, response: response)
        if let playlistID = extractYouTubePlaylistID(from: html) {
            let feedURL = youtubePlaylistFeedURL(for: playlistID)
            logger?.log("Resolved YouTube HTML \(url.absoluteString) to playlist feed \(feedURL.absoluteString)", category: .rss)
            return feedURL
        }
        if let channelID = extractYouTubeChannelID(from: html) {
            let feedURL = youtubeFeedURL(for: channelID)
            logger?.log("Resolved YouTube URL \(url.absoluteString) to channel feed \(feedURL.absoluteString)", category: .rss)
            return feedURL
        }

        logger?.log("Unable to resolve YouTube channel feed for \(url.absoluteString), using original URL", category: .rss)
        return url
    }

    private func youtubeChannelID(from url: URL) -> String? {
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let channelID = components.queryItems?.first(where: { $0.name == "channel_id" })?.value,
           channelID.hasPrefix("UC") {
            return channelID
        }
        let components = url.pathComponents.filter { $0 != "/" }
        if let channelIndex = components.firstIndex(of: "channel"),
           components.indices.contains(channelIndex + 1) {
            let channelID = components[channelIndex + 1]
            return channelID.hasPrefix("UC") ? channelID : nil
        }
        return nil
    }

    private func extractYouTubeChannelID(from html: String) -> String? {
        firstMatch(in: html, pattern: #"<meta itemprop=["']channelId["'] content=["'](UC[^"']+)["']"#)
            ?? firstMatch(in: html, pattern: #"\"channelId\":\"(UC[^\"]+)\""#)
            ?? firstMatch(in: html, pattern: #""channelId":"(UC[^"]+)""#)
            ?? firstMatch(in: html, pattern: #"\"externalId\":\"(UC[^\"]+)\""#)
            ?? firstMatch(in: html, pattern: #""externalId":"(UC[^"]+)""#)
            ?? firstMatch(in: html, pattern: #""browseId":"(UC[^"]+)""#)
            ?? firstMatch(in: html, pattern: #"channelMetadataRenderer\":\{\"title\":\".*?\",\"externalId\":\"(UC[^\"]+)\""#)
            ?? firstMatch(in: html, pattern: #"https:\\/\\/www\.youtube\.com\\/feeds\\/videos\.xml\\?channel_id=(UC[^\"]+)"#)
            ?? firstMatch(in: html, pattern: #"feeds/videos\.xml\?channel_id=(UC[^"&]+)"#)
    }

    private func youtubeFeedURL(for channelID: String) -> URL {
        URL(string: "https://www.youtube.com/feeds/videos.xml?channel_id=\(channelID)")!
    }

    private func youtubePlaylistID(from url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let playlistID = components.queryItems?.first(where: { $0.name == "list" })?.value,
              !playlistID.isEmpty else {
            return nil
        }
        return playlistID
    }

    private func extractYouTubePlaylistID(from html: String) -> String? {
        firstMatch(in: html, pattern: #"\"playlistId\":\"([^\"]+)\""#)
            ?? firstMatch(in: html, pattern: #""playlistId":"([^"]+)""#)
            ?? firstMatch(in: html, pattern: #"https:\\/\\/www\.youtube\.com\\/feeds\\/videos\.xml\\?playlist_id=([^\"]+)"#)
            ?? firstMatch(in: html, pattern: #"feeds/videos\.xml\?playlist_id=([^"&]+)"#)
    }

    private func youtubePlaylistFeedURL(for playlistID: String) -> URL {
        URL(string: "https://www.youtube.com/feeds/videos.xml?playlist_id=\(playlistID)")!
    }

    private func youtubeLookupURL(from url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let pathComponents = components.path.split(separator: "/").map(String.init)
        if let first = pathComponents.first, first.hasPrefix("@") {
            components.path = "/\(first)"
            return components.url ?? url
        }
        if let key = pathComponents.first,
           ["channel", "c", "user"].contains(key),
           pathComponents.count >= 2 {
            components.path = "/\(key)/\(pathComponents[1])"
            return components.url ?? url
        }
        return url
    }

    private func savePageArticle(_ pageArticle: FeedArticle) {
        articles.removeAll(where: { $0.url == pageArticle.url && $0.sourceKind == .page })
        articles.insert(pageArticle, at: 0)
        persist()
    }

    private func makePageArticle(url: URL, pageTitle: String?, html: String) -> FeedArticle {
        let resolvedTitle = (pageTitle ?? extractPageTitle(from: html) ?? url.host() ?? url.absoluteString)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let extractedContent = ArticleExtractor.extractText(fromHTML: html, excludeTitle: resolvedTitle)
        let pageVideoURL = normalizedPlayableMediaURL(
            extractOpenGraphVideo(from: html),
            articleURL: url.absoluteString,
            siteURL: url.deletingLastPathComponent().absoluteString
        ) ?? youtubeWatchURL(from: url, html: html)
        let pageAudioURL = normalizedPlayableMediaURL(
            extractOpenGraphAudio(from: html),
            articleURL: url.absoluteString,
            siteURL: url.deletingLastPathComponent().absoluteString
        )
        return FeedArticle(
            feedID: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
            feedTitle: String(localized: "pages.title", defaultValue: "Pages"),
            sourceKind: .page,
            title: resolvedTitle.isEmpty ? url.absoluteString : resolvedTitle,
            url: url.absoluteString,
            author: url.host(),
            summary: extractPageSummary(from: html),
            content: normalizeContent(
                extractedContent ?? extractPageText(from: html) ?? url.absoluteString,
                articleURL: url.absoluteString,
                siteURL: url.deletingLastPathComponent().absoluteString
            ),
            imageURL: normalizedImageURL(
                extractOpenGraphImage(from: html),
                articleURL: url.absoluteString,
                siteURL: url.deletingLastPathComponent().absoluteString
            ),
            videoURL: pageVideoURL,
            audioURL: pageAudioURL,
            mediaDuration: nil,
            publishedDate: .now,
            isRead: false,
            isSaved: true
        )
    }

    private func makeDirectMediaPageArticle(url: URL, mediaKind: DirectMediaKind) -> FeedArticle {
        let title = url.deletingPathExtension().lastPathComponent.isEmpty ? (url.host() ?? url.absoluteString) : url.deletingPathExtension().lastPathComponent
        return FeedArticle(
            feedID: UUID(uuidString: "00000000-0000-0000-0000-000000000001") ?? UUID(),
            feedTitle: String(localized: "pages.title", defaultValue: "Pages"),
            sourceKind: .page,
            title: title,
            url: url.absoluteString,
            author: url.host(),
            summary: "",
            content: url.absoluteString,
            imageURL: nil,
            videoURL: mediaKind == .video ? url.absoluteString : nil,
            audioURL: mediaKind == .audio ? url.absoluteString : nil,
            mediaDuration: nil,
            publishedDate: .now,
            isRead: false,
            isSaved: true
        )
    }

    private func normalizedPlayableMediaURL(_ rawURL: String?, articleURL: String, siteURL: String?) -> String? {
        normalizedImageURL(rawURL, articleURL: articleURL, siteURL: siteURL)
    }

    private func youtubeWatchURL(from pageURL: URL, html: String) -> String? {
        if isYouTubeURL(pageURL) {
            return pageURL.absoluteString
        }
        return firstMatch(in: html, pattern: #"https://www\.youtube\.com/watch\?v=[A-Za-z0-9_-]{6,}"#)
            ?? firstMatch(in: html, pattern: #"https://youtu\.be/[A-Za-z0-9_-]{6,}"#)
    }

    private func isYouTubeURL(_ url: URL) -> Bool {
        guard let host = url.host(percentEncoded: false)?.lowercased() else { return false }
        return host.contains("youtube.com") || host.contains("youtu.be")
    }

    private func directMediaKind(for url: URL, response: URLResponse) -> DirectMediaKind? {
        let mimeType = response.mimeType?.lowercased()
        let pathExtension = url.pathExtension.lowercased()
        if let mimeType {
            if mimeType.hasPrefix("audio/") || mimeType == "application/vnd.apple.mpegurl" && pathExtension == "m3u8" && url.absoluteString.contains("/audio") {
                return .audio
            }
            if mimeType.hasPrefix("video/") || mimeType == "application/x-mpegurl" || mimeType == "application/vnd.apple.mpegurl" {
                return .video
            }
        }

        if ["mp3", "m4a", "aac", "wav", "flac", "ogg"].contains(pathExtension) {
            return .audio
        }
        if ["mp4", "m4v", "mov", "webm", "m3u8"].contains(pathExtension) {
            return .video
        }
        return nil
    }

    private func loadPayload(from url: URL) throws -> FeedStorePayload {
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(FeedStorePayload.self, from: data)
        } catch {
            let legacy = try JSONDecoder().decode(LegacyFeedStorePayload.self, from: data)
            logger?.log("Migrated legacy feed store payload from \(url.lastPathComponent)", category: .storage)
            return FeedStorePayload(
                schemaVersion: 1,
                savedAt: nil,
                appVersion: nil,
                sources: legacy.sources,
                articles: legacy.articles
            )
        }
    }

    private func apply(payload: FeedStorePayload, origin: String) {
        sources = payload.sources
        articles = payload.articles
            .map { article in
                var normalized = article
                normalized.content = normalizeContent(
                    article.content,
                    articleURL: article.url,
                    siteURL: sourceURL(for: article.feedID)
                )
                return normalized
            }
            .sorted(by: recencySort)
        logger?.log("Loaded \(origin) feed store payload schema=\(payload.schemaVersion) savedAt=\(payload.savedAt?.formatted(date: .abbreviated, time: .shortened) ?? "unknown") version=\(payload.appVersion ?? "unknown")", category: .storage)
    }

    private func writePayload(_ payload: FeedStorePayload, to url: URL, backupExistingPrimary: Bool) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if backupExistingPrimary, fileManager.fileExists(atPath: storeURL.path()) {
            try? fileManager.removeItem(at: backupStoreURL)
            try? fileManager.copyItem(at: storeURL, to: backupStoreURL)
        }
        let data = try JSONEncoder().encode(payload)
        try data.write(to: url, options: .atomic)
    }

    private enum DirectMediaKind {
        case video
        case audio
    }

    private func normalizedImageURL(_ imageURL: String?, articleURL: String, siteURL: String?) -> String? {
        guard let imageURL, !imageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let trimmed = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("data:") {
            return trimmed
        }
        if let absolute = URL(string: trimmed), absolute.scheme != nil {
            return absolute.absoluteString
        }
        if trimmed.hasPrefix("//"),
           let articleURL = URL(string: articleURL),
           let scheme = articleURL.scheme {
            return "\(scheme):\(trimmed)"
        }

        let candidateBases = [articleURL, siteURL].compactMap { $0 }
        for base in candidateBases {
            if let baseURL = URL(string: base),
               let resolved = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL {
                return resolved.absoluteString
            }
        }
        return trimmed
    }

    private func normalizeContent(_ content: String, articleURL: String, siteURL: String?) -> String {
        var normalized = content.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized = replaceLegacyImagePlaceholders(in: normalized, articleURL: articleURL, siteURL: siteURL)
        normalized = normalizeMarkdownImageURLs(in: normalized, articleURL: articleURL, siteURL: siteURL)
        normalized = normalized.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func replaceLegacyImagePlaceholders(in content: String, articleURL: String, siteURL: String?) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\{\{IMG\}\}(.*?)\{\{/IMG\}\}"#, options: [.dotMatchesLineSeparators]) else {
            return content
        }

        var result = content
        let nsContent = result as NSString
        let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsContent.length))
        for match in matches.reversed() {
            let rawURL = nsContent.substring(with: match.range(at: 1))
            let resolved = normalizedImageURL(rawURL, articleURL: articleURL, siteURL: siteURL) ?? rawURL
            let replacement = "\n\n![](\(resolved))\n\n"
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
        }
        return result
    }

    private func normalizeMarkdownImageURLs(in content: String, articleURL: String, siteURL: String?) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^)]+)\)"#) else {
            return content
        }

        var result = content
        let nsContent = result as NSString
        let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsContent.length))
        for match in matches.reversed() {
            let alt = nsContent.substring(with: match.range(at: 1))
            let rawURL = nsContent.substring(with: match.range(at: 2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            let resolved = normalizedImageURL(rawURL, articleURL: articleURL, siteURL: siteURL) ?? rawURL
            let replacement = "![\(alt)](\(resolved))"
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
        }
        return result
    }

    private func extractPageSummary(from html: String) -> String {
        if let summary = firstMatch(in: html, pattern: #"<meta name=["']description["'] content=["']([^"']+)["']"#) {
            return summary
        }
        let text = extractPageText(from: html) ?? ""
        return String(text.prefix(220))
    }

    private func extractPageText(from html: String) -> String? {
        var result = html
        result = result.replacingOccurrences(of: #"<script[\s\S]*?</script>"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"<style[\s\S]*?</style>"#, with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: #"</p>|</div>|</li>|</article>|</section>|</h1>|</h2>|</h3>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: #"&nbsp;"#, with: " ")
        result = result.replacingOccurrences(of: #"&amp;"#, with: "&")
        result = result.replacingOccurrences(of: #"&lt;"#, with: "<")
        result = result.replacingOccurrences(of: #"&gt;"#, with: ">")
        result = result.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let nsText = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              match.numberOfRanges > 1 else {
            return nil
        }
        return nsText.substring(with: match.range(at: 1))
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedSourceURLString(_ input: String) -> String {
        guard let url = URL(string: input) else {
            return input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        let path = components?.percentEncodedPath ?? ""
        if path.hasSuffix("/") && path.count > 1 {
            components?.percentEncodedPath = String(path.dropLast())
        }
        return components?.string?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            ?? input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private struct EnrichedArticle {
        let content: String?
        let summary: String
        let imageURL: String?
    }
}

private extension Array where Element == FeedArticle {
    func uniqued(by keyPath: KeyPath<FeedArticle, String>) -> [FeedArticle] {
        var seen = Set<String>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}
