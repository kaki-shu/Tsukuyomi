import SwiftUI
import UniformTypeIdentifiers

private enum SourceSortMode: String, CaseIterable, Identifiable {
    case manual
    case name
    case recentRefresh
    case articleCount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual:
            return String(localized: "rss.sources.sort.manual", defaultValue: "Added Order")
        case .name:
            return String(localized: "rss.sources.sort.name", defaultValue: "Name")
        case .recentRefresh:
            return String(localized: "rss.sources.sort.refresh", defaultValue: "Latest Refresh")
        case .articleCount:
            return String(localized: "rss.sources.sort.count", defaultValue: "Article Count")
        }
    }
}

struct SourcesView: View {
    @Environment(FeedStore.self) private var feedStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(AppLogger.self) private var appLogger

    @State private var showingAddFeed = false
    @State private var editingSourceID: FeedSource.ID?
    @State private var deletingSourceID: FeedSource.ID?
    @State private var sharedURL: SharedSourceURL?
    @State private var sharedExportFile: SharedExportFile?
    @State private var showingOPMLImporter = false
    @State private var isImportingOPML = false
    @State private var opmlImportMessage: String?
    @State private var opmlImportError: String?
    @AppStorage("Tsukuyomi.Sources.sortMode") private var sortModeRawValue = SourceSortMode.manual.rawValue

    private var sortMode: SourceSortMode {
        get { SourceSortMode(rawValue: sortModeRawValue) ?? .manual }
        nonmutating set { sortModeRawValue = newValue.rawValue }
    }

    private var displayedSources: [FeedSource] {
        switch sortMode {
        case .manual:
            return feedStore.sources
        case .name:
            return feedStore.sources.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .recentRefresh:
            return feedStore.sources.sorted { ($0.lastRefreshAt ?? .distantPast) > ($1.lastRefreshAt ?? .distantPast) }
        case .articleCount:
            return feedStore.sources.sorted { $0.articleCount > $1.articleCount }
        }
    }

