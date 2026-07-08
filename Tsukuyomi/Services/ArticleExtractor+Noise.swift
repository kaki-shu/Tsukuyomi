import Foundation
import SwiftSoup

extension ArticleExtractor {
    static let noiseSelectors = [
        "nav", "header", "footer", "aside", ".sidebar", ".navigation", ".nav", ".navbar",
        ".menu", ".main-menu", ".site-menu", ".mobile-menu", ".dropdown-menu", ".breadcrumb",
        ".breadcrumbs", ".site-header", ".site-footer", ".page-header", ".page-footer",
        ".top-bar", ".bottom-bar", ".header-nav", ".footer-nav", ".skip-link",
        ".social-share", ".share-buttons", ".sharing", ".social-links", ".social-icons",
        ".share-bar", ".share-links", ".share-widget",
        ".related-posts", ".related-articles", ".related-content", ".related-stories",
        ".recommended", ".recommendations", ".suggested", ".suggested-posts",
        ".suggested-articles", ".more-stories", ".more-articles", ".more-from", ".read-next",
        ".read-more", ".up-next", ".also-read", ".trending", ".trending-posts",
        ".popular-posts", ".most-read", ".most-popular", ".top-stories", ".you-may-like",
        ".dont-miss", ".latest-posts", ".latest-articles", ".latest-stories", ".more-on",
        ".further-reading",
        ".comments", ".comment-section", ".comment-form", ".comment-list", ".comments-area",
        ".comments-section", ".disqus_thread", "#disqus_thread", "#comments", ".respond",
        ".comment-respond", ".discussion",
        ".advertisement", ".ad-container", ".ad", ".ads", ".ad-slot", ".ad-wrapper",
        ".ad-banner", ".ad-unit", ".adsbygoogle", ".sponsored", ".promoted", ".promo",
        ".promo-banner",
        ".cookie-banner", ".cookie-notice", ".cookie-consent", ".popup", ".modal", ".overlay",
        ".alert-banner", ".notification-bar", ".announcement-bar", ".paywall",
        ".paywall-prompt", ".gate", ".login-prompt", ".register-prompt",
        ".newsletter", ".subscribe", ".signup", ".newsletter-signup", ".email-signup",
        ".subscribe-form", ".cta", ".call-to-action",
        ".toolbar", ".pagination", ".pager", ".tags", ".tag-list", ".toc",
        ".table-of-contents", ".print-only", ".screen-reader-text", ".visually-hidden",
        ".author-bio", ".author-box", ".author-info", ".byline-section", ".bio", ".about-author",
        "[role=navigation]", "[role=banner]", "[role=complementary]", "[role=contentinfo]",
        "[aria-label*=menu]", "[aria-label*=Menu]", "[aria-label*=navigation]",
        "[aria-label*=Navigation]", "[aria-label*=comment]", "[aria-label*=Comment]",
        "[aria-label*=related]", "[aria-label*=Related]", "[aria-label*=share]",
        "[aria-label*=Share]", "[aria-label*=advertisement]", "[aria-label*=Advertisement]",
        "script", "style", "noscript", "iframe", "form", "button", "select", "input",
        "svg", "canvas", "template"
    ]

    private static let noiseClassPatterns = [
        "related", "recommend", "suggested", "popular", "trending", "sidebar", "widget",
        "promo", "newsletter", "subscribe", "comment", "disqus", "social-share",
        "share-bar", "ad-slot", "ad-wrap", "footer-links", "site-footer", "more-stories",
        "outbrain", "taboola", "also-like", "dont-miss", "read-next", "up-next", "most-read"
    ]

    static func removeNoise(from element: Element) {
        for selector in noiseSelectors {
            do {
                let elements = try element.select(selector)
                try elements.remove()
            } catch {
                continue
            }
        }

        removeNoiseByClassPatterns(from: element)
        removeMenuLists(from: element)
        removeSuggestionSections(from: element)
    }

    private static func removeNoiseByClassPatterns(from element: Element) {
        do {
            let elements = try element.select("div, section, aside, ul, ol")
            for element in elements {
                let className = (try? element.attr("class"))?.lowercased() ?? ""
                let idName = (try? element.attr("id"))?.lowercased() ?? ""
                let combined = className + " " + idName
                for pattern in noiseClassPatterns where combined.contains(pattern) {
                    try element.remove()
                    break
                }
            }
        } catch {}
    }

    private static func removeMenuLists(from element: Element) {
        do {
            let lists = try element.select("ul, ol")
            for list in lists {
                let links = try list.select("a")
                let items = try list.select("li")
                if items.size() > 2 && links.size() >= items.size() {
                    let totalText = try list.text()
                    let averageTextPerItem = totalText.count / max(items.size(), 1)
                    if averageTextPerItem < 50 {
                        try list.remove()
                    }
                }
            }
        } catch {}
    }

    private static func removeSuggestionSections(from element: Element) {
        let suggestionHeadingPatterns = [
            "related", "recommended", "suggested", "you may also", "you might also",
            "more from", "more stories", "more articles", "don't miss", "also read",
            "read next", "read more", "trending", "popular", "most read", "top stories",
            "further reading", "editors' picks", "editor's pick", "latest news",
            "what to read next", "up next", "around the web"
        ]

        do {
            let headings = try element.select("h2, h3, h4, h5, h6")
            for heading in headings {
                let text = (try? heading.text())?.lowercased() ?? ""
                let isSuggestionHeading = suggestionHeadingPatterns.contains { text.contains($0) }
                guard isSuggestionHeading else { continue }

                if let parent = heading.parent(),
                   parent.tagName().lowercased() != "body",
                   !["article", "main"].contains(parent.tagName().lowercased()) {
                    let parentLinks = (try? parent.select("a"))?.size() ?? 0
                    if parentLinks >= 2 {
                        try parent.remove()
                        continue
                    }
                }

                var sibling = try heading.nextElementSibling()
                try heading.remove()
                while let current = sibling {
                    let tag = current.tagName().lowercased()
                    if ["h1", "h2", "h3", "h4", "h5", "h6"].contains(tag) {
                        break
                    }
                    let next = try current.nextElementSibling()
                    try current.remove()
                    sibling = next
                }
            }
        } catch {}
    }
}
