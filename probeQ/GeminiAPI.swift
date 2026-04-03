import Foundation

class GeminiAPI {
    // A shared instance for convenience
    static let shared = GeminiAPI()
    
    func generateContent(messages: [[String: Any]], apiKey: String, modelName: String = "gemini-2.5-flash") async throws -> String {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "GeminiAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Please enter your Gemini API Key in the GUI."])
        }
        
        // This simple API endpoint works flawlessly for the chat format you need without pulling huge dependencies like Firebase
        let endpointString = "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent?key=\(apiKey)"
        guard let url = URL(string: endpointString) else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Match the correct JSON payload for API v1beta Gemini models
        let body: [String: Any] = [
            "contents": messages,
            "systemInstruction": [
                "parts": [
                    ["text": "You are a helpful, extremely concise, fast macOS AI assistant. Prefer direct answers. Ignore markdown bloat as much as possible unless necessary for readability."]
                ]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if httpResponse.statusCode != 200 {
            let errorString = String(data: data, encoding: .utf8) ?? "Unknown Error"
            print("API Error: \(errorString)")
            throw NSError(domain: "GeminiAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorString])
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
        
        throw NSError(domain: "GeminiAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse generation result from Google AI servers."])
    }
}

// MARK: - Dynamic Model Fetching
struct GeminiModelInfo: Codable, Identifiable, Hashable {
    let name: String
    let displayName: String
    var id: String { name }
}

struct ModelResponse: Codable {
    let models: [GeminiModelInfo]
}

extension GeminiAPI {
    func getAvailableModels(apiKey: String) async throws -> [GeminiModelInfo] {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        
        let urlStr = "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)&pageSize=200"
        guard let url = URL(string: urlStr) else { throw URLError(.badURL) }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        
        let res = try JSONDecoder().decode(ModelResponse.self, from: data)
        
        return res.models.filter { model in
            let lower = model.name.lowercased()
            // Strictly exclude embedding/vision models so dropdown remains clean
            return lower.contains("gemini") && !lower.contains("vision") && !lower.contains("embedding")
        }.map { model in
            // Strip the "models/" prefix so it maps directly to our prompt generator natively
            let strippedName = model.name.replacingOccurrences(of: "models/", with: "")
            return GeminiModelInfo(name: strippedName, displayName: model.displayName)
        }.sorted { $0.name > $1.name } // Naturally sorts newer versions higher
    }
}
