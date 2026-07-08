import SwiftUI

struct MarkdownContentView: View {
    let markdown: String
    var hiddenImageURLs: Set<String> = []
    var isStreaming = false

    private var blocks: [MarkdownBlock] {
        MarkdownBlock.parse(markdown, hiddenImageURLs: hiddenImageURLs)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(blocks) { block in
                switch block.kind {
                case .text(let value):
                    MarkdownTextBlock(markdown: value, isStreaming: isStreaming)
                case .image(let urlString):
                    MarkdownImageBlock(urlString: urlString)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MarkdownTextBlock: View {
    @Environment(SettingsStore.self) private var settingsStore
    let markdown: String
    let isStreaming: Bool

    private var normalizedMarkdown: String {
        MarkdownTextNormalizer.normalize(markdown)
    }

    var body: some View {
        Group {
            if let attributed = try? AttributedString(
                markdown: processedMarkdown,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .full)
            ) {
                Text(attributed)
            } else {
                Text(processedMarkdown)
            }
        }
        .font(settingsStore.bodyFont.font(size: 17))
        .foregroundStyle(Color.primaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lineLimit(nil)
        .lineSpacing(isStreaming ? 7 : 8)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .tint(Color.accentCinder)
        .textSelection(.enabled)
    }

    private var processedMarkdown: String {
        let normalized = normalizedMarkdown
        let lines = normalized.components(separatedBy: "\n")
        guard !lines.isEmpty else { return normalized }

        return lines.enumerated().map { index, line in
            guard index < lines.count - 1 else { return line }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty
                || trimmed.hasPrefix("#")
                || trimmed.hasPrefix("- ")
                || trimmed.hasPrefix("* ")
                || trimmed.hasPrefix("> ")
                || trimmed.hasPrefix(">") {
                return line
            }

            return "\(line)  "
        }
        .joined(separator: "\n")
    }
}

private enum MarkdownTextNormalizer {
    static func normalize(_ markdown: String) -> String {
        markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "{{SUP}}", with: "^(")
            .replacingOccurrences(of: "{{/SUP}}", with: ")")
            .replacingOccurrences(of: "{{SUB}}", with: "(")
            .replacingOccurrences(of: "{{/SUB}}", with: ")")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct MarkdownImageBlock: View {
    let urlString: String

    var body: some View {
        if let url = URL(string: urlString) {
            CachedRemoteImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFit()
            } placeholder: {
                imagePlaceholder
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private var imagePlaceholder: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Color.buttonSurface)
            .frame(maxWidth: .infinity)
            .frame(height: 180)
            .overlay {
                ProgressView()
                    .tint(Color.accentCinder)
            }
    }
}

private struct MarkdownBlock: Identifiable {
    enum Kind {
        case text(String)
        case image(String)
    }

    let id = UUID()
    let kind: Kind

    static func parse(_ markdown: String, hiddenImageURLs: Set<String>) -> [MarkdownBlock] {
        let pattern = #"\{\{IMG\}\}(.*?)\{\{/IMG\}\}|!\[[^\]]*\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return textBlocks(from: markdown)
        }

        let nsText = markdown as NSString
        let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else {
            return textBlocks(from: markdown)
        }

        var blocks: [MarkdownBlock] = []
        var seenImageKeys = Set(hiddenImageURLs.map(normalizedImageKey))
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                let text = nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
                blocks.append(contentsOf: textBlocks(from: text))
            }
            let url = imageURL(from: match, in: nsText)
            if let url, !url.isEmpty {
                let key = normalizedImageKey(url)
                guard !seenImageKeys.contains(key) else {
                    cursor = match.range.location + match.range.length
                    continue
                }
                seenImageKeys.insert(key)
                blocks.append(MarkdownBlock(kind: .image(url)))
            }
            cursor = match.range.location + match.range.length
        }

        if cursor < nsText.length {
            let tail = nsText.substring(with: NSRange(location: cursor, length: nsText.length - cursor))
            blocks.append(contentsOf: textBlocks(from: tail))
        }

        return blocks.isEmpty ? textBlocks(from: markdown) : blocks
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

    private static func textBlocks(from markdown: String) -> [MarkdownBlock] {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let paragraphs = trimmed
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .components(separatedBy: "\n\n")
        return paragraphs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { MarkdownBlock(kind: .text($0)) }
    }

    private static func normalizedImageKey(_ url: String) -> String {
        url.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            .lowercased()
    }
}
