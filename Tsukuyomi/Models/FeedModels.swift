import Foundation

enum ArticleSourceKind: String, Codable, Hashable, CaseIterable {
    case rss
    case page
}

struct FeedSource: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String
    var subtitle: String
    var feedURL: String
    var siteURL: String
    var tintHex: String
    var createdAt: Date = .now
    var updatedAt: Date = .now
    var lastRefreshAt: Date?
    var articleCount: Int = 0
}

struct FeedArticle: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var feedID: UUID
    var feedTitle: String
    var sourceKind: ArticleSourceKind = .rss
    var title: String
    var url: String
    var author: String?
    var summary: String
    var content: String
    var imageURL: String?
    var videoURL: String?
    var audioURL: String?
    var mediaDuration: Int?
    var publishedDate: Date?
    var isRead: Bool = false
    var isSaved: Bool = false
    var aiSummary: String?
    var aiTranslation: String?
    var aiTitleTranslation: String?
    var updatedAt: Date = .now
}

extension FeedArticle {
    var bodyText: String {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedContent.isEmpty {
            return trimmedContent
        }
        return summary
    }

    var isYouTubeArticle: Bool {
        let candidates = [url, videoURL, audioURL].compactMap { $0?.lowercased() ?? $0 }
        return candidates.contains { value in
            value.contains("youtube.com") || value.contains("youtu.be")
        }
    }
}

enum AIOutputLanguage: String, CaseIterable, Codable, Identifiable {
    case followApp
    case chineseSimplified
    case english
    case japanese

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .followApp:
            return String(localized: "ai.language.followApp", defaultValue: "Follow App")
        case .chineseSimplified:
            return String(localized: "ai.language.chineseSimplified", defaultValue: "Chinese (Simplified)")
        case .english:
            return String(localized: "ai.language.english", defaultValue: "English")
        case .japanese:
            return String(localized: "ai.language.japanese", defaultValue: "Japanese")
        }
    }

    var promptLabel: String {
        switch self {
        case .followApp:
            return Locale.current.localizedString(forLanguageCode: Locale.current.language.languageCode?.identifier ?? "en") ?? "the current app language"
        case .chineseSimplified:
            return "Simplified Chinese"
        case .english:
            return "English"
        case .japanese:
            return "Japanese"
        }
    }
}

enum TranslationDisplayMode: String, CaseIterable, Codable, Identifiable {
    case translationOnly
    case replaceOriginal
    case bilingual

    var id: String { rawValue }

    static var allCases: [TranslationDisplayMode] {
        [.translationOnly, .bilingual]
    }

    var displayName: String {
        switch self {
        case .translationOnly:
            return String(localized: "ai.settings.translation.only", defaultValue: "Translation Only")
        case .replaceOriginal:
            return String(localized: "ai.settings.translation.only", defaultValue: "Translation Only")
        case .bilingual:
            return String(localized: "ai.settings.translation.bilingual", defaultValue: "Original + Translation")
        }
    }

    var usesTranslatedBodyOnly: Bool {
        switch self {
        case .translationOnly, .replaceOriginal:
            return true
        case .bilingual:
            return false
        }
    }
}

enum TitleTranslationDisplayMode: String, CaseIterable, Codable, Identifiable {
    case original
    case translationOnly
    case bilingual

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original:
            return String(localized: "ai.settings.titles.original", defaultValue: "Original Only")
        case .translationOnly:
            return String(localized: "ai.settings.titles.translationOnly", defaultValue: "Translated Only")
        case .bilingual:
            return String(localized: "ai.settings.titles.bilingual", defaultValue: "Original + Translation")
        }
    }
}

enum ProviderPreset: String, CaseIterable, Codable, Identifiable {
    case appleIntelligence = "Apple Intelligence"
    case openAI = "OpenAI"
    case openRouter = "OpenRouter"
    case custom = "Custom"

    var id: String { rawValue }

    var defaultEndpoint: String {
        switch self {
        case .appleIntelligence:
            return "apple-intelligence://system"
        case .openAI:
            return "https://api.openai.com/v1"
        case .openRouter:
            return "https://openrouter.ai/api/v1"
        case .custom:
            return "https://example.com/v1"
        }
    }

    var defaultHeaders: String {
        switch self {
        case .appleIntelligence:
            return ""
        case .openAI:
            return ""
        case .openRouter:
            return """
            {
              "HTTP-Referer": "https://tsukuyomi.app",
              "X-Title": "Tsukuyomi"
            }
            """
        case .custom:
            return "{}"
        }
    }
}

