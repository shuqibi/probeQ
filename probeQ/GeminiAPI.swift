import Foundation

class LLMManager {
    static let shared = LLMManager()
    
    // Helper to get the base URL based on provider
    private func getBaseURL(provider: String, customURL: String) -> String {
        switch provider {
        case "deepseek": return "https://api.deepseek.com"
        case "zhipu": return "https://open.bigmodel.cn/api/paas/v4"
        case "qwen": return "https://dashscope.aliyuncs.com/compatible-mode"
        case "openai": return "https://api.openai.com"
        case "moonshot": return "https://api.moonshot.cn"
        case "groq": return "https://api.groq.com/openai"
        case "grok": return "https://api.x.ai"
        case "custom": return customURL.trimmingCharacters(in: .init(charactersIn: "/"))
        // gemini is handled separately, but fallback here
        default: return ""
        }
    }
    
    func generateContent(messages: [Message], provider: String, customURL: String, apiKey: String, modelName: String = "gemini-2.5-flash", systemPrompt: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "LLMManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Please enter your API Key in the GUI."])
        }
        
        if provider == "gemini" {
            return try await generateGemini(messages: messages, apiKey: apiKey, modelName: modelName, systemPrompt: systemPrompt)
        } else {
            let baseURL = getBaseURL(provider: provider, customURL: customURL)
            guard !baseURL.isEmpty else { throw URLError(.badURL) }
            return try await generateOpenAI(messages: messages, baseURL: baseURL, apiKey: apiKey, modelName: modelName, systemPrompt: systemPrompt)
        }
    }
    
    // MARK: - Gemini Implementation
    private func generateGemini(messages: [Message], apiKey: String, modelName: String, systemPrompt: String) async throws -> String {
        let endpointString = "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent?key=\(apiKey)"
        guard let url = URL(string: endpointString) else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let geminiHistory = messages.map { msg in
            ["role": msg.role, "parts": [["text": msg.parts]]]
        }
        
        let body: [String: Any] = [
            "contents": geminiHistory,
            "systemInstruction": [ "parts": [ ["text": systemPrompt] ] ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        
        if httpResponse.statusCode != 200 {
            let errorString = String(data: data, encoding: .utf8) ?? "Unknown Error"
            throw NSError(domain: "LLMManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorString])
        }
        
        let result = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        if let candidates = result?["candidates"] as? [[String: Any]],
           let firstCandidate = candidates.first,
           let content = firstCandidate["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]],
           let firstPart = parts.first,
           let text = firstPart["text"] as? String {
            return text
        }
        throw NSError(domain: "LLMManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse generation result from Google AI."])
    }
    
    // MARK: - OpenAI-Compatible Implementation
    private func generateOpenAI(messages: [Message], baseURL: String, apiKey: String, modelName: String, systemPrompt: String) async throws -> String {
        let endpointString = "\(baseURL)/v1/chat/completions"
        guard let url = URL(string: endpointString) else { throw URLError(.badURL) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        var openAIMessages: [[String: Any]] = []
        openAIMessages.append(["role": "system", "content": systemPrompt])
        
        for msg in messages {
            let role = msg.role == "model" ? "assistant" : "user"
            openAIMessages.append(["role": role, "content": msg.parts])
        }
        
        let body: [String: Any] = [
            "model": modelName == "" ? "gpt-4o" : modelName,
            "messages": openAIMessages
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        
        if httpResponse.statusCode != 200 {
            let errorString = String(data: data, encoding: .utf8) ?? "Unknown Error"
            throw NSError(domain: "LLMManager", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorString])
        }
        
        let result = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        if let choices = result?["choices"] as? [[String: Any]],
           let firstChoice = choices.first,
           let message = firstChoice["message"] as? [String: Any],
           let content = message["content"] as? String {
            return content
        }
        throw NSError(domain: "LLMManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse OpenAI-compatible response."])
    }
}

// MARK: - Dynamic Model Fetching

struct LLMModelInfo: Codable, Identifiable, Hashable {
    let name: String
    let displayName: String
    var id: String { name }
}

struct GeminiModelResponse: Codable {
    struct GModel: Codable {
        let name: String
        let displayName: String
    }
    let models: [GModel]
}

struct OpenAIModelResponse: Codable {
    struct OModel: Codable {
        let id: String
    }
    let data: [OModel]
}

extension LLMManager {
    private func getFallbackModels(for provider: String) -> [LLMModelInfo] {
        switch provider {
        case "deepseek":
            return [
                LLMModelInfo(name: "deepseek-chat", displayName: "DeepSeek Chat (V3)"),
                LLMModelInfo(name: "deepseek-reasoner", displayName: "DeepSeek Reasoner (R1)")
            ]
        case "moonshot":
            return [
                LLMModelInfo(name: "moonshot-v1-8k", displayName: "Moonshot v1 8K"),
                LLMModelInfo(name: "moonshot-v1-32k", displayName: "Moonshot v1 32K"),
                LLMModelInfo(name: "moonshot-v1-128k", displayName: "Moonshot v1 128K")
            ]
        case "zhipu":
            return [
                LLMModelInfo(name: "glm-4-plus", displayName: "GLM-4 Plus"),
                LLMModelInfo(name: "glm-4-0520", displayName: "GLM-4 0520"),
                LLMModelInfo(name: "glm-4-air", displayName: "GLM-4 Air"),
                LLMModelInfo(name: "glm-4-flash", displayName: "GLM-4 Flash"),
                LLMModelInfo(name: "glm-4v", displayName: "GLM-4V")
            ]
        case "qwen":
            return [
                LLMModelInfo(name: "qwen-max", displayName: "Qwen Max"),
                LLMModelInfo(name: "qwen-plus", displayName: "Qwen Plus"),
                LLMModelInfo(name: "qwen-turbo", displayName: "Qwen Turbo")
            ]
        case "openai":
            return [
                LLMModelInfo(name: "gpt-4o", displayName: "GPT-4o"),
                LLMModelInfo(name: "gpt-4o-mini", displayName: "GPT-4o Mini"),
                LLMModelInfo(name: "o1-preview", displayName: "o1 Preview"),
                LLMModelInfo(name: "o1-mini", displayName: "o1 Mini")
            ]
        case "groq":
            return [
                LLMModelInfo(name: "llama3-70b-8192", displayName: "Llama 3 70B"),
                LLMModelInfo(name: "llama3-8b-8192", displayName: "Llama 3 8B"),
                LLMModelInfo(name: "mixtral-8x7b-32768", displayName: "Mixtral 8x7B")
            ]
        case "grok":
            return [
                LLMModelInfo(name: "grok-beta", displayName: "Grok Beta"),
                LLMModelInfo(name: "grok-vision-beta", displayName: "Grok Vision Beta"),
                LLMModelInfo(name: "grok-2", displayName: "Grok 2")
            ]
        default:
            return []
        }
    }

    func getAvailableModels(provider: String, customURL: String, apiKey: String) async throws -> [LLMModelInfo] {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        
        if provider == "gemini" {
            let urlStr = "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)&pageSize=200"
            guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
                
                let res = try JSONDecoder().decode(GeminiModelResponse.self, from: data)
                return res.models.filter {
                    let lower = $0.name.lowercased()
                    return lower.contains("gemini") && !lower.contains("vision") && !lower.contains("embedding")
                }.map {
                    let strippedName = $0.name.replacingOccurrences(of: "models/", with: "")
                    return LLMModelInfo(name: strippedName, displayName: $0.displayName)
                }.sorted { $0.name > $1.name }
            } catch {
                return [LLMModelInfo(name: "gemini-2.5-flash", displayName: "Gemini 2.5 Flash"),
                        LLMModelInfo(name: "gemini-2.5-pro", displayName: "Gemini 2.5 Pro")]
            }
        } else {
            let baseURL = getBaseURL(provider: provider, customURL: customURL)
            let urlStr = "\(baseURL)/v1/models"
            guard let url = URL(string: urlStr) else { return getFallbackModels(for: provider) }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    return getFallbackModels(for: provider)
                }
                
                let res = try JSONDecoder().decode(OpenAIModelResponse.self, from: data)
                let parsedModels = res.data.map {
                    LLMModelInfo(name: $0.id, displayName: $0.id)
                }.sorted { $0.name < $1.name }
                
                if parsedModels.isEmpty { return getFallbackModels(for: provider) }
                return parsedModels
            } catch {
                return getFallbackModels(for: provider)
            }
        }
    }
}
