import Foundation
import Observation
#if canImport(FoundationModels)
import FoundationModels
#endif

@Observable
final class SettingsStore {
    var aiProviders: [AIProviderConfiguration] = []
    var defaultProviderID: UUID?
    var aiOutputLanguage: AIOutputLanguage = .followApp
    var translationDisplayMode: TranslationDisplayMode = .bilingual
    var titleTranslationDisplayMode: TitleTranslationDisplayMode = .original
    var titleFont: ReadingFontChoice = .newYork
    var bodyFont: ReadingFontChoice = .system
    var autoSummaryEnabled = false
    var autoTranslationEnabled = false

    private let defaults = UserDefaults.standard
    private let configurationKey = "Tsukuyomi.AIWorkspaceConfiguration"

    func bootstrap(logger: AppLogger) {
        if let data = defaults.data(forKey: configurationKey),
           let workspace = try? JSONDecoder().decode(AIWorkspaceSettings.self, from: data) {
            aiProviders = workspace.providers.filter { !$0.isRemoved }
            ensureBuiltInProviders()
            defaultProviderID = workspace.defaultProviderID
            aiOutputLanguage = workspace.outputLanguage
            translationDisplayMode = workspace.translationDisplayMode.usesTranslatedBodyOnly ? .translationOnly : .bilingual
            titleTranslationDisplayMode = workspace.titleTranslationDisplayMode
            titleFont = workspace.titleFont
            bodyFont = workspace.bodyFont
            autoSummaryEnabled = workspace.autoSummaryEnabled
            autoTranslationEnabled = workspace.autoTranslationEnabled
            repairDefaultProviderIfNeeded()
            logger.log("Loaded AI workspace: \(workspaceSummary)", category: .storage)
        } else {
            aiProviders = []
            ensureBuiltInProviders()
            defaultProviderID = nil
            aiOutputLanguage = .followApp
            translationDisplayMode = .bilingual
            titleTranslationDisplayMode = .original
            titleFont = .newYork
            bodyFont = .system
            autoSummaryEnabled = false
            autoTranslationEnabled = false
            persist(logger: logger)
            logger.log("Initialized empty AI workspace configuration", category: .storage)
        }
    }

    var defaultProvider: AIProviderConfiguration? {
        guard let defaultProviderID else { return nil }
        return aiProviders.first(where: { $0.id == defaultProviderID })
    }

    func newProviderDraft() -> AIProviderConfiguration {
        var provider = AIProviderConfiguration.default
        provider.providerName = String(localized: "ai.provider.new", defaultValue: "New Provider")
        provider.endpoint = ""
        provider.modelListEndpoint = provider.responseFormat.defaultModelListEndpoint
        provider.apiKey = ""
        provider.modelIdentifier = ""
        provider.headersJSON = ""
        provider.bodyFieldsJSON = ""
        provider.capabilities = []
        provider.modifiedAt = .now
        return provider
    }

    func saveProvider(_ provider: AIProviderConfiguration, logger: AppLogger) {
        var updatedProvider = normalizeProvider(provider)
        updatedProvider.modifiedAt = .now
        if let index = aiProviders.firstIndex(where: { $0.id == updatedProvider.id }) {
            aiProviders[index] = updatedProvider
            logger.log("Updated AI provider \(updatedProvider.providerName)", category: .ai)
        } else {
            aiProviders.append(updatedProvider)
            logger.log("Added AI provider \(updatedProvider.providerName)", category: .ai)
        }
        repairDefaultProviderIfNeeded()
        persist(logger: logger)
    }

    func addProvider(logger: AppLogger) -> UUID {
        let provider = newProviderDraft()
        saveProvider(provider, logger: logger)
        return provider.id
    }

    func addAppleIntelligenceProviderIfNeeded(logger: AppLogger) -> UUID {
        if let existing = aiProviders.first(where: \.usesAppleIntelligence) {
            return existing.id
        }
        let provider = Self.appleIntelligenceProviderTemplate()
        aiProviders.insert(provider, at: 0)
        persist(logger: logger)
        logger.log("Added built-in Apple Intelligence provider", category: .ai)
        return provider.id
    }

    func duplicateProvider(id: UUID, logger: AppLogger) -> UUID? {
        guard var provider = provider(with: id) else { return nil }
        guard !provider.usesAppleIntelligence else {
            logger.log("Skipped duplicating built-in Apple Intelligence provider", category: .ai)
            return nil
        }
        provider.id = UUID()
        provider.deviceID = UUID().uuidString
        provider.createdAt = .now
        provider.modifiedAt = .now
        provider.isRemoved = false
        provider.providerName = provider.displayName + " Copy"
        aiProviders.append(provider)
        persist(logger: logger)
        logger.log("Duplicated AI provider \(id.uuidString) to \(provider.id.uuidString)", category: .ai)
        return provider.id
    }

