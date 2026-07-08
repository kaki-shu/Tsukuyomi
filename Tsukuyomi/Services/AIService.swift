import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum AIAction {
    case summarize
    case translate

    var title: String {
        switch self {
        case .summarize:
            return "summary"
        case .translate:
            return "translation"
        }
    }
}

enum AIServiceError: LocalizedError {
    case missingDefaultProvider
    case missingAPIKey
    case invalidEndpoint
    case invalidJSONField(name: String)
    case badResponse(statusCode: Int, message: String)
    case emptyResponse
    case appleIntelligenceUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingDefaultProvider:
            return "Please choose a default AI provider first."
        case .missingAPIKey:
            return "Please configure Headers JSON first."
        case .invalidEndpoint:
            return "The provider endpoint is invalid."
        case .invalidJSONField(let name):
            return "\(name) is not valid JSON."
        case .badResponse(let statusCode, let message):
            return message.isEmpty ? "The AI service returned HTTP \(statusCode)." : "HTTP \(statusCode): \(message)"
        case .emptyResponse:
            return "The model returned an empty response."
        case .appleIntelligenceUnavailable(let reason):
            return reason
        }
    }
}

struct AIService {
    let configuration: AIProviderConfiguration
    let logger: AppLogger

    func run(action: AIAction, article: FeedArticle, outputLanguage: AIOutputLanguage) async throws -> String {
        if configuration.usesAppleIntelligence {
            return try await performAppleIntelligenceRequest(
                action: action,
                article: article,
                outputLanguage: outputLanguage
            )
        }
        let prompt = prompt(for: action, basePrompt: basePrompt(for: action), outputLanguage: outputLanguage)
        let protectedMarkdown: TranslationImagePreserver.ProtectedMarkdown?
        if case .translate = action {
            protectedMarkdown = TranslationImagePreserver.protect(article.bodyText)
        } else {
            protectedMarkdown = nil
        }
        let content = articleContent(for: article, protectedMarkdown: protectedMarkdown)
        let output = try await performRequest(
            action: action,
            prompt: prompt,
            content: content
        )
        if let protectedMarkdown {
            return TranslationImagePreserver.restoreImages(in: output, from: protectedMarkdown)
        }
        return output
    }

    func translateTitle(articleTitle: String, feedTitle: String, outputLanguage: AIOutputLanguage) async throws -> String {
        if configuration.usesAppleIntelligence {
            return try await runAppleIntelligence(prompt: """
            Return only the translated title text in \(outputLanguage.promptLabel).
            Do not add quotation marks, bullets, labels, or explanations.

            Feed:
            \(feedTitle)

            Title:
            \(articleTitle)
            """)
        }
        let prompt = """
        Return only the translated title text in \(outputLanguage.promptLabel).
        Do not add quotation marks, bullets, labels, or explanations.
        """
        let content = """
        Feed:
        \(feedTitle)

        Title:
        \(articleTitle)
        """
        return try await performRequest(action: .translate, prompt: prompt, content: content)
    }