enum AIResponseFormat: String, CaseIterable, Codable, Identifiable {
    case chatCompletions
    case responses

    var id: String { rawValue }

    var defaultModelListEndpoint: String {
        ""
    }

    static func inferredFormat(from endpoint: String) -> AIResponseFormat? {
        let normalized = endpoint
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return nil }
        if normalized.hasSuffix("/responses") {
            return .responses
        }
        if normalized.hasSuffix("/chat/completions") {
            return .chatCompletions
        }
        return nil
    }
}

enum AIModelCapability: String, CaseIterable, Codable, Identifiable, Hashable {
    case visual
    case auditory
    case tool
    case developerRole

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .visual:
            return String(localized: "ai.provider.capability.visual", defaultValue: "Vision")
        case .auditory:
            return String(localized: "ai.provider.capability.auditory", defaultValue: "Audio")
        case .tool:
            return String(localized: "ai.provider.capability.tool", defaultValue: "Tool Use")
        case .developerRole:
            return String(localized: "ai.provider.capability.developer", defaultValue: "Developer Role")
        }
    }

    var descriptionText: String {
        switch self {
        case .visual:
            return String(localized: "ai.provider.capability.visual.description", defaultValue: "Enable image and screenshot understanding for compatible models.")
        case .auditory:
            return String(localized: "ai.provider.capability.auditory.description", defaultValue: "Allow speech or audio input when the service supports it.")
        case .tool:
            return String(localized: "ai.provider.capability.tool.description", defaultValue: "Allow the model to call structured tools during inference.")
        case .developerRole:
            return String(localized: "ai.provider.capability.developer.description", defaultValue: "Enable developer-role prompts for providers that support them.")
        }
    }
}

enum AIModelContextLength: Int, CaseIterable, Codable, Identifiable {
    case short4k = 4000
    case short8k = 8000
    case medium16k = 16000
    case medium32k = 32000
    case medium64k = 64000
    case long100k = 100_000
    case long200k = 200_000
    case huge1m = 1_000_000
    case infinity = 2_147_483_647

    var id: Int { rawValue }
}