    func provider(with id: UUID) -> AIProviderConfiguration? {
        aiProviders.first(where: { $0.id == id })
    }

    func updateProvider(_ provider: AIProviderConfiguration, logger: AppLogger) {
        guard !provider.usesAppleIntelligence else {
            logger.log("Skipped editing built-in Apple Intelligence provider", category: .ai)
            return
        }
        guard let index = aiProviders.firstIndex(where: { $0.id == provider.id }) else { return }
        var updatedProvider = normalizeProvider(provider)
        updatedProvider.modifiedAt = .now
        aiProviders[index] = updatedProvider
        repairDefaultProviderIfNeeded()
        persist(logger: logger)
        logger.log("Updated AI provider \(updatedProvider.providerName)", category: .ai)
    }

    func setDefaultProvider(id: UUID, logger: AppLogger) {
        defaultProviderID = id
        persist(logger: logger)
        logger.log("Selected default AI provider \(id.uuidString)", category: .ai)
    }

    func removeProvider(id: UUID, logger: AppLogger) {
        guard aiProviders.first(where: { $0.id == id })?.usesAppleIntelligence != true else {
            logger.log("Skipped removing built-in Apple Intelligence provider", category: .ai)
            return
        }
        aiProviders.removeAll(where: { $0.id == id })
        repairDefaultProviderIfNeeded()
        persist(logger: logger)
        logger.log("Removed AI provider \(id.uuidString)", category: .ai)
    }

    func setAIOutputLanguage(_ language: AIOutputLanguage, logger: AppLogger) {
        aiOutputLanguage = language
        persist(logger: logger)
        logger.log("Selected AI output language \(language.rawValue)", category: .ai)
    }

    func setTranslationDisplayMode(_ mode: TranslationDisplayMode, logger: AppLogger) {
        translationDisplayMode = mode
        persist(logger: logger)
        logger.log("Selected translation display mode \(mode.rawValue)", category: .ai)
    }

    func setTitleTranslationDisplayMode(_ mode: TitleTranslationDisplayMode, logger: AppLogger) {
        titleTranslationDisplayMode = mode
        persist(logger: logger)
        logger.log("Selected title translation display mode \(mode.rawValue)", category: .ai)
    }

    func setTitleFont(_ font: ReadingFontChoice, logger: AppLogger) {
        titleFont = font
        persist(logger: logger)
        logger.log("Selected title font \(font.rawValue)", category: .storage)
    }

    func setBodyFont(_ font: ReadingFontChoice, logger: AppLogger) {
        bodyFont = font
        persist(logger: logger)
        logger.log("Selected body font \(font.rawValue)", category: .storage)
    }

    func setAutoSummaryEnabled(_ enabled: Bool, logger: AppLogger) {
        autoSummaryEnabled = enabled
        persist(logger: logger)
        logger.log("Set automatic summary to \(enabled)", category: .ai)
    }

    func setAutoTranslationEnabled(_ enabled: Bool, logger: AppLogger) {
        autoTranslationEnabled = enabled
        persist(logger: logger)
        logger.log("Set automatic translation to \(enabled)", category: .ai)
    }

    func persist(logger: AppLogger) {
        do {
            repairDefaultProviderIfNeeded()
            let data = try JSONEncoder().encode(
                AIWorkspaceSettings(
                    providers: aiProviders,
                    defaultProviderID: defaultProviderID,
                    outputLanguage: aiOutputLanguage,
                    translationDisplayMode: translationDisplayMode,
                    titleTranslationDisplayMode: titleTranslationDisplayMode,
                    titleFont: titleFont,
                    bodyFont: bodyFont,
                    autoSummaryEnabled: autoSummaryEnabled,
                    autoTranslationEnabled: autoTranslationEnabled
                )
            )
            defaults.set(data, forKey: configurationKey)
            logger.log("Persisted AI workspace: \(workspaceSummary)", category: .storage)
        } catch {
            logger.log("Failed to persist AI configuration: \(error.localizedDescription)", category: .storage)
        }
    }

    private func repairDefaultProviderIfNeeded() {
        if let defaultProviderID, aiProviders.contains(where: { $0.id == defaultProviderID }) {
            return
        }
        defaultProviderID = aiProviders.first?.id
    }

