import Foundation
import SwiftSoup

extension ArticleExtractor {
    static let imgOpenPlaceholder = "{{SAKURA_IMG_OPEN}}"
    static let imgClosePlaceholder = "{{SAKURA_IMG_CLOSE}}"
    static let brPlaceholder = "{{SAKURA_BR}}"
    static let linkOpenPlaceholder = "{{SAKURA_LINK_OPEN}}"
    static let linkMidPlaceholder = "{{SAKURA_LINK_MID}}"
    static let linkClosePlaceholder = "{{SAKURA_LINK_CLOSE}}"
    static let boldOpenPlaceholder = "{{SAKURA_BOLD_OPEN}}"
    static let boldClosePlaceholder = "{{SAKURA_BOLD_CLOSE}}"
    static let italicOpenPlaceholder = "{{SAKURA_ITALIC_OPEN}}"
    static let italicClosePlaceholder = "{{SAKURA_ITALIC_CLOSE}}"
    static let supOpenPlaceholder = "{{SAKURA_SUP_OPEN}}"
    static let supClosePlaceholder = "{{SAKURA_SUP_CLOSE}}"
    static let subOpenPlaceholder = "{{SAKURA_SUB_OPEN}}"
    static let subClosePlaceholder = "{{SAKURA_SUB_CLOSE}}"