struct AIProviderConfiguration: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var deviceID: String = UUID().uuidString
    var preset: ProviderPreset = .openAI
    var providerName: String = "OpenAI Compatible"
    var comment: String = ""
    var endpoint: String = "https://api.openai.com/v1"
    var modelListEndpoint: String = ""
    var apiKey: String = ""
    var modelIdentifier: String = "gpt-5-mini"
    var responseFormat: AIResponseFormat = .chatCompletions
    var headersJSON: String = ""
    var bodyFieldsJSON: String = ""
    var capabilities: Set<AIModelCapability> = []
    var contextLength: AIModelContextLength = .medium64k
    var createdAt: Date = .now
    var modifiedAt: Date = .now
    var isRemoved: Bool = false
    var summaryPrompt: String = "Summarize the following article. Keep the structure clear, concise, and useful for later reading."
    var translationPrompt: String = "Translate the following article carefully while preserving structure and formatting."

    var usesAppleIntelligence: Bool {
        preset == .appleIntelligence || endpoint.trimmingCharacters(in: .whitespacesAndNewlines) == "apple-intelligence://system"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case deviceID
        case preset
        case providerName
        case comment
        case endpoint
        case modelListEndpoint
        case apiKey
        case modelIdentifier
        case responseFormat
        case headersJSON
        case bodyFieldsJSON
        case capabilities
        case contextLength
        case createdAt
        case modifiedAt
        case isRemoved
        case summaryPrompt
        case translationPrompt
        case token
        case model_identifier
        case model_list_endpoint
        case response_format
        case headers
        case bodyFields
        case context
        case creation
        case modified
        case removed
        case name
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID) ?? UUID().uuidString
        preset = try container.decodeIfPresent(ProviderPreset.self, forKey: .preset) ?? .openAI
        let decodedProviderName = try container.decodeIfPresent(String.self, forKey: .providerName)
        let decodedLegacyName = try container.decodeIfPresent(String.self, forKey: .name)
        providerName = decodedProviderName ?? decodedLegacyName ?? "OpenAI Compatible"
        comment = try container.decodeIfPresent(String.self, forKey: .comment) ?? ""
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? ProviderPreset.openAI.defaultEndpoint
        let decodedModelListEndpoint = try container.decodeIfPresent(String.self, forKey: .modelListEndpoint)
        let decodedLegacyModelListEndpoint = try container.decodeIfPresent(String.self, forKey: .model_list_endpoint)
        modelListEndpoint = decodedModelListEndpoint ?? decodedLegacyModelListEndpoint ?? ""
        let decodedAPIKey = try container.decodeIfPresent(String.self, forKey: .apiKey)
        let decodedLegacyToken = try container.decodeIfPresent(String.self, forKey: .token)
        apiKey = decodedAPIKey ?? decodedLegacyToken ?? ""
        let decodedModelIdentifier = try container.decodeIfPresent(String.self, forKey: .modelIdentifier)
        let decodedLegacyModelIdentifier = try container.decodeIfPresent(String.self, forKey: .model_identifier)
        modelIdentifier = decodedModelIdentifier ?? decodedLegacyModelIdentifier ?? "gpt-5-mini"
        let decodedResponseFormat = try container.decodeIfPresent(AIResponseFormat.self, forKey: .responseFormat)
        let decodedLegacyResponseFormat = try container.decodeIfPresent(AIResponseFormat.self, forKey: .response_format)
        responseFormat = decodedResponseFormat ?? decodedLegacyResponseFormat ?? .chatCompletions
        if let headersJSONString = try container.decodeIfPresent(String.self, forKey: .headersJSON) {
            headersJSON = headersJSONString
        } else if let headers = try container.decodeIfPresent([String: String].self, forKey: .headers),
                  let data = try? JSONSerialization.data(withJSONObject: headers, options: [.prettyPrinted]),
                  let string = String(data: data, encoding: .utf8) {
            headersJSON = string
        } else {
            headersJSON = ""
        }
        let decodedBodyFields = try container.decodeIfPresent(String.self, forKey: .bodyFieldsJSON)
        let decodedLegacyBodyFields = try container.decodeIfPresent(String.self, forKey: .bodyFields)
        bodyFieldsJSON = decodedBodyFields ?? decodedLegacyBodyFields ?? ""
        capabilities = try container.decodeIfPresent(Set<AIModelCapability>.self, forKey: .capabilities) ?? []
        let decodedContextLength = try container.decodeIfPresent(AIModelContextLength.self, forKey: .contextLength)
        let decodedLegacyContextLength = try container.decodeIfPresent(AIModelContextLength.self, forKey: .context)
        contextLength = decodedContextLength ?? decodedLegacyContextLength ?? .medium64k
        let decodedCreatedAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        let decodedLegacyCreatedAt = try container.decodeIfPresent(Date.self, forKey: .creation)
        createdAt = decodedCreatedAt ?? decodedLegacyCreatedAt ?? .now
        let decodedModifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt)
        let decodedLegacyModifiedAt = try container.decodeIfPresent(Date.self, forKey: .modified)
        modifiedAt = decodedModifiedAt ?? decodedLegacyModifiedAt ?? createdAt
        let decodedRemoved = try container.decodeIfPresent(Bool.self, forKey: .isRemoved)
        let decodedLegacyRemoved = try container.decodeIfPresent(Bool.self, forKey: .removed)
        isRemoved = decodedRemoved ?? decodedLegacyRemoved ?? false
        summaryPrompt = try container.decodeIfPresent(String.self, forKey: .summaryPrompt)
            ?? "Summarize the following article. Keep the structure clear, concise, and useful for later reading."
        translationPrompt = try container.decodeIfPresent(String.self, forKey: .translationPrompt)
            ?? "Translate the following article carefully while preserving structure and formatting."
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(preset, forKey: .preset)
        try container.encode(providerName, forKey: .providerName)
        try container.encode(comment, forKey: .comment)
        try container.encode(endpoint, forKey: .endpoint)
        try container.encode(modelListEndpoint, forKey: .modelListEndpoint)
        try container.encode(apiKey, forKey: .apiKey)
        try container.encode(modelIdentifier, forKey: .modelIdentifier)
        try container.encode(responseFormat, forKey: .responseFormat)
        try container.encode(headersJSON, forKey: .headersJSON)
        try container.encode(bodyFieldsJSON, forKey: .bodyFieldsJSON)
        try container.encode(capabilities, forKey: .capabilities)
        try container.encode(contextLength, forKey: .contextLength)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(modifiedAt, forKey: .modifiedAt)
        try container.encode(isRemoved, forKey: .isRemoved)
        try container.encode(summaryPrompt, forKey: .summaryPrompt)
        try container.encode(translationPrompt, forKey: .translationPrompt)
    }
}