    var body: some View {
        ZStack {
            TsukuyomiBackdrop()
            Group {
                if feedStore.sources.isEmpty {
                    ScrollView {
                        EmptyStateCard(
                            title: String(localized: "rss.sources.empty.title", defaultValue: "No feeds yet"),
                            message: String(localized: "rss.sources.empty.message", defaultValue: "Use the plus button to add an RSS source. Recommended feeds are available in the add sheet.")
                        )
                        .padding(20)
                    }
                } else {
                    List(displayedSources) { source in
                        NavigationLink {
                            FeedSourceDetailView(sourceID: source.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(source.title)
                                    .font(.headline)
                                    .foregroundStyle(Color.primaryText)
                                Text(source.subtitle.isEmpty ? source.feedURL : source.subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                                HStack {
                                    Text("\(source.articleCount) \(String(localized: "rss.source.items", defaultValue: "items"))")
                                    Spacer()
                                    if let lastRefreshAt = source.lastRefreshAt {
                                        Text(lastRefreshAt.formatted(date: .abbreviated, time: .shortened))
                                    }
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                        }
                        .contextMenu {
                            Button(String(localized: "action.share", defaultValue: "Share")) {
                                appLogger.logUI("Shared source URL \(source.feedURL)")
                                sharedURL = SharedSourceURL(url: source.feedURL)
                            }
                            Button(String(localized: "action.delete", defaultValue: "Delete"), role: .destructive) {
                                appLogger.logUI("Requested deletion for source \(source.title)")
                                deletingSourceID = source.id
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(String(localized: "action.delete", defaultValue: "Delete"), role: .destructive) {
                                appLogger.logUI("Requested deletion for source \(source.title)")
                                deletingSourceID = source.id
                            }
                            Button(String(localized: "action.edit", defaultValue: "Edit")) {
                                appLogger.logUI("Opened edit sheet for source \(source.title)")
                                editingSourceID = source.id
                            }
                            .tint(Color.accentCinder)
                        }
                        .listRowBackground(Color.clear)
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                }
            }
        }
        .navigationTitle(String(localized: "rss.sources.title", defaultValue: "Sources"))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button {
                        appLogger.logUI("Opened OPML importer from Sources tab")
                        showingOPMLImporter = true
                    } label: {
                        Label(String(localized: "sources.opml.import", defaultValue: "Import OPML"), systemImage: "tray.and.arrow.down")
                    }

                    Button {
                        exportOPML()
                    } label: {
                        Label(String(localized: "sources.opml.export", defaultValue: "Export OPML"), systemImage: "tray.and.arrow.up")
                    }
                    .disabled(feedStore.sources.isEmpty)
                } label: {
                    if isImportingOPML {
                        ProgressView()
                    } else {
                        Image(systemName: "doc.badge.arrow.up")
                    }
                }

                Menu {
                    Picker(String(localized: "rss.sources.sort.title", defaultValue: "Sort"), selection: Binding(
                        get: { sortMode },
                        set: { newValue in
                            appLogger.logUI("Changed RSS source sort mode to \(newValue.rawValue)")
                            sortMode = newValue
                        }
                    )) {
                        ForEach(SourceSortMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down.circle")
                }

                Button {
                    appLogger.logUI("Tapped refresh all feeds from Sources tab")
                    Task { await feedStore.forceRefreshAll(settingsStore: settingsStore, logger: appLogger) }
                } label: {
                    if feedStore.isRefreshing {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }

                Button {
                    appLogger.logUI("Opened add feed sheet from Sources tab")
                    showingAddFeed = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddFeed) {
            AddFeedSheet()
        }
        .sheet(item: $editingSourceID) { sourceID in
            EditFeedSheet(sourceID: sourceID)
        }
        .sheet(item: $sharedURL) { item in
            ShareSheet(items: [item.url])
        }
        .sheet(item: $sharedExportFile) { item in
            ShareSheet(items: [item.url])
        }
        .fileImporter(
            isPresented: $showingOPMLImporter,
            allowedContentTypes: [.xml, .data, .item],
            allowsMultipleSelection: false
        ) { result in
            Task { await handleOPMLImport(result) }
        }
        .alert(String(localized: "sources.opml.import.result.title", defaultValue: "OPML Import"), isPresented: Binding(
            get: { opmlImportMessage != nil },
            set: { if !$0 { opmlImportMessage = nil } }
        )) {
            Button(String(localized: "action.close", defaultValue: "Close"), role: .cancel) {
                opmlImportMessage = nil
            }
        } message: {
            if let opmlImportMessage {
                Text(opmlImportMessage)
            }
        }
        .alert(String(localized: "sources.opml.error.title", defaultValue: "OPML Error"), isPresented: Binding(
            get: { opmlImportError != nil },
            set: { if !$0 { opmlImportError = nil } }
        )) {
            Button(String(localized: "action.close", defaultValue: "Close"), role: .cancel) {
                opmlImportError = nil
            }
        } message: {
            if let opmlImportError {
                Text(opmlImportError)
            }
        }
        .alert(
            String(localized: "rss.sources.delete.title", defaultValue: "Delete Source"),
            isPresented: Binding(
                get: { deletingSourceID != nil },
                set: { if !$0 { deletingSourceID = nil } }
            )
        ) {
            Button(String(localized: "action.delete", defaultValue: "Delete"), role: .destructive) {
                guard let deletingSourceID else { return }
                withAnimation(.snappy(duration: 0.28)) {
                    feedStore.removeSource(sourceID: deletingSourceID, logger: appLogger)
                }
                self.deletingSourceID = nil
            }
            Button(String(localized: "action.close", defaultValue: "Close"), role: .cancel) {
                deletingSourceID = nil
            }
        } message: {
            if let deletingSourceID,
               let source = feedStore.sources.first(where: { $0.id == deletingSourceID }) {
                Text(String(
                    format: String(localized: "rss.sources.delete.message", defaultValue: "Delete %@ and remove its cached articles?"),
                    source.title
                ))
            }
        }
        .onAppear {
            appLogger.logUI("Displayed Sources tab with \(feedStore.sources.count) feeds")
        }
    }

    private func exportOPML() {
        do {
            let url = try OPMLService.export(sources: feedStore.sources)
            appLogger.log("Exported OPML with \(feedStore.sources.count) sources to \(url.lastPathComponent)", category: .storage)
            sharedExportFile = SharedExportFile(url: url)
        } catch {
            appLogger.log("Failed to export OPML: \(error.localizedDescription)", category: .storage)
            opmlImportError = error.localizedDescription
        }
    }

    private func handleOPMLImport(_ result: Result<[URL], Error>) async {
        isImportingOPML = true
        defer { isImportingOPML = false }

        do {
            guard let url = try result.get().first else { return }
            let isSecurityScoped = url.startAccessingSecurityScopedResource()
            defer {
                if isSecurityScoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            let entries = try OPMLService.parse(data: data)
            guard !entries.isEmpty else {
                opmlImportMessage = String(localized: "sources.opml.empty", defaultValue: "No RSS feeds were found in this OPML file.")
                return
            }

            var imported = 0
            var failed: [String] = []
            for entry in entries {
                do {
                    try await feedStore.addFeed(urlString: entry.xmlURL)
                    imported += 1
                } catch FeedStoreError.duplicateSource {
                    failed.append("\(entry.xmlURL) - \(String(localized: "rss.add.error.duplicate", defaultValue: "This RSS source has already been added."))")
                } catch {
                    failed.append("\(entry.xmlURL) - \(error.localizedDescription)")
                }
            }

            appLogger.log("Imported OPML with \(imported) succeeded and \(failed.count) failed feeds", category: .rss)
            if failed.isEmpty {
                opmlImportMessage = String(
                    format: String(localized: "sources.opml.import.success", defaultValue: "%d feeds imported."),
                    imported
                )
            } else {
                opmlImportMessage = String(
                    format: String(localized: "sources.opml.import.partial", defaultValue: "%d feeds imported. Failed: %@"),
                    imported,
                    failed.joined(separator: "\n")
                )
            }
        } catch {
            appLogger.log("Failed to import OPML: \(error.localizedDescription)", category: .rss)
            opmlImportError = error.localizedDescription
        }
    }
}

private struct SharedSourceURL: Identifiable {
    let id = UUID()
    let url: String
}

private struct EditFeedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FeedStore.self) private var feedStore
    @Environment(AppLogger.self) private var appLogger

    let sourceID: FeedSource.ID

    @State private var title = ""
    @State private var subtitle = ""
    @State private var feedURL = ""
    @State private var siteURL = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var source: FeedSource? {
        feedStore.sources.first(where: { $0.id == sourceID })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "rss.edit.section.identity", defaultValue: "Feed")) {
                    TextField(String(localized: "rss.edit.title", defaultValue: "Title"), text: $title)
                    TextField(String(localized: "rss.edit.subtitle", defaultValue: "Subtitle"), text: $subtitle)
                    TextField(String(localized: "rss.edit.feedURL", defaultValue: "Feed URL"), text: $feedURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    TextField(String(localized: "rss.edit.siteURL", defaultValue: "Site URL"), text: $siteURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(String(localized: "action.edit", defaultValue: "Edit"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "action.close", defaultValue: "Close")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "action.save", defaultValue: "Save")) {
                        Task { await submit() }
                    }
                    .disabled(feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .onAppear {
                guard let source else { return }
                title = source.title
                subtitle = source.subtitle
                feedURL = source.feedURL
                siteURL = source.siteURL
            }
        }
    }

    private func submit() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        do {
            try await feedStore.updateSource(
                sourceID: sourceID,
                title: title,
                subtitle: subtitle,
                feedURL: feedURL,
                siteURL: siteURL,
                logger: appLogger
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            appLogger.log("Failed to update source: \(error.localizedDescription)", category: .rss)
        }
    }
}
