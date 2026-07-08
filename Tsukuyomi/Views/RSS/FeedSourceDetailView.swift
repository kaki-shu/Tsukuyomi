import SwiftUI

struct FeedSourceDetailView: View {
    @Environment(FeedStore.self) private var feedStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(AppLogger.self) private var appLogger
    let sourceID: FeedSource.ID

    var body: some View {
        ZStack {
            TsukuyomiBackdrop()
            ScrollView {
                if let source {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(source.title)
                                .font(.title2.weight(.bold))
                            Text(source.subtitle.isEmpty ? source.feedURL : source.subtitle)
                                .foregroundStyle(.secondary)
                            if let lastRefreshAt = source.lastRefreshAt {
                                Text("\(String(localized: "rss.source.lastRefresh", defaultValue: "Last refresh")): \(lastRefreshAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            Text(String(localized: "rss.source.articles", defaultValue: "Articles"))
                                .font(.system(size: 20, weight: .bold, design: .serif))
                            ForEach(sourceArticles) { article in
                                NavigationLink {
                                    ArticleDestinationView(articleID: article.id)
                                } label: {
                                    ArticleRow(article: article)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(TsukuyomiLayout.horizontalPadding)
                    .frame(maxWidth: TsukuyomiLayout.readableMaxWidth, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .navigationTitle(source?.title ?? String(localized: "rss.source.title", defaultValue: "Feed"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    appLogger.logUI("Refreshing source detail feed \(sourceID.uuidString.prefix(8))")
                    Task {
                        try? await feedStore.refresh(sourceID: sourceID)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task(id: sourceArticles.map(\.id)) {
            await feedStore.prefetchTitleTranslations(
                for: sourceArticles.map(\.id),
                settingsStore: settingsStore,
                logger: appLogger
            )
        }
    }

    private var source: FeedSource? {
        feedStore.sources.first(where: { $0.id == sourceID })
    }

    private var sourceArticles: [FeedArticle] {
        feedStore.recentArticles.filter { $0.feedID == sourceID }
    }
}
