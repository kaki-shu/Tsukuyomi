import SwiftUI

struct PagesView: View {
    @Environment(FeedStore.self) private var feedStore
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(AppLogger.self) private var appLogger
    @State private var showingAddPage = false
    @State private var editingPageID: FeedArticle.ID?
    @State private var removingClipID: FeedArticle.ID?
    @State private var isManagingPages = false
    @State private var isExportingClips = false
    @State private var exportProgress = 0.0
    @State private var sharedExportFile: SharedExportFile?
    @State private var exportErrorMessage: String?

    var body: some View {
        ZStack {
            TsukuyomiBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if clips.isEmpty {
                        EmptyStateCard(
                            title: String(localized: "pages.empty.title", defaultValue: "No clips yet"),
                            message: String(localized: "pages.empty.message", defaultValue: "Use the plus button to save a web page for later.")
                        )
                    } else {
                        section(articles: clips)
                    }
                }
                .padding(TsukuyomiLayout.horizontalPadding)
                .frame(maxWidth: TsukuyomiLayout.readableMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if isExportingClips {
                exportProgressOverlay
            }
        }
        .navigationTitle(String(localized: "pages.title", defaultValue: "Clips"))
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if !clips.isEmpty {
                    Button {
                        Task { await exportClips() }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(isExportingClips)

                    Button(isManagingPages ? String(localized: "action.close", defaultValue: "Close") : String(localized: "action.edit", defaultValue: "Edit")) {
                        isManagingPages.toggle()
                    }
                }
                Button {
                    appLogger.logUI("Opened add page sheet from Pages tab")
                    showingAddPage = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddPage) {
            AddPageSheet()
        }
        .sheet(item: $editingPageID) { articleID in
            EditPageSheet(articleID: articleID)
        }
        .sheet(item: $sharedExportFile) { item in
            ShareSheet(items: [item.url])
        }
        .alert(String(localized: "clips.export.error.title", defaultValue: "Export Failed"), isPresented: Binding(
            get: { exportErrorMessage != nil },
            set: { if !$0 { exportErrorMessage = nil } }
        )) {
            Button(String(localized: "action.close", defaultValue: "Close"), role: .cancel) {
                exportErrorMessage = nil
            }
        } message: {
            if let exportErrorMessage {
                Text(exportErrorMessage)
            }
        }
        .confirmationDialog(
            String(localized: "pages.clip.remove.title", defaultValue: "Remove from Clip"),
            isPresented: Binding(
                get: { removingClipID != nil },
                set: { if !$0 { removingClipID = nil } }
            )
        ) {
            Button(String(localized: "pages.clip.remove", defaultValue: "Remove from Clip"), role: .destructive) {
                guard let removingClipID else { return }
                feedStore.removeClip(articleID: removingClipID, logger: appLogger)
                self.removingClipID = nil
            }
            Button(String(localized: "action.close", defaultValue: "Close"), role: .cancel) {
                removingClipID = nil
            }
        }
        .onAppear {
            appLogger.logUI("Displayed Pages tab with \(clips.count) clips")
        }
        .task(id: clips.map(\.id)) {
            await feedStore.prefetchTitleTranslations(
                for: clips.map(\.id),
                settingsStore: settingsStore,
                logger: appLogger
            )
        }
    }

    private var clips: [FeedArticle] {
        feedStore.clips
    }

    private func section(articles: [FeedArticle]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVStack(spacing: 12) {
                ForEach(articles) { article in
                    VStack(alignment: .leading, spacing: 10) {
                        NavigationLink {
                            ArticleDestinationView(articleID: article.id)
                        } label: {
                            ArticleRow(article: article)
                        }
                        .buttonStyle(.plain)

                        if isManagingPages {
                            HStack(spacing: 12) {
                                if article.sourceKind == .page {
                                    Button(String(localized: "action.edit", defaultValue: "Edit")) {
                                        editingPageID = article.id
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(Color.accentCinder)
                                }

                                Button(removeButtonTitle(for: article), role: .destructive) {
                                    removingClipID = article.id
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func removeButtonTitle(for article: FeedArticle) -> String {
        article.sourceKind == .page
            ? String(localized: "action.delete", defaultValue: "Delete")
            : String(localized: "pages.clip.remove", defaultValue: "Remove from Clip")
    }

    private var exportProgressOverlay: some View {
        ZStack {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
            VStack(alignment: .leading, spacing: 12) {
                Text(String(localized: "clips.export.progress", defaultValue: "Exporting Clips"))
                    .font(.headline)
                    .foregroundStyle(Color.primaryText)
                ProgressView(value: exportProgress)
                    .tint(Color.accentCinder)
                Text("\(Int(exportProgress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: 320, alignment: .leading)
            .background(Color.pageBackgroundTop, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func exportClips() async {
        guard !clips.isEmpty else { return }
        isExportingClips = true
        exportProgress = 0
        appLogger.logUI("Requested clips export for \(clips.count) articles")
        do {
            let url = try await ClipExportService.export(articles: clips) { progress in
                exportProgress = progress
            }
            appLogger.log("Exported clips archive to \(url.lastPathComponent)", category: .storage)
            sharedExportFile = SharedExportFile(url: url)
        } catch {
            appLogger.log("Failed to export clips archive: \(error.localizedDescription)", category: .storage)
            exportErrorMessage = error.localizedDescription
        }
        isExportingClips = false
    }
}

private struct EditPageSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(FeedStore.self) private var feedStore
    @Environment(AppLogger.self) private var appLogger

    let articleID: FeedArticle.ID

    @State private var title = ""
    @State private var urlString = ""
    @State private var errorMessage: String?

    private var article: FeedArticle? {
        feedStore.article(id: articleID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "pages.edit.title", defaultValue: "Title"), text: $title)
                    TextField(String(localized: "pages.edit.url", defaultValue: "Page URL"), text: $urlString)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    if let errorMessage {
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
                        do {
                            try feedStore.updatePage(articleID: articleID, title: title, urlString: urlString, logger: appLogger)
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }
            .onAppear {
                if let article {
                    title = article.title
                    urlString = article.url
                }
            }
        }
    }
}