    static func textContent(of element: Element) throws -> String {
        var html = try element.html()
        html = html.replacingOccurrences(of: "<br\\s*/?>", with: brPlaceholder, options: .regularExpression)
        html = replaceImgTags(in: html)
        html = replaceLinkTags(in: html)
        html = replaceFormattingTags(in: html)
        let fragment = try SwiftSoup.parseBodyFragment(html)
        var text = try fragment.body()?.text() ?? ""
        text = text.replacingOccurrences(of: brPlaceholder, with: "\n")
        text = escapeBracketsInLinkText(text, open: linkOpenPlaceholder, mid: linkMidPlaceholder)
        text = convertPlaceholdersToMarkdown(text)
        text = stripInvalidURLSupSub(text)
        text = stripRemainingHTMLTags(text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replaceImgTags(in html: String) -> String {
        guard let imgRegex = try? NSRegularExpression(
            pattern: "<img\\s[^>]*src=[\"']([^\"']+)[\"'][^>]*/?>",
            options: .caseInsensitive
        ) else {
            return html
        }
        var result = html
        let nsHTML = result as NSString
        let matches = imgRegex.matches(in: result, range: NSRange(location: 0, length: nsHTML.length))
        for match in matches.reversed() {
            let imageURL = nsHTML.substring(with: match.range(at: 1))
            let replacement = isLikelyContentImage(imageURL)
                ? "\(imgOpenPlaceholder)\(imageURL)\(imgClosePlaceholder)"
                : ""
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
        }
        return result
    }

    private static func replaceLinkTags(in html: String) -> String {
        var result = html
        result = result.replacingOccurrences(
            of: "<a\\s[^>]*href=[\"']([^\"']+)[\"'][^>]*>(.+?)</a>",
            with: "\(linkOpenPlaceholder)$2\(linkMidPlaceholder)$1\(linkClosePlaceholder)",
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: "<a\\s[^>]*>\\s*</a>", with: "", options: .regularExpression)
        return result
    }

    private static func replaceFormattingTags(in html: String) -> String {
        var result = html
        for tag in ["strong", "b"] {
            result = result.replacingOccurrences(
                of: "<\(tag)(?:\\s[^>]*)?>",
                with: boldOpenPlaceholder,
                options: [.regularExpression, .caseInsensitive]
            )
            result = result.replacingOccurrences(
                of: "</\(tag)>",
                with: boldClosePlaceholder,
                options: .caseInsensitive
            )
        }
        result = result.replacingOccurrences(
            of: "<em(?:\\s[^>]*)?>",
            with: italicOpenPlaceholder,
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(of: "</em>", with: italicClosePlaceholder, options: .caseInsensitive)
        result = result.replacingOccurrences(
            of: #"<i(?:\s[^>]*)?>"#,
            with: italicOpenPlaceholder,
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(of: "</i>", with: italicClosePlaceholder, options: .caseInsensitive)
        result = result.replacingOccurrences(
            of: "<sup(?:\\s[^>]*)?>",
            with: supOpenPlaceholder,
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(of: "</sup>", with: supClosePlaceholder, options: .caseInsensitive)
        result = result.replacingOccurrences(
            of: "<sub(?:\\s[^>]*)?>",
            with: subOpenPlaceholder,
            options: [.regularExpression, .caseInsensitive]
        )
        result = result.replacingOccurrences(of: "</sub>", with: subClosePlaceholder, options: .caseInsensitive)
        return result
    }

    private static func convertPlaceholdersToMarkdown(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: linkOpenPlaceholder, with: "[")
        result = result.replacingOccurrences(of: linkMidPlaceholder, with: "](")
        result = result.replacingOccurrences(of: linkClosePlaceholder, with: ")")
        result = result.replacingOccurrences(of: boldOpenPlaceholder, with: "**")
        result = result.replacingOccurrences(of: boldClosePlaceholder, with: "**")
        result = result.replacingOccurrences(of: italicOpenPlaceholder, with: "*")
        result = result.replacingOccurrences(of: italicClosePlaceholder, with: "*")
        result = result.replacingOccurrences(of: supOpenPlaceholder, with: "{{SUP}}")
        result = result.replacingOccurrences(of: supClosePlaceholder, with: "{{/SUP}}")
        result = result.replacingOccurrences(of: subOpenPlaceholder, with: "{{SUB}}")
        result = result.replacingOccurrences(of: subClosePlaceholder, with: "{{/SUB}}")
        result = convertImagePlaceholders(in: result)
        return result
    }

    private static func convertImagePlaceholders(in text: String) -> String {
        let pattern = NSRegularExpression.escapedPattern(for: imgOpenPlaceholder) + "(.*?)" + NSRegularExpression.escapedPattern(for: imgClosePlaceholder)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return text
        }

        var result = text
        let nsText = result as NSString
        let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsText.length))
        for match in matches.reversed() {
            let imageURL = nsText.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement = imageURL.isEmpty ? "" : "\n\n![](\(imageURL))\n\n"
            result = (result as NSString).replacingCharacters(in: match.range, with: replacement)
        }
        return result
    }

    static func isLikelyContentImage(_ url: String) -> Bool {
        let lowered = url.lowercased()
        let skipPatterns = [
            "gravatar.com", "pixel", "spacer", "blank",
            "1x1", "transparent", "tracking", "beacon",
            ".gif", "feeds.feedburner.com", "badge",
            "icon", "emoji", "smiley", "avatar",
            "ad.", "ads.", "doubleclick", "googlesyndication"
        ]
        for pattern in skipPatterns where lowered.contains(pattern) {
            return false
        }
        return true
    }

    static func stripInvalidURLSupSub(_ text: String) -> String {
        let pattern = #"\{\{(SUP|SUB)\}\}(.+?)\{\{/(SUP|SUB)\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        var result = text
        let nsText = result as NSString
        let matches = regex.matches(in: result, range: NSRange(location: 0, length: nsText.length))
        for match in matches.reversed() {
            let content = nsText.substring(with: match.range(at: 2))
            let linkPattern = #"\[([^\]]+)\]\(([^)]+)\)"#
            if let linkRegex = try? NSRegularExpression(pattern: linkPattern),
               let linkMatch = linkRegex.firstMatch(in: content, range: NSRange(location: 0, length: (content as NSString).length)) {
                let urlString = (content as NSString).substring(with: linkMatch.range(at: 2))
                if URL(string: urlString) == nil {
                    result = (result as NSString).replacingCharacters(in: match.range, with: "")
                }
            } else if content.hasPrefix("http://") || content.hasPrefix("https://") || content.hasPrefix("//") {
                if URL(string: content) == nil {
                    result = (result as NSString).replacingCharacters(in: match.range, with: "")
                }
            }
        }
        return result
    }

    static func escapeBracketsInLinkText(_ text: String, open: String, mid: String) -> String {
        var result = ""
        var remaining = text[text.startIndex...]
        while let openRange = remaining.range(of: open) {
            result += remaining[remaining.startIndex..<openRange.lowerBound]
            result += open
            let afterOpen = remaining[openRange.upperBound...]
            if let midRange = afterOpen.range(of: mid) {
                let linkText = afterOpen[afterOpen.startIndex..<midRange.lowerBound]
                result += linkText
                    .replacingOccurrences(of: "[", with: "\\[")
                    .replacingOccurrences(of: "]", with: "\\]")
                result += mid
                remaining = afterOpen[midRange.upperBound...]
            } else {
                remaining = afterOpen
            }
        }
        result += remaining
        return result
    }

    static func stripRemainingHTMLTags(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        result = result.replacingOccurrences(of: "&amp;", with: "&")
        result = result.replacingOccurrences(of: "&lt;", with: "<")
        result = result.replacingOccurrences(of: "&gt;", with: ">")
        result = result.replacingOccurrences(of: "&quot;", with: "\"")
        result = result.replacingOccurrences(of: "&#39;", with: "'")
        result = result.replacingOccurrences(of: "&apos;", with: "'")
        result = result.replacingOccurrences(of: "&nbsp;", with: " ")
        result = result.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func compactWhitespace(in paragraphs: [String]) -> [String] {
        let cleaned = paragraphs
            .map { compactWhitespace(in: $0) }
            .filter { !$0.isEmpty }
        return removeTrailingFeedCTAParagraphs(cleaned)
    }

    static func compactWhitespace(in text: String) -> String {
        var result = text
        result = result.replacingOccurrences(
            of: #"(?m)^[ \t]*(?:-{3,}|={3,}|_{3,}|\*{3,})[ \t]*$"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?m)^[ \t]*[\|\·•‣▪▫◦▶›»→・、,]+[ \t]*$"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?m)^[ \t]*(?:\*{1,3}|_{1,3})[ \t]*(?:\*{1,3}|_{1,3})?[ \t]*$"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let trailingFeedCTATexts: Set<String> = [
        "read full article",
        "read full story",
        "read the full article",
        "read the full story",
        "read the rest",
        "read the rest of this entry",
        "read the rest of this entry »",
        "read more",
        "read more...",
        "read more…",
        "read more »",
        "continue reading",
        "continue reading...",
        "continue reading…",
        "continue reading »",
        "view original",
        "view full article",
        "view on website",
        "view article",
        "see full article",
        "see more",
        "comments",
        "view comments",
        "view all comments",
        "leave a comment",
        "0 comments",
        "discuss on hacker news"
    ]

    static func removeTrailingFeedCTAParagraphs(_ paragraphs: [String]) -> [String] {
        var result = paragraphs
        while let last = result.last, isFeedCTAParagraph(last) {
            result.removeLast()
        }
        return result
    }

    private static func isFeedCTAParagraph(_ paragraph: String) -> Bool {
        let trimmed = paragraph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let pattern = #"^\[((?:[^\]\\]|\\.)+)\]\([^)\s]+\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let nsTrimmed = trimmed as NSString
        guard let match = regex.firstMatch(
            in: trimmed,
            range: NSRange(location: 0, length: nsTrimmed.length)
        ), match.numberOfRanges >= 2 else {
            return false
        }
        let linkText = nsTrimmed.substring(with: match.range(at: 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return trailingFeedCTATexts.contains(linkText)
    }
}
