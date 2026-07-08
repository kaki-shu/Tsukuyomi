import SwiftUI

struct ArticleDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FeedStore.self) private var feedStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(AppLogger.self) private var appLogger

    let articleID: FeedArticle.ID

    @State private var isRunningSummary = false
    @State private var isRunningTranslation = false
    @State private var errorMessage: String?
    @State private var showingSummaryOutput = false
    @State private var showingTranslationOutput = false
    @State private var streamingTranslationText = ""
    @State private var lastStreamRenderLength = 0
    @State private var browserDestination: BrowserSheetDestination?
    @State private var generatedArticleID: FeedArticle.ID?
    @State private var isViewActive = false

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                if let article {
                    let contentWidth = max(0, min(proxy.size.width - 32, 720))
                    VStack(alignment: .leading, spacing: 18) {
                        header(for: article)
                        actionBar(for: article)
                        if shouldShowSummary(for: article) {
                            aiOutputSection(
                                title: String(localized: "article.ai.summary", defaultValue: "AI Summary"),
                                content: article.aiSummary,
                                loading: isRunningSummary
                            )
                        }
                        articleImage(for: article, contentWidth: contentWidth)
                        ArticleMediaSection(article: article)
                        articleBody(for: article)
                        linkSection(for: article)
                    }
                    .frame(width: contentWidth, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                }
            }
        }
        .background(Color.pageBackgroundTop)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $browserDestination) { destination in
            ArticleBrowserView(initialURL: destination.url) { articleID in
                generatedArticleID = articleID
            }
        }
        .navigationDestination(item: $generatedArticleID) { generatedArticleID in
            ArticleDestinationView(articleID: generatedArticleID)
        }
        .toolbar {
            if let article {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        appLogger.logUI("Toggled clip state from article detail for \(article.id.uuidString.prefix(8))")
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
        .task {
            isViewActive = true
            if let article {
                appLogger.logUI("Opened article detail for '\(article.title)' [\(article.id.uuidString.prefix(8))]")
                feedStore.markRead(for: article.id)
                await feedStore.ensureArticleContent(for: article.id)
                await feedStore.prefetchTitleTranslations(
                    for: [article.id],
                    settingsStore: settingsStore,
                    logger: appLogger
                )
                await runAutomaticActionsIfNeeded(for: article.id)
            }
        }
        .onDisappear {
            isViewActive = false
        }
        .alert(String(localized: "article.ai.error.title", defaultValue: "AI Request Failed"), isPresented: Binding(get: {
            errorMessage != nil
        }, set: { value in
            if !value { errorMessage = nil }
        })) {
            Button(String(localized: "action.ok", defaultValue: "OK"), role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
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

    private func header(for article: FeedArticle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(article.feedTitle.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accentCinder)
            titleBlock(for: article)
            ViewThatFits(in: .vertical) {
                HStack {
                    if let author = article.author, !author.isEmpty {
                        Text(author)
                    }
                    Spacer(minLength: 12)
                    if let publishedDate = article.publishedDate {
                        Text(publishedDate.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    if let author = article.author, !author.isEmpty {
                        Text(author)
                    }
                    if let publishedDate = article.publishedDate {
                        Text(publishedDate.formatted(date: .abbreviated, time: .shortened))
                    }
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func titleBlock(for article: FeedArticle) -> some View {
        let translatedTitle = nonBlank(article.aiTitleTranslation)
        switch settingsStore.titleTranslationDisplayMode {
        case .original:
            articleTitleText(article.title)
        case .translationOnly:
            articleTitleText(translatedTitle ?? article.title)
        case .bilingual:
            VStack(alignment: .leading, spacing: 8) {
                articleTitleText(article.title)
                if let translatedTitle {
                    articleTitleText(translatedTitle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func articleTitleText(_ title: String) -> some View {
        Text(title)
            .font(settingsStore.titleFont.font(size: 30, weight: .bold))
            .foregroundStyle(Color.primaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    @ViewBuilder
    private func articleImage(for article: FeedArticle, contentWidth: CGFloat) -> some View {
        if let imageURL = article.imageURL,
           let url = URL(string: imageURL),
           !bodyContainsImage(imageURL, in: article.bodyText) {
            CachedRemoteImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.buttonSurface)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title2)
                            .foregroundStyle(Color.accentCinder.opacity(0.7))
                    }
            }
            .frame(width: contentWidth, height: min(320, max(180, contentWidth * 0.62)))
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private func actionBar(for article: FeedArticle) -> some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 10) {
                TsukuyomiForceableActionButton(
                    title: String(localized: "article.ai.summarize", defaultValue: "Summarize"),
                    systemImage: "text.append",
                    isActive: isRunningSummary || showingSummaryOutput
                ) {
                    toggleSummary(for: article)
                } forceAction: {
                    forceRegenerateSummary(for: article)
                }

                TsukuyomiForceableActionButton(
                    title: String(localized: "article.ai.translate", defaultValue: "Translate"),
                    systemImage: "character.bubble",
                    isActive: shouldShowTranslation(for: article)
                ) {
                    toggleTranslation(for: article)
                } forceAction: {
                    forceRegenerateTranslation(for: article)
                }
            }

            Spacer(minLength: 12)

            Button {
                if let url = URL(string: article.url) {
                    appLogger.logUI("Opened article detail browser button for \(url.absoluteString)")
                    browserDestination = BrowserSheetDestination(url: url)
                }
            } label: {
                TsukuyomiActionButton(
                    title: String(localized: "article.browser.open", defaultValue: "Browser"),
                    systemImage: "safari",
                    isActive: false
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func toggleSummary(for article: FeedArticle) {
        appLogger.logUI("Toggled summarize button for article \(article.id.uuidString.prefix(8))")
        if showingSummaryOutput, !isRunningSummary {
            withAnimation(.easeInOut(duration: 0.2)) {
                showingSummaryOutput = false
            }
        } else if article.aiSummary?.isEmpty == false {
            withAnimation(.easeInOut(duration: 0.2)) {
                showingSummaryOutput = true
            }
        } else {
            Task { await run(.summarize, for: article) }
        }
    }

    private func toggleTranslation(for article: FeedArticle) {
        appLogger.logUI("Toggled translate button for article \(article.id.uuidString.prefix(8))")
        if showingTranslationOutput, !isRunningTranslation {
            withAnimation(.easeInOut(duration: 0.2)) {
                showingTranslationOutput = false
            }
        } else if article.aiTranslation?.isEmpty == false {
            withAnimation(.easeInOut(duration: 0.2)) {
                showingTranslationOutput = true
            }
        } else {
            Task { await runTranslation(for: article) }
        }
    }

    private func forceRegenerateSummary(for article: FeedArticle) {
        guard !isRunningSummary else { return }
        appLogger.logUI("Force regenerating summary from long press for article \(article.id.uuidString.prefix(8))")
        showingSummaryOutput = true
        Task { await run(.summarize, for: article) }
    }

    private func forceRegenerateTranslation(for article: FeedArticle) {
        guard !isRunningTranslation else { return }
        appLogger.logUI("Force regenerating translation from long press for article \(article.id.uuidString.prefix(8))")
        showingTranslationOutput = true
        Task { await runTranslation(for: article) }
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

    private func articleBody(for article: FeedArticle) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            let activeTranslation = translatedBody(for: article)
            if shouldShowTranslation(for: article),
               let translation = activeTranslation {
                switch settingsStore.translationDisplayMode {
                case .translationOnly:
                    translatedContentView(translation, article: article)
                case .bilingual:
                    VStack(alignment: .leading, spacing: 18) {
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
                case .replaceOriginal:
                    translatedContentView(translation, article: article)
                        .padding(16)
                        .background(Color.buttonSurface.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            } else {
                MarkdownContentView(markdown: article.bodyText, hiddenImageURLs: hiddenImageSet(for: article))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func linkSection(for article: FeedArticle) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "article.source.title", defaultValue: "Source"))
                .font(.headline)
            Button(article.url) {
                if let url = URL(string: article.url) {
                    appLogger.logUI("Opened in-app browser for source link \(url.absoluteString)")
                    browserDestination = BrowserSheetDestination(url: url)
                }
            }
            .buttonStyle(.plain)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.buttonSurface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(Color.accentCinder)
        }
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
            let articleForRequest: FeedArticle
            if case .translate = action {
                await feedStore.ensureArticleContent(for: article.id)
                articleForRequest = feedStore.article(id: article.id) ?? article
            } else {
                articleForRequest = article
            }
            appLogger.log("Starting AI \(action.title) with provider \(provider.providerName) [\(provider.id.uuidString.prefix(8))] for article \(articleForRequest.id.uuidString.prefix(8))", category: .ai)
            let service = AIService(configuration: provider, logger: appLogger)
            let result = try await service.run(
                action: action,
                article: articleForRequest,
                outputLanguage: settingsStore.aiOutputLanguage
            )
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
            appLogger.log("AI \(action.title) failed: \(error.localizedDescription)", category: .ai)
        }
    }

    private func runTranslation(for article: FeedArticle) async {
        isRunningTranslation = true
        showingTranslationOutput = true
        streamingTranslationText = ""
        lastStreamRenderLength = 0
        defer {
            isRunningTranslation = false
        }
        do {
            guard let provider = settingsStore.defaultProvider else {
                throw AIServiceError.missingDefaultProvider
            }
            appLogger.log("Ensuring latest article body before streaming translation for article \(article.id.uuidString.prefix(8))", category: .ai)
            await feedStore.ensureArticleContent(for: article.id)
            let articleForRequest = feedStore.article(id: article.id) ?? article
            appLogger.log("Starting streaming AI translation with provider \(provider.providerName) [\(provider.id.uuidString.prefix(8))] for article \(articleForRequest.id.uuidString.prefix(8))", category: .ai)
            let service = AIService(configuration: provider, logger: appLogger)
            let result = try await service.streamTranslation(
                article: articleForRequest,
                outputLanguage: settingsStore.aiOutputLanguage
            ) { partial in
                let shouldRender = partial.count < 120
                    || partial.count - lastStreamRenderLength >= 120
                    || partial.hasSuffix("\n")
                    || partial.hasSuffix(")")
                guard shouldRender else { return }
                self.streamingTranslationText = partial
                self.lastStreamRenderLength = partial.count
            }
            feedStore.storeAIResult(translation: result, for: article.id)
            streamingTranslationText = ""
            lastStreamRenderLength = 0
            showingTranslationOutput = true
        } catch {
            showingTranslationOutput = false
            streamingTranslationText = ""
            lastStreamRenderLength = 0
            errorMessage = error.localizedDescription
            appLogger.log("AI translation failed: \(error.localizedDescription)", category: .ai)
        }
    }

    private func runAutomaticActionsIfNeeded(for articleID: FeedArticle.ID) async {
        guard settingsStore.autoSummaryEnabled || settingsStore.autoTranslationEnabled else {
            return
        }
        guard isViewActive else { return }
        guard let latestArticle = feedStore.article(id: articleID) else { return }
        guard settingsStore.defaultProvider != nil else {
            appLogger.logWarning("Skipped automatic AI actions because no default provider is configured")
            return
        }

        if settingsStore.autoSummaryEnabled,
           !isRunningSummary,
           latestArticle.aiSummary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            appLogger.log("Running automatic summary for article \(articleID.uuidString.prefix(8))", category: .ai)
            await run(.summarize, for: latestArticle)
        }

        guard let refreshedArticle = feedStore.article(id: articleID) else { return }
        if settingsStore.autoTranslationEnabled,
           !isRunningTranslation,
           refreshedArticle.aiTranslation?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            appLogger.log("Running automatic translation for article \(articleID.uuidString.prefix(8))", category: .ai)
            await run(.translate, for: refreshedArticle)
        }
    }

    private func contentSection(title: String, markdown: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.accentCinder)
            MarkdownContentView(markdown: markdown, hiddenImageURLs: article.map(hiddenImageSet(for:)) ?? [])
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
        MarkdownContentView(
            markdown: restoredTranslation,
            hiddenImageURLs: hiddenImages,
            isStreaming: isRunningTranslation
        )
    }

    private func hiddenImageSet(for article: FeedArticle) -> Set<String> {
        guard let imageURL = article.imageURL else { return [] }
        return [imageURL]
    }

    private func bodyContainsImage(_ imageURL: String, in markdown: String) -> Bool {
        let normalized = imageURL.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        return markdown.lowercased().contains(normalized)
    }
}
