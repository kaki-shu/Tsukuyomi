import Foundation

enum ClipExportService {
    static func export(
        articles: [FeedArticle],
        progress: @escaping @MainActor (Double) -> Void
    ) async throws -> URL {
        let timestamp = ExportDateFormatters.fileTimestamp.string(from: .now)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Tsukuyomi-Clips-\(timestamp)")
            .appendingPathExtension("zip")

        var entries: [ZipArchiveEntry] = []
        let total = max(articles.count, 1)
        for (index, article) in articles.enumerated() {
            let date = article.publishedDate ?? article.updatedAt
            let fileName = "\(article.title.safeFileName)-\(ExportDateFormatters.fileTimestamp.string(from: date)).md"
            let markdown = markdownDocument(for: article, originalDate: date)
            entries.append(ZipArchiveEntry(
                fileName: fileName,
                data: Data(markdown.utf8),
                modifiedAt: date
            ))
            await progress(Double(index + 1) / Double(total))
            if index.isMultiple(of: 5) {
                await Task.yield()
            }
        }

        try ZipArchiveWriter.write(entries: entries, to: url)
        await progress(1)
        return url
    }

    private static func markdownDocument(for article: FeedArticle, originalDate: Date) -> String {
        let published = ExportDateFormatters.iso8601.string(from: originalDate)
        let authorLine = article.author?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? "\n- Author: \(article.author ?? "")"
            : ""
        let body = article.bodyText.trimmingCharacters(in: .whitespacesAndNewlines)

        return """
        # \(article.title)

        - Source: \(article.feedTitle)
        - URL: \(article.url)
        - Original Published Time: \(published)\(authorLine)

        \(body)
        """
    }
}

enum ExportDateFormatters {
    static let fileTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter
    }()

    static let iso8601 = ISO8601DateFormatter()
}

private extension String {
    var safeFileName: String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:\n\r\t")
        let components = components(separatedBy: invalid)
        let joined = components.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = joined.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
        return String(collapsed.prefix(80)).nilIfBlank ?? "Untitled"
    }

    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
