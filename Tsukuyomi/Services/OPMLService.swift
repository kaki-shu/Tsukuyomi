import Foundation

struct OPMLFeedEntry: Hashable {
    var title: String
    var xmlURL: String
    var htmlURL: String?
}

enum OPMLService {
    static func export(sources: [FeedSource]) throws -> URL {
        let timestamp = ExportDateFormatters.fileTimestamp.string(from: .now)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Tsukuyomi-Sources-\(timestamp)")
            .appendingPathExtension("opml")

        let outlines = sources.map { source in
            """
                <outline text="\(source.title.xmlEscaped)" title="\(source.title.xmlEscaped)" type="rss" xmlUrl="\(source.feedURL.xmlEscaped)" htmlUrl="\(source.siteURL.xmlEscaped)" />
            """
        }.joined(separator: "\n")

        let document = """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
          <head>
            <title>Tsukuyomi Sources</title>
            <dateCreated>\(ISO8601DateFormatter().string(from: .now))</dateCreated>
          </head>
          <body>
        \(outlines)
          </body>
        </opml>
        """

        try document.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    static func parse(data: Data) throws -> [OPMLFeedEntry] {
        let parser = XMLParser(data: data)
        let delegate = OPMLParserDelegate()
        parser.delegate = delegate
        guard parser.parse() else {
            throw parser.parserError ?? URLError(.cannotParseResponse)
        }
        return delegate.entries.uniquedByNormalizedURL()
    }
}

private final class OPMLParserDelegate: NSObject, XMLParserDelegate {
    private(set) var entries: [OPMLFeedEntry] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName.lowercased() == "outline" else { return }
        let xmlURL = attributeDict["xmlUrl"] ?? attributeDict["xmlURL"] ?? attributeDict["xmlurl"]
        guard let xmlURL, !xmlURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let title = attributeDict["title"] ?? attributeDict["text"] ?? xmlURL
        let htmlURL = attributeDict["htmlUrl"] ?? attributeDict["htmlURL"] ?? attributeDict["htmlurl"]
        entries.append(OPMLFeedEntry(
            title: title,
            xmlURL: xmlURL.trimmingCharacters(in: .whitespacesAndNewlines),
            htmlURL: htmlURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
    }
}

private extension Array where Element == OPMLFeedEntry {
    func uniquedByNormalizedURL() -> [OPMLFeedEntry] {
        var seen = Set<String>()
        return filter { entry in
            let key = entry.xmlURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return seen.insert(key).inserted
        }
    }
}

private extension String {
    var xmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
