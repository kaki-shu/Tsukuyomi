import SwiftUI

struct RSSDashboardView: View {
    @Environment(FeedStore.self) private var feedStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(AppLogger.self) private var appLogger
    @State private var showingAddFeed = false

    var body: some View {
        ZStack {
            TsukuyomiBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    recentSection
                }
                .padding(TsukuyomiLayout.horizontalPadding)
                .frame(maxWidth: TsukuyomiLayout.readableMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .navigationTitle("Tsukuyomi")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    appLogger.logUI("Tapped refresh all feeds from RSS dashboard")
                    Task { await feedStore.forceRefreshAll(settingsStore: settingsStore, logger: appLogger) }
                } label: {
                    if feedStore.isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }

                Button {
                    appLogger.logUI("Opened add feed sheet from RSS dashboard")
                    showingAddFeed = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddFeed) {
            AddFeedSheet()
        }
        .onAppear {
            appLogger.logUI("Displayed RSS dashboard with \(feedStore.recentArticles.count) items")
        }
        .task(id: feedStore.recentArticles.map(\.id)) {
            await feedStore.prefetchTitleTranslations(
                for: Array(feedStore.recentArticles.prefix(30)).map(\.id),
                settingsStore: settingsStore,
                logger: appLogger
            )
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(String(localized: "rss.latest.title", defaultValue: "Latest"))
            if feedStore.recentArticles.isEmpty {
                EmptyStateCard(
                    title: String(localized: "rss.empty.title", defaultValue: "No articles yet"),
                    message: String(localized: "rss.empty.message", defaultValue: "Add an RSS source to start reading.")
                )
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(feedStore.recentArticles) { article in
                        NavigationLink {
                            ArticleDestinationView(articleID: article.id)
                        } label: {
                            ArticleRow(article: article)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 20, weight: .bold, design: .serif))
            .foregroundStyle(Color.primaryText)
    }
}
