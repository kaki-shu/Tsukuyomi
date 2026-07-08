import Foundation
import SwiftSoup

struct ArticleExtractor {
    static let contentSelectors = [
        "article",
        "[role=main]",
        "main",
        ".post-content",
        ".entry-content",
        ".article-body",
        ".article-content",
        ".post-body",
        ".story-body",
        ".content-body",
        "#article-body",
        "#content",
        ".post",
        ".entry"
    ]

    static let blockElements = [
        "p", "h1", "h2", "h3", "h4", "h5", "h6",
        "blockquote", "li", "figcaption", "pre", "td", "th"
    ]

    static func extractText(fromHTML html: String, excludeTitle: String? = nil) -> String? {
        guard !html.isEmpty else { return nil }
        do {
            let document = try SwiftSoup.parse(html)
            removeNoise(from: document)
            let mainContent = try findMainContent(from: document)
            removeNoise(from: mainContent)
            let paragraphs = try extractParagraphs(from: mainContent, excludeTitle: excludeTitle)
            let result = paragraphs.joined(separator: "\n\n")
            let cleaned = stripRemainingHTMLTags(result)
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            return nil
        }
    }

    static func findMainContent(from document: Document) throws -> Element {
        for selector in contentSelectors {
            let elements = try document.select(selector)
            if let element = elements.first() {
                let text = try element.text()
                if text.count > 100 {
                    return element
                }
            }
        }
        return document.body() ?? document
    }

    static func extractParagraphs(from element: Element, excludeTitle: String? = nil) throws -> [String] {
        var paragraphs: [String] = []
        try collectBlocks(from: element, into: &paragraphs, excludeTitle: excludeTitle)

        if paragraphs.isEmpty {
            let text = try textContent(of: element)
            return text.isEmpty ? [] : compactWhitespace(in: [text])
        }

        return compactWhitespace(in: paragraphs)
    }

    private static func collectBlocks(from element: Element, into paragraphs: inout [String], excludeTitle: String?) throws {
        for child in element.children() {
            let tag = child.tagName().lowercased()
            if tag == "img" {
                if let src = try? child.attr("src"), !src.isEmpty, isLikelyContentImage(src) {
                    paragraphs.append("{{IMG}}\(src){{/IMG}}")
                }
            } else if tag == "picture" {
                if let image = try? child.select("img").first(),
                   let src = try? image.attr("src"),
                   !src.isEmpty,
                   isLikelyContentImage(src) {
                    paragraphs.append("{{IMG}}\(src){{/IMG}}")
                }
            } else if tag == "figure" {
                if let image = try? child.select("img").first(),
                   let src = try? image.attr("src"),
                   !src.isEmpty,
                   isLikelyContentImage(src) {
                    paragraphs.append("{{IMG}}\(src){{/IMG}}")
                }
                if let caption = try? child.select("figcaption").first() {
                    let captionText = try textContent(of: caption)
                    if !captionText.isEmpty {
                        paragraphs.append("*\(captionText)*")
                    }
                }
            } else if blockElements.contains(tag) || isLeafBlock(child) {
                var text = try textContent(of: child)
                if !text.isEmpty {
                    let headingTags = ["h1", "h2", "h3", "h4", "h5", "h6"]
                    if headingTags.contains(tag),
                       let excludeTitle,
                       text.caseInsensitiveCompare(excludeTitle) == .orderedSame {
                        continue
                    }
                    switch tag {
                    case "h1":
                        text = "# \(text)"
                    case "h2":
                        text = "## \(text)"
                    case "h3":
                        text = "### \(text)"
                    case "h4", "h5", "h6":
                        text = "**\(text)**"
                    default:
                        break
                    }
                    paragraphs.append(text)
                }
            } else {
                try collectBlocks(from: child, into: &paragraphs, excludeTitle: excludeTitle)
            }
        }
    }

    private static func isLeafBlock(_ element: Element) -> Bool {
        let structuralTags: Set<String> = ["div", "section", "article", "main", "aside"]
        for child in element.children() {
            let tag = child.tagName().lowercased()
            if blockElements.contains(tag) || structuralTags.contains(tag) {
                return false
            }
        }
        let text = (try? element.text()) ?? ""
        return !text.isEmpty
    }
}