    func fetchModelIdentifiers(for provider: AIProviderConfiguration, logger: AppLogger) async throws -> [String] {
        if provider.usesAppleIntelligence {
            return try appleIntelligenceModels()
        }
        let candidates = resolvedModelListURLs(for: provider)
        guard !candidates.isEmpty else {
            throw AIServiceError.invalidEndpoint
        }

        let headers = (try? parseHeaders(provider.headersJSON)) ?? [:]
        var lastError: Error?

        for url in candidates {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: 30)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }

            let startedAt = logger.logRequestStart(method: "GET", url: url, context: "ai.models", bodyBytes: nil)
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                logger.logResponse(method: "GET", url: url, context: "ai.models", startedAt: startedAt, response: response, dataSize: data.count)
                if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                    let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if http.statusCode == 401, headers.isEmpty {
                        lastError = AIServiceError.missingAPIKey
                        logger.log("Model list request is unauthorized and no headers are configured", category: .network)
                        continue
                    }
                    lastError = AIServiceError.badResponse(statusCode: http.statusCode, message: message)
                    logger.log("Model list request failed with status \(http.statusCode) at \(url.absoluteString)", category: .network)
                    continue
                }
                let list = scrubModelList(from: data)
                if !list.isEmpty {
                    logger.log("Fetched \(list.count) model identifiers for \(provider.displayName) from \(url.absoluteString)", category: .ai)
                    return list
                }
                logger.log("Model list endpoint returned zero models at \(url.absoluteString)", category: .network)
            } catch {
                lastError = error
                logger.log("Failed to fetch model list from \(url.absoluteString): \(error.localizedDescription)", category: .network)
            }
        }

        throw lastError ?? AIServiceError.emptyResponse
    }

    private var workspaceSummary: String {
        let providerSummary = aiProviders.map { provider in
            let marker = defaultProviderID == provider.id ? "*" : ""
            return "\(marker)\(provider.providerName)[\(provider.id.uuidString.prefix(8))]"
        }.joined(separator: ", ")
        let defaultIdentifier = defaultProviderID.map { String($0.uuidString.prefix(8)) } ?? "none"
        return "providers=\(aiProviders.count) [\(providerSummary)], default=\(defaultIdentifier), autoSummary=\(autoSummaryEnabled), autoTranslation=\(autoTranslationEnabled), language=\(aiOutputLanguage.rawValue), display=\(translationDisplayMode.rawValue), titleDisplay=\(titleTranslationDisplayMode.rawValue), titleFont=\(titleFont.rawValue), bodyFont=\(bodyFont.rawValue)"
    }

    private func normalizeProvider(_ provider: AIProviderConfiguration) -> AIProviderConfiguration {
        var provider = provider
        if provider.usesAppleIntelligence {
            provider.preset = .appleIntelligence
            provider.providerName = provider.providerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Apple Intelligence" : provider.providerName
            provider.endpoint = ProviderPreset.appleIntelligence.defaultEndpoint
            provider.headersJSON = ""
            provider.bodyFieldsJSON = ""
            provider.modelListEndpoint = ""
            return provider
        }
        provider = migrateLegacyAPIKeyIfNeeded(provider)
        if let inferredFormat = AIResponseFormat.inferredFormat(from: provider.endpoint) {
            provider.responseFormat = inferredFormat
        }
        if provider.modelListEndpoint.contains("$INFERENCE_ENDPOINT$") {
            provider.modelListEndpoint = ""
        }
        return provider
    }

    private func migrateLegacyAPIKeyIfNeeded(_ provider: AIProviderConfiguration) -> AIProviderConfiguration {
        var provider = provider
        let legacyAPIKey = provider.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !legacyAPIKey.isEmpty else { return provider }

        var headers = (try? parseHeaders(provider.headersJSON)) ?? [:]
        if headers["Authorization"] == nil {
            headers["Authorization"] = "Bearer \(legacyAPIKey)"
            if let data = try? JSONSerialization.data(withJSONObject: headers, options: [.prettyPrinted]),
               let string = String(data: data, encoding: .utf8) {
                provider.headersJSON = string
            }
        }
        provider.apiKey = ""
        return provider
    }

    private func resolvedModelListURLs(for provider: AIProviderConfiguration) -> [URL] {
        let endpoint = provider.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpoint.isEmpty, let baseURL = URL(string: endpoint) else { return [] }

        let explicit = provider.modelListEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty {
            if let absolute = URL(string: explicit), absolute.scheme != nil {
                return [absolute.standardized.absoluteURL]
            }
            if let relative = URL(string: explicit, relativeTo: baseURL)?.standardized {
                return [relative.absoluteURL]
            }
        }
        return inferredModelListURLs(from: baseURL, format: provider.responseFormat)
    }

    private func inferredModelListURLs(from baseURL: URL, format: AIResponseFormat) -> [URL] {
        let path = baseURL.path
        let baseString = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var candidates: [String] = []

        switch format {
        case .chatCompletions:
            if path.hasSuffix("/chat/completions") {
                candidates.append(baseString.replacingOccurrences(of: "/chat/completions", with: "/models"))
                candidates.append(baseString.replacingOccurrences(of: "/chat/completions", with: ""))
            }
        case .responses:
            if path.hasSuffix("/responses") {
                candidates.append(baseString.replacingOccurrences(of: "/responses", with: "/models"))
                candidates.append(baseString.replacingOccurrences(of: "/responses", with: ""))
            }
        }

        candidates.append("\(baseString)/models")
        return candidates.compactMap { URL(string: $0)?.standardized.absoluteURL }.uniqued()
    }

    private func parseHeaders(_ text: String) throws -> [String: String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [:] }
        let data = Data(trimmed.utf8)
        let json = try JSONSerialization.jsonObject(with: data)
        if let value = json as? [String: String] {
            return value
        }
        guard let dictionary = json as? [String: Any] else { return [:] }
        var output: [String: String] = [:]
        for (key, value) in dictionary {
            switch value {
            case let string as String:
                output[key] = string
            case let number as NSNumber:
                output[key] = number.stringValue
            case let bool as Bool:
                output[key] = bool ? "true" : "false"
            default:
                if JSONSerialization.isValidJSONObject(value),
                   let nestedData = try? JSONSerialization.data(withJSONObject: value),
                   let nestedString = String(data: nestedData, encoding: .utf8) {
                    output[key] = nestedString
                } else {
                    output[key] = String(describing: value)
                }
            }
        }
        return output
    }

    private func scrubModelList(from data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let dict = json as? [String: Any] {
            if let array = dict["data"] as? [[String: Any]] {
                return array.compactMap { $0["id"] as? String }.sorted()
            }
            if let array = dict["models"] as? [[String: Any]] {
                return array.compactMap { ($0["id"] as? String) ?? ($0["name"] as? String) ?? ($0["model"] as? String) }.sorted()
            }
            if let array = dict["items"] as? [[String: Any]] {
                return array.compactMap { ($0["id"] as? String) ?? ($0["name"] as? String) }.sorted()
            }
        }
        if let array = json as? [[String: Any]] {
            return array.compactMap { ($0["id"] as? String) ?? ($0["name"] as? String) }.sorted()
        }
        if let array = json as? [String] {
            return array.sorted()
        }
        return []
    }

    private func ensureBuiltInProviders() {
        guard !aiProviders.contains(where: \.usesAppleIntelligence) else { return }
        aiProviders.insert(Self.appleIntelligenceProviderTemplate(), at: 0)
    }

    private static func appleIntelligenceProviderTemplate() -> AIProviderConfiguration {
        var provider = AIProviderConfiguration.default
        provider.preset = .appleIntelligence
        provider.providerName = "Apple Intelligence"
        provider.endpoint = ProviderPreset.appleIntelligence.defaultEndpoint
        provider.modelIdentifier = "apple.system"
        provider.summaryPrompt = "Summarize the following article. Keep the structure clear, concise, and useful for later reading."
        provider.translationPrompt = "Translate the following article carefully while preserving structure and formatting."
        return provider
    }

    private func appleIntelligenceModels() throws -> [String] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = FoundationModels.SystemLanguageModel.default
            switch model.availability {
            case .available:
                return ["apple.system"]
            case .unavailable(let reason):
                let message: String
                switch reason {
                case .deviceNotEligible:
                    message = "This device does not support Apple Intelligence."
                case .appleIntelligenceNotEnabled:
                    message = "Apple Intelligence is not enabled on this device."
                case .modelNotReady:
                    message = "Apple Intelligence is still preparing its on-device model."
                @unknown default:
                    message = "Apple Intelligence is unavailable on this device."
                }
                throw AIServiceError.appleIntelligenceUnavailable(message)
            }
        }
        #endif
        throw AIServiceError.appleIntelligenceUnavailable("Apple Intelligence is unavailable on this device.")
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