extension AIProviderConfiguration {
    var displayName: String {
        let trimmedName = providerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedName.isEmpty {
            return trimmedName
        }
        let trimmedModel = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedModel.isEmpty {
            return trimmedModel
        }
        return String(localized: "settings.ai.none", defaultValue: "Not Set")
    }

    var inferenceHost: String {
        URL(string: endpoint)?.host ?? ""
    }

    var scopeIdentifier: String {
        let trimmedModel = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedModel.contains("/") {
            return trimmedModel.components(separatedBy: "/").first ?? ""
        }
        return ""
    }

    var tags: [String] {
        var output: [String] = []
        if !inferenceHost.isEmpty {
            output.append("@\(inferenceHost)")
        }
        if !scopeIdentifier.isEmpty {
            output.append("@\(scopeIdentifier)")
        }
        output.append(contentsOf: capabilities.map(\.displayName))
        return output
    }
}

struct AIWorkspaceSettings: Codable, Equatable {
    var providers: [AIProviderConfiguration]
    var defaultProviderID: UUID?
    var outputLanguage: AIOutputLanguage = .followApp
    var translationDisplayMode: TranslationDisplayMode = .bilingual
    var titleTranslationDisplayMode: TitleTranslationDisplayMode = .original
    var titleFont: ReadingFontChoice = .newYork
    var bodyFont: ReadingFontChoice = .system
    var autoSummaryEnabled: Bool = false
    var autoTranslationEnabled: Bool = false

    init(
        providers: [AIProviderConfiguration],
        defaultProviderID: UUID?,
        outputLanguage: AIOutputLanguage = .followApp,
        translationDisplayMode: TranslationDisplayMode = .bilingual,
        titleTranslationDisplayMode: TitleTranslationDisplayMode = .original,
        titleFont: ReadingFontChoice = .newYork,
        bodyFont: ReadingFontChoice = .system,
        autoSummaryEnabled: Bool = false,
        autoTranslationEnabled: Bool = false
    ) {
        self.providers = providers
        self.defaultProviderID = defaultProviderID
        self.outputLanguage = outputLanguage
        self.translationDisplayMode = translationDisplayMode
        self.titleTranslationDisplayMode = titleTranslationDisplayMode
        self.titleFont = titleFont
        self.bodyFont = bodyFont
        self.autoSummaryEnabled = autoSummaryEnabled
        self.autoTranslationEnabled = autoTranslationEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case providers
        case defaultProviderID
        case outputLanguage
        case translationDisplayMode
        case titleTranslationDisplayMode
        case titleFont
        case bodyFont
        case autoSummaryEnabled
        case autoTranslationEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        providers = try container.decode([AIProviderConfiguration].self, forKey: .providers)
        defaultProviderID = try container.decodeIfPresent(UUID.self, forKey: .defaultProviderID)
        outputLanguage = try container.decodeIfPresent(AIOutputLanguage.self, forKey: .outputLanguage) ?? .followApp
        translationDisplayMode = try container.decodeIfPresent(TranslationDisplayMode.self, forKey: .translationDisplayMode) ?? .bilingual
        titleTranslationDisplayMode = try container.decodeIfPresent(TitleTranslationDisplayMode.self, forKey: .titleTranslationDisplayMode) ?? .original
        titleFont = try container.decodeIfPresent(ReadingFontChoice.self, forKey: .titleFont) ?? .newYork
        bodyFont = try container.decodeIfPresent(ReadingFontChoice.self, forKey: .bodyFont) ?? .system
        autoSummaryEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoSummaryEnabled) ?? false
        autoTranslationEnabled = try container.decodeIfPresent(Bool.self, forKey: .autoTranslationEnabled) ?? false
    }
}

struct AppBuild: Codable {
    static let version = "0.1.20260705040624"
    static let build = "20260705040624"
    static let bundleIdentifier = "com.hibajiri.tsukuyomi"
}

extension AIProviderConfiguration {
    static var `default`: AIProviderConfiguration {
        var provider = AIProviderConfiguration()
        provider.deviceID = UUID().uuidString
        provider.preset = .custom
        provider.providerName = ""
        provider.endpoint = ""
        provider.modelListEndpoint = ""
        provider.apiKey = ""
        provider.modelIdentifier = ""
        provider.responseFormat = .chatCompletions
        provider.headersJSON = ""
        provider.bodyFieldsJSON = ""
        provider.capabilities = []
        provider.contextLength = .medium64k
        provider.createdAt = .now
        provider.modifiedAt = .now
        provider.isRemoved = false
        return provider
    }
}
