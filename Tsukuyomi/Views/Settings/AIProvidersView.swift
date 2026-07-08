import SwiftUI
import Combine

struct AIProvidersView: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(AppLogger.self) private var appLogger

    @State private var editingProvider: AIProviderConfiguration?

    var body: some View {
        List {
            inferenceSection
            providersSection
        }
        .tsukuyomiListSurface()
        .navigationTitle(String(localized: "ai.providers.title", defaultValue: "AI"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editingProvider = settingsStore.newProviderDraft()
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $editingProvider, onDismiss: {
            editingProvider = nil
        }) { provider in
            AIProviderEditorView(provider: provider)
        }
        .onReceive(NotificationCenter.default.publisher(for: .tsukuyomiOpenAIProviderEditor)) { note in
            if let id = note.object as? UUID,
               let provider = settingsStore.provider(with: id),
               !provider.usesAppleIntelligence {
                editingProvider = provider
            }
        }
    }

    private var inferenceSection: some View {
        Section {
            Picker(String(localized: "ai.providers.default.label", defaultValue: "Current"), selection: Binding(
                get: { settingsStore.defaultProviderID },
                set: { newValue in
                    guard let newValue else { return }
                    settingsStore.setDefaultProvider(id: newValue, logger: appLogger)
                }
            )) {
                Text(String(localized: "settings.ai.none", defaultValue: "Not Set")).tag(UUID?.none)
                ForEach(settingsStore.aiProviders) { provider in
                    Text(provider.displayName).tag(Optional(provider.id))
                }
            }
            .listRowBackground(Color.clear)

            Picker(String(localized: "ai.settings.language", defaultValue: "Language"), selection: Binding(
                get: { settingsStore.aiOutputLanguage },
                set: { settingsStore.setAIOutputLanguage($0, logger: appLogger) }
            )) {
                ForEach(AIOutputLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .listRowBackground(Color.clear)

            Picker(String(localized: "ai.settings.translation.mode", defaultValue: "Translation Display"), selection: Binding(
                get: { settingsStore.translationDisplayMode },
                set: { settingsStore.setTranslationDisplayMode($0, logger: appLogger) }
            )) {
                ForEach(TranslationDisplayMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .listRowBackground(Color.clear)

            Picker(String(localized: "ai.settings.titles.mode", defaultValue: "Title Translation"), selection: Binding(
                get: { settingsStore.titleTranslationDisplayMode },
                set: { settingsStore.setTitleTranslationDisplayMode($0, logger: appLogger) }
            )) {
                ForEach(TitleTranslationDisplayMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .listRowBackground(Color.clear)

            Toggle(String(localized: "settings.ai.autoSummary", defaultValue: "Automatic Summary"), isOn: Binding(
                get: { settingsStore.autoSummaryEnabled },
                set: { settingsStore.setAutoSummaryEnabled($0, logger: appLogger) }
            ))
            .listRowBackground(Color.clear)

            Toggle(String(localized: "settings.ai.autoTranslation", defaultValue: "Automatic Translation"), isOn: Binding(
                get: { settingsStore.autoTranslationEnabled },
                set: { settingsStore.setAutoTranslationEnabled($0, logger: appLogger) }
            ))
            .listRowBackground(Color.clear)
        } header: {
            Text(String(localized: "ai.settings.inference.section", defaultValue: "Inference"))
        } footer: {
            Text(String(localized: "ai.settings.inference.footer", defaultValue: "These options control the default provider, AI output language, translation layout, and whether article actions run automatically."))
        }
    }

    private var providersSection: some View {
        Section(String(localized: "ai.providers.section", defaultValue: "Providers")) {
            if settingsStore.aiProviders.isEmpty {
                Text(String(localized: "ai.providers.empty", defaultValue: "No providers configured yet. Add one when you are ready to use AI actions."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(settingsStore.aiProviders) { provider in
                Button {
                    guard !provider.usesAppleIntelligence else { return }
                    editingProvider = provider
                } label: {
                    AIProviderRow(
                        provider: provider,
                        isDefault: settingsStore.defaultProviderID == provider.id
                    )
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                    if !provider.usesAppleIntelligence {
                        Button(String(localized: "action.edit", defaultValue: "Edit")) {
                            editingProvider = provider
                        }
                        .tint(Color.accentCinder)
                    }
                }
                .contextMenu {
                    if !provider.usesAppleIntelligence {
                        Button(String(localized: "action.edit", defaultValue: "Edit")) {
                            editingProvider = provider
                        }
                    }
                    Button(String(localized: "ai.providers.makeDefault", defaultValue: "Set as Default")) {
                        settingsStore.setDefaultProvider(id: provider.id, logger: appLogger)
                    }
                    if !provider.usesAppleIntelligence {
                        Button(String(localized: "ai.providers.duplicate", defaultValue: "Duplicate")) {
                            if let newID = settingsStore.duplicateProvider(id: provider.id, logger: appLogger),
                               let duplicatedProvider = settingsStore.provider(with: newID) {
                                editingProvider = duplicatedProvider
                            }
                        }
                        Button(String(localized: "action.delete", defaultValue: "Delete"), role: .destructive) {
                            settingsStore.removeProvider(id: provider.id, logger: appLogger)
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    if !provider.usesAppleIntelligence {
                        Button(String(localized: "action.delete", defaultValue: "Delete"), role: .destructive) {
                            settingsStore.removeProvider(id: provider.id, logger: appLogger)
                        }
                    }
                }
            }
        }
    }
}

private struct AIProviderRow: View {
    let provider: AIProviderConfiguration
    let isDefault: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.title3)
                .foregroundStyle(Color.accentCinder)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                Text(provider.displayName)
                    .foregroundStyle(.primary)
                Text(provider.modelIdentifier.isEmpty ? String(localized: "settings.ai.none", defaultValue: "Not Set") : provider.modelIdentifier)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if provider.usesAppleIntelligence {
                    Text(String(localized: "ai.provider.apple.name", defaultValue: "Apple Intelligence"))
                        .font(.caption)
                        .foregroundStyle(Color.accentCinder)
                }
                if !provider.tags.isEmpty {
                    Text(provider.tags.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }

            Spacer()

            if isDefault {
                Label(String(localized: "ai.providers.default.badge", defaultValue: "Default"), systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentCinder)
            }
        }
        .padding(.vertical, 4)
    }
}

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

struct AIProviderEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(AppLogger.self) private var appLogger

    @State var provider: AIProviderConfiguration
    @State private var availableModels: [String] = []
    @State private var isLoadingModels = false
    @State private var showingModelPicker = false
    @State private var modelFetchMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(String(localized: "ai.provider.section.identity", defaultValue: "Identity")) {
                    TextField(String(localized: "ai.provider.name", defaultValue: "Nickname"), text: $provider.providerName)
                    TextField(String(localized: "ai.provider.endpoint", defaultValue: "Inference Endpoint"), text: $provider.endpoint)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(provider.usesAppleIntelligence)
                }

                Section(String(localized: "ai.provider.section.model", defaultValue: "Model")) {
                    TextField(String(localized: "ai.provider.model", defaultValue: "Model Identifier"), text: $provider.modelIdentifier)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        Task { await loadModelsFromServer() }
                    } label: {
                        HStack {
                            Text(String(localized: "ai.provider.models.fetch", defaultValue: "Fetch Models from Server"))
                            Spacer()
                            if isLoadingModels {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isLoadingModels)

                    if let modelFetchMessage {
                        Text(modelFetchMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if provider.usesAppleIntelligence {
                        Text(String(localized: "ai.provider.apple.footer", defaultValue: "Apple Intelligence uses the on-device system model. Availability depends on device eligibility and whether Apple Intelligence is enabled."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if !availableModels.isEmpty {
                        Button {
                            showingModelPicker = true
                        } label: {
                            HStack {
                                Text(String(localized: "ai.provider.models.select", defaultValue: "Select a Model"))
                                Spacer()
                                Text(provider.modelIdentifier.isEmpty ? String(localized: "settings.ai.none", defaultValue: "Not Set") : provider.modelIdentifier)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section(String(localized: "ai.provider.section.parameters", defaultValue: "Parameters")) {
                    Picker(String(localized: "ai.provider.context", defaultValue: "Context Length"), selection: $provider.contextLength) {
                        ForEach(AIModelContextLength.allCases) { length in
                            Text(contextLabel(for: length)).tag(length)
                        }
                    }
                    Picker(String(localized: "ai.provider.response", defaultValue: "Content Style"), selection: $provider.responseFormat) {
                        ForEach(AIResponseFormat.allCases) { format in
                            Text(responseFormatLabel(for: format)).tag(format)
                        }
                    }
                    if settingsStore.defaultProviderID == provider.id {
                        Label(String(localized: "ai.providers.default.badge", defaultValue: "Default"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentCinder)
                    } else if isPersistedProvider {
                        Button(String(localized: "ai.providers.makeDefault", defaultValue: "Set as Default")) {
                            settingsStore.setDefaultProvider(id: provider.id, logger: appLogger)
                        }
                    }
                }

                Section(String(localized: "ai.provider.section.headers", defaultValue: "Headers")) {
                    TextEditor(text: $provider.headersJSON)
                        .frame(minHeight: 120)
                        .font(.system(.footnote, design: .monospaced))
                }
                Section(String(localized: "ai.provider.section.body", defaultValue: "Body")) {
                    TextEditor(text: $provider.bodyFieldsJSON)
                        .frame(minHeight: 120)
                        .font(.system(.footnote, design: .monospaced))
                }

                Section(String(localized: "ai.provider.section.prompts", defaultValue: "Prompts")) {
                    TextEditor(text: $provider.summaryPrompt)
                        .frame(minHeight: 96)
                    TextEditor(text: $provider.translationPrompt)
                        .frame(minHeight: 96)
                }
            }
            .navigationTitle(provider.displayName)
            .onAppear {
                if let inferred = AIResponseFormat.inferredFormat(from: provider.endpoint) {
                    provider.responseFormat = inferred
                }
            }
            .onChange(of: provider.endpoint) { _, newValue in
                guard let inferred = AIResponseFormat.inferredFormat(from: newValue) else { return }
                provider.responseFormat = inferred
                if provider.modelListEndpoint.contains("$INFERENCE_ENDPOINT$") {
                    provider.modelListEndpoint = ""
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "action.close", defaultValue: "Close")) {
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if isPersistedProvider && !provider.usesAppleIntelligence {
                        Menu {
                            Button(String(localized: "ai.providers.makeDefault", defaultValue: "Set as Default")) {
                                settingsStore.setDefaultProvider(id: provider.id, logger: appLogger)
                            }
                            Button(String(localized: "ai.providers.duplicate", defaultValue: "Duplicate")) {
                                if let newID = settingsStore.duplicateProvider(id: provider.id, logger: appLogger) {
                                    editingReplacement(id: newID)
                                }
                            }
                            Button(String(localized: "action.delete", defaultValue: "Delete"), role: .destructive) {
                                settingsStore.removeProvider(id: provider.id, logger: appLogger)
                                dismiss()
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }

                    Button(String(localized: "action.save", defaultValue: "Save")) {
                        settingsStore.saveProvider(provider, logger: appLogger)
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingModelPicker) {
                AIModelSelectionSheet(
                    models: availableModels,
                    selectedModel: provider.modelIdentifier
                ) { selection in
                    provider.modelIdentifier = selection
                    showingModelPicker = false
                }
            }
        }
    }

    private var isPersistedProvider: Bool {
        settingsStore.provider(with: provider.id) != nil
    }

    private func loadModelsFromServer() async {
        isLoadingModels = true
        defer { isLoadingModels = false }
        do {
            let normalizedProvider = normalizedProviderForFetch(provider)
            let models = try await settingsStore.fetchModelIdentifiers(for: normalizedProvider, logger: appLogger)
            availableModels = models
            showingModelPicker = !models.isEmpty
            modelFetchMessage = models.isEmpty
                ? String(localized: "ai.provider.models.empty", defaultValue: "No models were returned. Check the endpoint and Headers JSON.")
                : String(format: String(localized: "ai.provider.models.count", defaultValue: "%d models loaded."), models.count)
        } catch {
            availableModels = []
            showingModelPicker = false
            if let error = error as? AIServiceError {
                switch error {
                case .missingAPIKey:
                    modelFetchMessage = String(localized: "ai.provider.models.authRequired", defaultValue: "The server requires request headers. Add Authorization or other required headers to Headers JSON.")
                default:
                    modelFetchMessage = error.localizedDescription
                }
            } else {
                modelFetchMessage = error.localizedDescription
            }
        }
    }

    private func editingReplacement(id: UUID) {
        settingsStore.updateProvider(provider, logger: appLogger)
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .tsukuyomiOpenAIProviderEditor, object: id)
        }
    }

    private func normalizedProviderForFetch(_ provider: AIProviderConfiguration) -> AIProviderConfiguration {
        var provider = provider
        if let inferred = AIResponseFormat.inferredFormat(from: provider.endpoint) {
            provider.responseFormat = inferred
        }
        if provider.modelListEndpoint.contains("$INFERENCE_ENDPOINT$") {
            provider.modelListEndpoint = ""
        }
        return provider
    }

    private func contextLabel(for length: AIModelContextLength) -> String {
        switch length {
        case .short4k:
            return "4K"
        case .short8k:
            return "8K"
        case .medium16k:
            return "16K"
        case .medium32k:
            return "32K"
        case .medium64k:
            return "64K"
        case .long100k:
            return "100K"
        case .long200k:
            return "200K"
        case .huge1m:
            return "1M"
        case .infinity:
            return String(localized: "ai.provider.context.infinity", defaultValue: "Infinity")
        }
    }

    private func responseFormatLabel(for format: AIResponseFormat) -> String {
        switch format {
        case .chatCompletions:
            return String(localized: "ai.provider.response.chat", defaultValue: "Chat Completions")
        case .responses:
            return String(localized: "ai.provider.response.responses", defaultValue: "Responses")
        }
    }
}

extension Notification.Name {
    static let tsukuyomiOpenAIProviderEditor = Notification.Name("Tsukuyomi.OpenAIProviderEditor")
}

private struct AIModelSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss

    let models: [String]
    let selectedModel: String
    let onSelect: (String) -> Void

    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredSections, id: \.title) { section in
                    Section(section.title) {
                        ForEach(section.items, id: \.self) { model in
                            Button {
                                onSelect(model)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(displayName(for: model))
                                            .foregroundStyle(.primary)
                                        if let scope = scopeName(for: model), !scope.isEmpty {
                                            Text(scope)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if model == selectedModel {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.accentCinder)
                                    }
                                }
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(TsukuyomiBackdrop())
            .navigationTitle(String(localized: "ai.provider.models.select", defaultValue: "Select a Model"))
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "action.close", defaultValue: "Close")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var filteredSections: [ModelSection] {
        let filtered = models.filter { model in
            searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || model.localizedCaseInsensitiveContains(searchText)
        }
        let grouped = Dictionary(grouping: filtered, by: { scopeName(for: $0) ?? String(localized: "ai.provider.models.ungrouped", defaultValue: "Ungrouped") })
        return grouped.keys.sorted().map { key in
            ModelSection(title: key, items: grouped[key, default: []].sorted())
        }
    }

    private func scopeName(for model: String) -> String? {
        guard model.contains("/") else { return nil }
        return model.components(separatedBy: "/").first
    }

    private func displayName(for model: String) -> String {
        guard let scope = scopeName(for: model) else { return model }
        return model.replacingOccurrences(of: "\(scope)/", with: "")
    }

    private struct ModelSection {
        let title: String
        let items: [String]
    }
}
