import Foundation

final class RSSParser: NSObject, XMLParserDelegate, @unchecked Sendable {
    private var currentElement = ""
    private var currentTitle = ""
    private var currentLink = ""
    private var currentDescription = ""
    private var currentAuthor = ""
    private var currentContent = ""
    private var currentPubDate = ""
    private var currentImageURL = ""
    private var currentVideoURL = ""
    private var currentAudioURL = ""
    private var currentDuration = ""

    private var feedTitle = ""
    private var feedLink = ""
    private var feedDescription = ""

    private var parsedArticles: [ParsedArticle] = []
    private var isInsideItem = false
    private var isInsideImage = false
    private var isAtom = false

    func parse(data: Data) -> ParsedFeed? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        resetState()
        guard parser.parse() else { return nil }
        return ParsedFeed(
            title: decodeHTMLEntities(feedTitle.trimmingCharacters(in: .whitespacesAndNewlines)),
            siteURL: feedLink.trimmingCharacters(in: .whitespacesAndNewlines),
            description: cleanHTMLPreservingStructure(feedDescription.trimmingCharacters(in: .whitespacesAndNewlines)) ?? "",
            articles: parsedArticles
        )
    }

    private func resetState() {
        currentElement = ""
        currentTitle = ""
        currentLink = ""
        currentDescription = ""
        currentAuthor = ""
        currentContent = ""
        currentPubDate = ""
        currentImageURL = ""
        currentVideoURL = ""
        currentAudioURL = ""
        currentDuration = ""
        feedTitle = ""
        feedLink = ""
        feedDescription = ""
        parsedArticles = []
        isInsideItem = false
        isInsideImage = false
        isAtom = false
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName

        switch elementName {
        case "feed":
            isAtom = true
        case "image":
            if !isInsideItem { isInsideImage = true }
        case "item", "entry":
            isInsideItem = true
            resetItemState()
        case "link" where isAtom:
            let rel = attributeDict["rel"] ?? "alternate"
            guard let href = attributeDict["href"], rel == "alternate" else { break }
            if isInsideItem {
                currentLink = href
            } else {
                feedLink = href
            }
        case "enclosure", "media:content":
            if let url = attributeDict["url"], let type = attributeDict["type"], type.hasPrefix("image/") {
                currentImageURL = url
            } else if let url = attributeDict["url"], let type = attributeDict["type"], type.hasPrefix("video/") {
                currentVideoURL = url
            } else if let url = attributeDict["url"], let type = attributeDict["type"], type.hasPrefix("audio/") {
                currentAudioURL = url
            } else if let url = attributeDict["url"], attributeDict["medium"] == "image" {
                currentImageURL = url
            } else if let url = attributeDict["url"], attributeDict["medium"] == "video" {
                currentVideoURL = url
            }
        case "media:thumbnail":
            if let url = attributeDict["url"] {
                currentImageURL = url
            }
        case "itunes:image":
            if let url = attributeDict["href"], currentImageURL.isEmpty {
                currentImageURL = url
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if isInsideItem {
            switch currentElement {
            case "title":
                currentTitle += string
            case "link":
                if !isAtom { currentLink += string }
            case "description", "summary", "subtitle":
                currentDescription += string
            case "dc:creator", "author", "name":
                currentAuthor += string
            case "content:encoded", "content":
                currentContent += string
            case "pubDate", "published", "updated", "dc:date":
                currentPubDate += string
            case "itunes:duration":
                currentDuration += string
            default:
                break
            }
        } else {
            guard !isInsideImage else { return }
            switch currentElement {
            case "title":
                feedTitle += string
            case "link":
                if !isAtom { feedLink += string }
            case "description", "subtitle":
                feedDescription += string
            default:
                break
            }
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "image" {
            isInsideImage = false
        } else if elementName == "item" || elementName == "entry" {
            let article = ParsedArticle(
                title: decodeHTMLEntities(currentTitle.trimmingCharacters(in: .whitespacesAndNewlines)),
                url: currentLink.trimmingCharacters(in: .whitespacesAndNewlines),
                author: normalized(currentAuthor),
                summary: cleanHTMLPreservingStructure(currentDescription.trimmingCharacters(in: .whitespacesAndNewlines)),
                content: cleanHTMLPreservingStructure(currentContent.trimmingCharacters(in: .whitespacesAndNewlines)),
                imageURL: resolveImageURL(),
                videoURL: normalized(currentVideoURL),
                publishedDate: parseDate(currentPubDate.trimmingCharacters(in: .whitespacesAndNewlines)),
                audioURL: normalized(currentAudioURL),
                duration: parseDuration(currentDuration.trimmingCharacters(in: .whitespacesAndNewlines))
            )
            if !article.title.isEmpty && !article.url.isEmpty {
                parsedArticles.append(article)
            }
            isInsideItem = false
        }
        currentElement = ""
    }

    private func resetItemState() {
        currentTitle = ""
        currentLink = ""
        currentDescription = ""
        currentAuthor = ""
        currentContent = ""
        currentPubDate = ""
        currentImageURL = ""
        currentVideoURL = ""
        currentAudioURL = ""
        currentDuration = ""
    }

    private func resolveImageURL() -> String? {
        if !currentImageURL.isEmpty {
            return currentImageURL
        }
        if let contentURL = extractImageFromHTML(currentContent) {
            return contentURL
        }
        return extractImageFromHTML(currentDescription)
    }

    private func normalized(_ string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : decodeHTMLEntities(trimmed)
    }
}
