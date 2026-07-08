import SwiftUI
import UIKit

struct AddFeedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FeedStore.self) private var feedStore
    @Environment(AppLogger.self) private var appLogger
    @State private var feedURLs = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var failedImports: [ImportFailure] = []
    @State private var importedCount = 0

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "rss.add.section.url", defaultValue: "Feed URL")) {
                    ZStack(alignment: .topLeading) {
                        if feedURLs.isEmpty {
                            Text("https://example.com/feed.xml\nhttps://example.com/feed-2.xml")
                                .foregroundStyle(Color.placeholderText)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }
                        TextEditor(text: $feedURLs)
                            .frame(minHeight: 128)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Text(String(localized: "rss.add.http.note", defaultValue: "Both http and https RSS sources are supported."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if importedCount > 0 {
                        Text(String(format: String(localized: "import.success.count", defaultValue: "%d links imported."), importedCount))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if !failedImports.isEmpty {
                    Section(String(localized: "import.failed.section", defaultValue: "Failed Imports")) {
                        ForEach(failedImports) { failure in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(failure.url)
                                Text(failure.message)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button(String(localized: "import.failed.copy", defaultValue: "Copy Failed Links")) {
                            UIPasteboard.general.string = failedImports.map(\.url).joined(separator: "\n")
                        }
                        Button(String(localized: "import.failed.retry", defaultValue: "Retry Failed Links")) {
                            feedURLs = failedImports.map(\.url).joined(separator: "\n")
                            failedImports = []
                            importedCount = 0
                        }
                    }
                }

                Section(String(localized: "rss.add.section.recommended", defaultValue: "Recommended")) {
                    ForEach(FeedSuggestion.samples, id: \.url) { sample in
                        Button {
                            appLogger.logUI("Selected recommended feed \(sample.url)")
                            feedURLs = appendURL(sample.url, to: feedURLs)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(sample.title)
                                Text(sample.url)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "rss.add.title", defaultValue: "Add Feed"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "action.close", defaultValue: "Close")) {
                        appLogger.logUI("Closed add feed sheet")
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "action.save", defaultValue: "Save")) {
                        appLogger.logUI("Submitted add feed sheet for \(parsedURLs.count) URL(s)")
                        Task { await submit() }
                    }
                    .disabled(parsedURLs.isEmpty || isSubmitting)
                }
            }
        }
    }

    private func submit() async {
        errorMessage = nil
        failedImports = []
        importedCount = 0
        isSubmitting = true
        defer { isSubmitting = false }
        for url in parsedURLs {
            do {
                try await feedStore.addFeed(urlString: url)
                importedCount += 1
            } catch {
                failedImports.append(ImportFailure(url: url, message: error.localizedDescription))
                appLogger.log("Feed import failed for \(url): \(error.localizedDescription)", category: .rss)
            }
        }

        if failedImports.isEmpty, importedCount > 0 {
            appLogger.log("Feed sheet completed successfully", category: .rss)
            dismiss()
        } else if importedCount == 0, let firstFailure = failedImports.first {
            errorMessage = firstFailure.message
        } else if !failedImports.isEmpty {
            errorMessage = String(format: String(localized: "import.failed.summary", defaultValue: "%d links failed to import."), failedImports.count)
        }
    }

    private var parsedURLs: [String] {
        feedURLs
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func appendURL(_ url: String, to existing: String) -> String {
        let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? url : "\(trimmed)\n\(url)"
    }
}

private struct ImportFailure: Identifiable {
    let id = UUID()
    let url: String
    let message: String
}

private struct FeedSuggestion {
    let title: String
    let url: String

    static let samples = [
        FeedSuggestion(title: "OpenAI News", url: "https://openai.com/news/rss.xml"),
        FeedSuggestion(title: "The Verge", url: "https://www.theverge.com/rss/index.xml"),
        FeedSuggestion(title: "O'Reilly Radar", url: "https://feeds.feedburner.com/oreilly/radar")
    ]
}
