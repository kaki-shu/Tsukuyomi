import SwiftUI

struct ArticleDestinationView: View {
    @Environment(FeedStore.self) private var feedStore

    let articleID: FeedArticle.ID

    var body: some View {
        Group {
            if let article = feedStore.article(id: articleID), article.isYouTubeArticle {
                YouTubeArticleView(articleID: articleID)
            } else {
                ArticleDetailView(articleID: articleID)
            }
        }
    }
}
