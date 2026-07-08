import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppLogger.self) private var appLogger
    @Environment(SettingsStore.self) private var settingsStore
    @State private var shareItem: SharedLogFile?

    var body: some View {
        List {
            Section(String(localized: "settings.section.ai", defaultValue: "AI")) {
                NavigationLink {
                    AIProvidersView()
                } label: {
                    LabeledContent(
                        String(localized: "settings.ai.providers", defaultValue: "AI Settings"),
                        value: settingsStore.defaultProvider?.providerName ?? String(localized: "settings.ai.none", defaultValue: "Not Set")
                    )
                }
                .listRowBackground(Color.clear)
            }

            Section(String(localized: "settings.section.integrations", defaultValue: "Integrations")) {
                NavigationLink {
                    YouTubeSettingsView()
                } label: {
                    LabeledContent(
                        String(localized: "settings.youtube.title", defaultValue: "YouTube"),
                        value: String(localized: "settings.youtube.value", defaultValue: "Player & Login")
                    )
                }
                .listRowBackground(Color.clear)
            }

            Section(String(localized: "settings.section.reading", defaultValue: "Reading")) {
                Picker(String(localized: "settings.font.title", defaultValue: "Title Font"), selection: Binding(
                    get: { settingsStore.titleFont },
                    set: { settingsStore.setTitleFont($0, logger: appLogger) }
                )) {
                    ForEach(ReadingFontChoice.allCases) { font in
                        Text(font.displayName).tag(font)
                    }
                }
                .listRowBackground(Color.clear)

                Picker(String(localized: "settings.font.body", defaultValue: "Body Font"), selection: Binding(
                    get: { settingsStore.bodyFont },
                    set: { settingsStore.setBodyFont($0, logger: appLogger) }
                )) {
                    ForEach(ReadingFontChoice.allCases) { font in
                        Text(font.displayName).tag(font)
                    }
                }
                .listRowBackground(Color.clear)
            }

            Section(String(localized: "settings.section.storage", defaultValue: "Local Data")) {
                LabeledContent(String(localized: "settings.storage.sources", defaultValue: "Sources"), value: "\(AppStorageSnapshot.sources)")
                    .listRowBackground(Color.clear)
                LabeledContent(String(localized: "settings.storage.articles", defaultValue: "Articles"), value: "\(AppStorageSnapshot.articles)")
                    .listRowBackground(Color.clear)
                LabeledContent(String(localized: "settings.storage.pages", defaultValue: "Clips"), value: "\(AppStorageSnapshot.pages)")
                    .listRowBackground(Color.clear)
            }

            Section(String(localized: "settings.section.capture", defaultValue: "Capture Scope")) {
                Text(String(localized: "settings.capture.body", defaultValue: "Tsukuyomi records app lifecycle, RSS refresh, storage events, AI requests, and basic network state. The log catcher refreshes whenever the app becomes active."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }

            Section(String(localized: "settings.section.logs", defaultValue: "Logs")) {
                Button(String(localized: "settings.logs.export", defaultValue: "Export Current Log")) {
                    if let exportURL = appLogger.exportCurrentLog() {
                        appLogger.logUI("Requested log export for \(exportURL.lastPathComponent)")
                        shareItem = SharedLogFile(url: exportURL)
                    }
                }
                .listRowBackground(Color.clear)
                Button(String(localized: "settings.logs.refresh", defaultValue: "Refresh Log Catcher")) {
                    appLogger.logUI("Requested manual log capture refresh")
                    appLogger.refreshCaptureSession()
                }
                .listRowBackground(Color.clear)
                Button(String(localized: "settings.logs.clear", defaultValue: "Clear Stored Logs"), role: .destructive) {
                    appLogger.logUI("Requested log clear")
                    appLogger.clearAllLogs()
                }
                .listRowBackground(Color.clear)
            }

            Section(String(localized: "settings.section.build", defaultValue: "Build")) {
                LabeledContent(String(localized: "settings.build.name", defaultValue: "Name"), value: "Tsukuyomi")
                    .listRowBackground(Color.clear)
                LabeledContent(String(localized: "settings.build.version", defaultValue: "Version"), value: AppBuild.version)
                    .listRowBackground(Color.clear)
                LabeledContent(String(localized: "settings.build.build", defaultValue: "Build"), value: AppBuild.build)
                    .listRowBackground(Color.clear)
                LabeledContent(String(localized: "settings.build.bundle", defaultValue: "Bundle"), value: AppBuild.bundleIdentifier)
                    .listRowBackground(Color.clear)
                NavigationLink {
                    OpenSourceReferencesView()
                } label: {
                    Text(String(localized: "settings.openSource.title", defaultValue: "Open Source"))
                }
                    .listRowBackground(Color.clear)
            }
        }
        .tsukuyomiListSurface()
        .navigationTitle(String(localized: "settings.title", defaultValue: "Settings"))
        .onAppear {
            appLogger.logUI("Displayed Settings view")
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
    }
}

private enum AppStorageSnapshot {
    static var sources: Int {
        loadPayload()?.sources.count ?? 0
    }

    static var articles: Int {
        loadPayload()?.articles.filter { $0.sourceKind == .rss }.count ?? 0
    }

    static var pages: Int {
        loadPayload()?.articles.filter { $0.sourceKind == .page }.count ?? 0
    }

    private static func loadPayload() -> FeedStoreSnapshotPayload? {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let url = root.appending(path: "Tsukuyomi/feed-store.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FeedStoreSnapshotPayload.self, from: data)
    }
}

private struct FeedStoreSnapshotPayload: Codable {
    var schemaVersion: Int?
    var savedAt: Date?
    var appVersion: String?
    var sources: [FeedSource]
    var articles: [FeedArticle]
}

struct SharedLogFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
