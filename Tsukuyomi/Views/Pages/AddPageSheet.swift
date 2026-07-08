import SwiftUI
import UIKit

struct AddPageSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FeedStore.self) private var feedStore
    @Environment(AppLogger.self) private var appLogger

    @State private var pageURLs = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var failedImports: [PageImportFailure] = []
    @State private var importedCount = 0

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "pages.add.section.url", defaultValue: "Web Page URL")) {
                    ZStack(alignment: .topLeading) {
                        if pageURLs.isEmpty {
                            Text("https://example.com/article\nhttps://example.com/video")
                                .foregroundStyle(Color.placeholderText)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                        }
                        TextEditor(text: $pageURLs)
                            .frame(minHeight: 128)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
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
                            pageURLs = failedImports.map(\.url).joined(separator: "\n")
                            failedImports = []
                            importedCount = 0
                        }
                    }
                }
            }
            .navigationTitle(String(localized: "pages.add.title", defaultValue: "Add Clip"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "action.close", defaultValue: "Close")) {
                        appLogger.logUI("Closed add page sheet")
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "action.save", defaultValue: "Save")) {
                        appLogger.logUI("Submitted add page sheet for \(parsedURLs.count) URL(s)")
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
                try await feedStore.addPage(urlString: url)
                importedCount += 1
            } catch {
                failedImports.append(PageImportFailure(url: url, message: error.localizedDescription))
                appLogger.log("Failed to save page \(url): \(error.localizedDescription)", category: .rss)
            }
        }
        if failedImports.isEmpty, importedCount > 0 {
            appLogger.log("Saved page from Pages sheet", category: .rss)
            dismiss()
        } else if importedCount == 0, let firstFailure = failedImports.first {
            errorMessage = firstFailure.message
        } else if !failedImports.isEmpty {
            errorMessage = String(format: String(localized: "import.failed.summary", defaultValue: "%d links failed to import."), failedImports.count)
        }
    }

    private var parsedURLs: [String] {
        pageURLs
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct PageImportFailure: Identifiable {
    let id = UUID()
    let url: String
    let message: String
}
