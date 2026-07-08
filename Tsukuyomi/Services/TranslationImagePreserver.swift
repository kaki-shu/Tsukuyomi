import Foundation

struct TranslationImagePreserver {
    struct ProtectedMarkdown {
        let markdown: String
        let tokenToImageURL: [String: String]
    }

    static func protect(_ markdown: String) -> ProtectedMarkdown {
        let images = imageReferences(in: markdown)
        guard !images.isEmpty else {
            return ProtectedMarkdown(markdown: markdown, tokenToImageURL: [:])
        }

        var protectedMarkdown = markdown
        var tokenToImageURL: [String: String] = [:]
        for (index, image) in images.enumerated().reversed() {
            let token = "{{TSUKUYOMI_IMAGE_\(index + 1)}}"
            tokenToImageURL[token] = image.urlString
            protectedMarkdown = (protectedMarkdown as NSString).replacingCharacters(in: image.range, with: "\n\n\(token)\n\n")
        }
        return ProtectedMarkdown(markdown: protectedMarkdown, tokenToImageURL: tokenToImageURL)
    }

    static func restoreImages(in translation: String, from protectedMarkdown: ProtectedMarkdown) -> String {
        guard !protectedMarkdown.tokenToImageURL.isEmpty else { return translation }
        var result = translation
        for (token, imageURL) in protectedMarkdown.tokenToImageURL {
            result = result.replacingOccurrences(of: token, with: "\n\n![](\(imageURL))\n\n")
        }
        return result
    }

    static func mergeMissingImages(
        into translation: String,
        originalMarkdown: String,
        hiddenImageURLs: Set<String> = []
    ) -> String {
        let originalImages = imageReferences(in: originalMarkdown).map(\.urlString)
        let hidden = Set(hiddenImageURLs.map(normalizedImageKey))
        guard !originalImages.isEmpty else {
            return stripImageTokens(from: translation).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var merged = restoreOrTrim(
            restoreImageTokens(
                in: translation,
                originalImages: originalImages,
                hiddenImageURLs: hidden
            )
        )
        var seen = Set(imageReferences(in: merged).map { normalizedImageKey($0.urlString) })

        var missingImages: [String] = []
        for imageURL in originalImages {
            let key = normalizedImageKey(imageURL)
            guard !seen.contains(key), !hidden.contains(key) else { continue }
            seen.insert(key)
            missingImages.append(imageURL)
        }

        guard !missingImages.isEmpty else { return merged }
        let restoredImages = missingImages.map { "![](\($0))" }.joined(separator: "\n\n")
        if merged.isEmpty {
            return restoredImages
        }
        merged += "\n\n\(restoredImages)"
        return merged
    }

    private static func restoreOrTrim(_ markdown: String) -> String {
        markdown.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func restoreImageTokens(
        in markdown: String,
        originalImages: [String],
        hiddenImageURLs: Set<String>
    ) -> String {
        let pattern = #"\{\{TSUKUYOMI_IMAGE_(\d+)\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return markdown
        }

        let nsText = markdown as NSString
        var restored = markdown
        for match in regex.matches(in: markdown, range: NSRange(location: 0, length: nsText.length)).reversed() {
            let indexRange = match.range(at: 1)
            guard indexRange.location != NSNotFound,
                  let imageNumber = Int(nsText.substring(with: indexRange)),
                  originalImages.indices.contains(imageNumber - 1) else {
                restored = (restored as NSString).replacingCharacters(in: match.range, with: "")
                continue
            }

            let imageURL = originalImages[imageNumber - 1]
            let replacement = hiddenImageURLs.contains(normalizedImageKey(imageURL))
                ? ""
                : "\n\n![](\(imageURL))\n\n"
            restored = (restored as NSString).replacingCharacters(in: match.range, with: replacement)
        }
        return restored
    }

    private static func stripImageTokens(from markdown: String) -> String {
        let pattern = #"\{\{TSUKUYOMI_IMAGE_\d+\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return markdown
        }
        return regex.stringByReplacingMatches(
            in: markdown,
            range: NSRange(location: 0, length: (markdown as NSString).length),
            withTemplate: ""
        )
    }

    private struct ImageReference {
        let urlString: String
        let range: NSRange
    }

    private static func imageReferences(in markdown: String) -> [ImageReference] {
        let pattern = #"\{\{IMG\}\}(.*?)\{\{/IMG\}\}|!\[[^\]]*\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return []
        }

        let nsText = markdown as NSString
        return regex.matches(in: markdown, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            guard let url = imageURL(from: match, in: nsText), !url.isEmpty else { return nil }
            return ImageReference(urlString: url, range: match.range)
        }
    }

    private static func imageURL(from match: NSTextCheckingResult, in text: NSString) -> String? {
        for index in 1..<match.numberOfRanges {
            let range = match.range(at: index)
            guard range.location != NSNotFound else { continue }
            return text.substring(with: range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        }
        return nil
    }

    private static func normalizedImageKey(_ url: String) -> String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            .lowercased()
    }
}
