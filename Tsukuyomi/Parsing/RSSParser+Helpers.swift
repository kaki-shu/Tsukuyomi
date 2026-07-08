import Foundation

private let htmlNamedEntities: [String: String] = [
    "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
    "nbsp": "\u{00A0}", "ndash": "\u{2013}", "mdash": "\u{2014}",
    "lsquo": "\u{2018}", "rsquo": "\u{2019}", "ldquo": "\u{201C}",
    "rdquo": "\u{201D}", "hellip": "\u{2026}", "copy": "\u{00A9}",
    "trade": "\u{2122}", "euro": "\u{20AC}"
]

extension RSSParser {
    func decodeHTMLEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }
        var result = ""
        var index = string.startIndex
        while index < string.endIndex {
            if string[index] == "&",
               let semiIndex = string[index...].firstIndex(of: ";"),
               semiIndex > string.index(after: index) {
                let entity = String(string[string.index(after: index)..<semiIndex])
                if let decoded = decodeEntity(entity) {
                    result.append(decoded)
                    index = string.index(after: semiIndex)
                    continue
                }
            }
            result.append(string[index])
            index = string.index(after: index)
        }
        return result
    }

    private func decodeEntity(_ entity: String) -> String? {
        if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
            let hex = String(entity.dropFirst(2))
            if let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) {
                return String(Character(scalar))
            }
        } else if entity.hasPrefix("#") {
            let decimal = String(entity.dropFirst())
            if let code = UInt32(decimal), let scalar = Unicode.Scalar(code) {
                return String(Character(scalar))
            }
        } else if let replacement = htmlNamedEntities[entity] {
            return replacement
        }
        return nil
    }

    func cleanHTMLPreservingStructure(_ html: String) -> String? {
        guard !html.isEmpty else { return nil }
        guard html.contains("<") else {
            let text = decodeHTMLEntities(html).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        if let extracted = ArticleExtractor.extractText(fromHTML: html, excludeTitle: nil),
           !extracted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return extracted
        }
        var result = html
        result = result.replacingOccurrences(of: #"<br\s*/?>"#, with: "\n", options: .regularExpression)
        result = result.replacingOccurrences(of: #"</p>|</div>|</li>|</h1>|</h2>|</h3>"#, with: "\n", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: #"<a\s[^>]*href=["']([^"']+)["'][^>]*>(.*?)</a>"#, with: "$2 ($1)", options: [.regularExpression, .caseInsensitive])
        result = result.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        result = decodeHTMLEntities(result)
        result = result.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func extractImageFromHTML(_ html: String) -> String? {
        let patterns = [#"<img[^>]+src="([^"]+)""#, #"<img[^>]+src='([^']+)'"#]
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: (html as NSString).length)),
               let range = Range(match.range(at: 1), in: html) {
                return String(html[range])
            }
        }
        return nil
    }

    func parseDuration(_ string: String) -> Int? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let components = trimmed.split(separator: ":").compactMap { Int($0) }
        switch components.count {
        case 1: return components[0]
        case 2: return components[0] * 60 + components[1]
        case 3: return components[0] * 3600 + components[1] * 60 + components[2]
        default: return nil
        }
    }

    func parseDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for formatter in Self.dateFormatters {
            if let value = formatter.date(from: trimmed) {
                return value
            }
        }
        return Self.iso8601WithFractional.date(from: trimmed) ?? Self.iso8601.date(from: trimmed)
    }

    private static let dateFormatters: [DateFormatter] = {
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        ]
        return formats.map {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = $0
            return formatter
        }
    }()

    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
