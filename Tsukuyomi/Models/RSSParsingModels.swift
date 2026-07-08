import Foundation

struct ParsedFeed: Sendable {
    var title: String
    var siteURL: String
    var description: String
    var articles: [ParsedArticle]
}

struct ParsedArticle: Sendable {
    var title: String
    var url: String
    var author: String?
    var summary: String?
    var content: String?
    var imageURL: String?
    var videoURL: String?
    var publishedDate: Date?
    var audioURL: String?
    var duration: Int?
}