    func streamTranslation(
        article: FeedArticle,
        outputLanguage: AIOutputLanguage,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        if configuration.usesAppleIntelligence {
            return try await streamAppleIntelligenceTranslation(
                article: article,
                outputLanguage: outputLanguage,
                onDelta: onDelta
            )
        }
        guard let baseURL = URL(string: configuration.endpoint) else {
            throw AIServiceError.invalidEndpoint
        }

        let prompt = prompt(for: .translate, basePrompt: basePrompt(for: .translate), outputLanguage: outputLanguage)
        let protectedMarkdown = TranslationImagePreserver.protect(article.bodyText)
        let content = articleContent(for: article, protectedMarkdown: protectedMarkdown)
        let requestURL = try makeRequestURL(from: baseURL)
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureRequestHeaders(&request)
        request.httpBody = try makeBody(prompt: prompt, content: content, stream: true)
        logger.log("Preparing streaming translation using provider \(configuration.providerName) [\(configuration.id.uuidString.prefix(8))] for '\(article.title)'", category: .ai)
        let requestStartedAt = logger.logRequestStart(
            method: request.httpMethod ?? "POST",
            url: requestURL,
            context: "ai.translation.stream",
            bodyBytes: request.httpBody?.count
        )

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let http = response as? HTTPURLResponse {
            logger.log("AI response status \(http.statusCode) for translation stream", category: .network)
            guard (200...299).contains(http.statusCode) else {
                let data = try await collectData(from: bytes)
                throw AIServiceError.badResponse(
                    statusCode: http.statusCode,
                    message: decodeErrorMessage(from: data)
                )
            }
        }

        var output = ""
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { continue }
            let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            if payload == "[DONE]" {
                break
            }
            guard let data = payload.data(using: .utf8),
                  let delta = decodeStreamDelta(from: data) else { continue }
            output += delta
            await onDelta(TranslationImagePreserver.restoreImages(in: output, from: protectedMarkdown))
        }
        logger.logResponse(
            method: request.httpMethod ?? "POST",
            url: requestURL,
            context: "ai.translation.stream",
            startedAt: requestStartedAt,
            response: response,
            dataSize: output.utf8.count
        )
        let trimmed = TranslationImagePreserver.restoreImages(in: output, from: protectedMarkdown)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIServiceError.emptyResponse }
        logger.log("Received streaming translation output with \(trimmed.count) characters", category: .ai)
        return trimmed
    }

    private func performAppleIntelligenceRequest(
        action: AIAction,
        article: FeedArticle,
        outputLanguage: AIOutputLanguage
    ) async throws -> String {
        let protectedMarkdown: TranslationImagePreserver.ProtectedMarkdown?
        if case .translate = action {
            protectedMarkdown = TranslationImagePreserver.protect(article.bodyText)
        } else {
            protectedMarkdown = nil
        }
        let prompt = """
        \(prompt(for: action, basePrompt: basePrompt(for: action), outputLanguage: outputLanguage))

        Article Title:
        \(article.title)

        Feed:
        \(article.feedTitle)

        Content:
        \(protectedMarkdown?.markdown ?? article.bodyText)
        """
        let output = try await runAppleIntelligence(prompt: prompt)
        if let protectedMarkdown {
            return TranslationImagePreserver.restoreImages(in: output, from: protectedMarkdown)
        }
        return output
    }

    private func runAppleIntelligence(prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                throw AIServiceError.appleIntelligenceUnavailable(appleIntelligenceReason(for: model.availability))
            }
            let session = LanguageModelSession(model: model)
            logger.log("Preparing local Apple Intelligence request", category: .ai)
            let response = try await session.respond(to: prompt)
            let output = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !output.isEmpty else { throw AIServiceError.emptyResponse }
            logger.log("Received Apple Intelligence output with \(output.count) characters", category: .ai)
            return output
        }
        #endif
        throw AIServiceError.appleIntelligenceUnavailable("Apple Intelligence is unavailable on this device.")
    }

    private func streamAppleIntelligenceTranslation(
        article: FeedArticle,
        outputLanguage: AIOutputLanguage,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let model = SystemLanguageModel.default
            guard model.isAvailable else {
                throw AIServiceError.appleIntelligenceUnavailable(appleIntelligenceReason(for: model.availability))
            }
            let session = LanguageModelSession(model: model)
            let protectedMarkdown = TranslationImagePreserver.protect(article.bodyText)
            let prompt = """
            \(prompt(for: .translate, basePrompt: basePrompt(for: .translate), outputLanguage: outputLanguage))

            Article Title:
            \(article.title)

            Feed:
            \(article.feedTitle)

            Content:
            \(protectedMarkdown.markdown)
            """
            var latest = ""
            for try await snapshot in session.streamResponse(to: prompt) {
                latest = snapshot.content
                await onDelta(TranslationImagePreserver.restoreImages(in: latest, from: protectedMarkdown))
            }
            let restored = TranslationImagePreserver.restoreImages(in: latest, from: protectedMarkdown)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !restored.isEmpty else { throw AIServiceError.emptyResponse }
            return restored
        }
        #endif
        throw AIServiceError.appleIntelligenceUnavailable("Apple Intelligence is unavailable on this device.")
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private func appleIntelligenceReason(for availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            return "Apple Intelligence is available."
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This device does not support Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence is not enabled on this device."
            case .modelNotReady:
                return "Apple Intelligence is still preparing its on-device model."
            @unknown default:
                return "Apple Intelligence is unavailable on this device."
            }
        }
    }
    #endif

    private func prompt(for action: AIAction, basePrompt: String, outputLanguage: AIOutputLanguage) -> String {
        let language = outputLanguage.promptLabel
        let guardrails: String
        switch action {
        case .summarize:
            guardrails = """
            Return Markdown only.
            Write the answer in \(language).
            Keep headings, bullets, and emphasis lightweight.
            Do not wrap the answer in code fences.
            """
        case .translate:
            guardrails = """
            Return Markdown only.
            Translate the readable text into \(language).
            Preserve Markdown structure, links, headings, lists, and emphasis.
            Preserve image placeholders such as {{TSUKUYOMI_IMAGE_1}} exactly where they appear.
            Do not translate URLs, image placeholders, image references, or code spans.
            Do not leave readable source-language sentences untranslated unless they are names, quoted terms, code, URLs, or image references.
            """
        }

        let trimmedPrompt = basePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPrompt.isEmpty {
            return guardrails
        }
        return "\(trimmedPrompt)\n\n\(guardrails)"
    }

    private func performRequest(action: AIAction, prompt: String, content: String) async throws -> String {
        guard let baseURL = URL(string: configuration.endpoint) else {
            throw AIServiceError.invalidEndpoint
        }

        let requestURL = try makeRequestURL(from: baseURL)
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureRequestHeaders(&request)
        request.httpBody = try makeBody(prompt: prompt, content: content, stream: false)
        logger.log("Preparing \(action.title) request using provider \(configuration.providerName) [\(configuration.id.uuidString.prefix(8))]", category: .ai)
        let requestStartedAt = logger.logRequestStart(
            method: request.httpMethod ?? "POST",
            url: requestURL,
            context: "ai.\(action.title)",
            bodyBytes: request.httpBody?.count
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        logger.logResponse(
            method: request.httpMethod ?? "POST",
            url: requestURL,
            context: "ai.\(action.title)",
            startedAt: requestStartedAt,
            response: response,
            dataSize: data.count
        )
        if let http = response as? HTTPURLResponse {
            logger.log("AI response status \(http.statusCode) for \(action.title)", category: .network)
            guard (200...299).contains(http.statusCode) else {
                throw AIServiceError.badResponse(
                    statusCode: http.statusCode,
                    message: decodeErrorMessage(from: data)
                )
            }
        }

        let output = try decodeResponse(data: data)
        logger.log("Received \(action.title) output with \(output.count) characters", category: .ai)
        return output
    }

    private func articleContent(for article: FeedArticle, protectedMarkdown: TranslationImagePreserver.ProtectedMarkdown? = nil) -> String {
        """
        Article Title:
        \(article.title)

        Feed:
        \(article.feedTitle)

        Content:
        \(protectedMarkdown?.markdown ?? article.bodyText)
        """
    }

    private func basePrompt(for action: AIAction) -> String {
        switch action {
        case .summarize:
            configuration.summaryPrompt
        case .translate:
            configuration.translationPrompt
        }
    }

    private func configureRequestHeaders(_ request: inout URLRequest) throws {
        let headers = try parseDictionary(from: configuration.headersJSON, name: "Headers JSON")
        if headers.isEmpty {
            throw AIServiceError.missingAPIKey
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
    }

    private func makeBody(prompt: String, content: String, stream: Bool) throws -> Data {
        let extra = try parseAnyJSON(from: configuration.bodyFieldsJSON, name: "Body Fields JSON")
        let payload: [String: Any]
        switch configuration.responseFormat {
        case .chatCompletions:
            var body: [String: Any] = [
                "model": configuration.modelIdentifier,
                "stream": stream,
                "messages": [
                    ["role": "system", "content": prompt],
                    ["role": "user", "content": content]
                ]
            ]
            if let extra {
                body.merge(extra) { _, new in new }
            }
            payload = body
        case .responses:
            var body: [String: Any] = [
                "model": configuration.modelIdentifier,
                "stream": stream,
                "input": [
                    ["role": "system", "content": [["type": "input_text", "text": prompt]]],
                    ["role": "user", "content": [["type": "input_text", "text": content]]]
                ]
            ]
            if let extra {
                body.merge(extra) { _, new in new }
            }
            payload = body
        }
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
    }

    private func collectData(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
        }
        return data
    }

    private func makeRequestURL(from baseURL: URL) throws -> URL {
        let normalized = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch configuration.responseFormat {
        case .chatCompletions:
            if normalized.hasSuffix("/chat/completions") {
                return baseURL
            }
            return baseURL.appending(path: "chat/completions")
        case .responses:
            if normalized.hasSuffix("/responses") {
                return baseURL
            }
            return baseURL.appending(path: "responses")
        }
    }

    private func decodeResponse(data: Data) throws -> String {
        if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let output = ((object["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String,
               !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return output
            }
            if let output = ((object["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? [[String: Any]] {
                let fragments = output
                    .compactMap { $0["text"] as? String }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !fragments.isEmpty {
                    return fragments
                }
            }
            if let text = object["output_text"] as? String,
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
            if let output = object["output"] as? [[String: Any]] {
                let fragments = output
                    .flatMap { $0["content"] as? [[String: Any]] ?? [] }
                    .compactMap { $0["text"] as? String }
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !fragments.isEmpty {
                    return fragments
                }
            }
        }
        throw AIServiceError.emptyResponse
    }

    private func decodeErrorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        if let error = object["error"] as? [String: Any] {
            return (error["message"] as? String) ?? ""
        }
        if let message = object["message"] as? String {
            return message
        }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func decodeStreamDelta(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let choices = object["choices"] as? [[String: Any]],
           let delta = choices.first?["delta"] as? [String: Any] {
            if let content = delta["content"] as? String {
                return content
            }
            if let fragments = delta["content"] as? [[String: Any]] {
                return fragments.compactMap { $0["text"] as? String }.joined()
            }
        }
        if let type = object["type"] as? String,
           type == "response.output_text.delta",
           let delta = object["delta"] as? String {
            return delta
        }
        if let delta = object["output_text"] as? String {
            return delta
        }
        return nil
    }

    private func parseDictionary(from text: String, name: String) throws -> [String: String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [:] }
        let data = Data(trimmed.utf8)
        let json = try JSONSerialization.jsonObject(with: data)
        if let value = json as? [String: String] {
            return value
        }
        guard let dictionary = json as? [String: Any] else {
            throw AIServiceError.invalidJSONField(name: name)
        }
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

    private func parseAnyJSON(from text: String, name: String) throws -> [String: Any]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let data = Data(trimmed.utf8)
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AIServiceError.invalidJSONField(name: name)
        }
        return value
    }
}
