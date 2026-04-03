import SwiftUI

struct Message: Identifiable, Codable {
    var id = UUID()
    let role: String   // "user" or "model"
    let parts: String
}

@MainActor
class ChatViewModel: ObservableObject {
    var sessionId: UUID
    @Published var messages: [Message] = []
    @Published var isWaitingForResponse = false
    @Published var inputText = ""
    @Published var errorMessage: String? = nil
    
    init(sessionId: UUID? = nil, initialMessages: [Message] = []) {
        self.sessionId = sessionId ?? UUID()
        self.messages = initialMessages
    }
    
    // Converts Message array into Gemini API format
    private var geminiHistory: [[String: Any]] {
        messages.map { msg in
            ["role": msg.role, "parts": [["text": msg.parts]]]
        }
    }
    
    func sendMessage(_ text: String, prefixPrompt: String? = nil) {
        let actualText = prefixPrompt != nil ? "\(prefixPrompt!):\n\n\(text)" : text
        messages.append(Message(role: "user", parts: actualText))
        inputText = ""
        fetchAIResponse()
    }
    
    private func fetchAIResponse() {
        guard !messages.isEmpty else { return }
        isWaitingForResponse = true
        errorMessage = nil
        
        let settings = SettingsManager.shared
        let currentHistory = geminiHistory
        
        Task {
            do {
                guard !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    errorMessage = "Please enter your Gemini API Key in Settings."
                    isWaitingForResponse = false
                    return
                }
                
                let responseText = try await GeminiAPI.shared.generateContent(
                    messages: currentHistory,
                    apiKey: settings.apiKey,
                    modelName: settings.modelName
                )
                
                messages.append(Message(role: "model", parts: responseText))
                isWaitingForResponse = false
            } catch {
                errorMessage = error.localizedDescription
                isWaitingForResponse = false
            }
        }
    }
    
    func clearHistory() {
        messages.removeAll()
        errorMessage = nil
        inputText = ""
    }
    
    func onClipboardGrab() {
        if let text = ClipboardManager.getText(), !text.isEmpty {
            inputText = text
        } else {
            errorMessage = "Clipboard is empty or contains no readable text."
        }
    }
    
    func onOCRGrab(onComplete: @escaping () -> Void = {}) {
        Task {
            isWaitingForResponse = true
            NSApp.hide(nil)
            
            var success = false
            do {
                let extractedText = try await OCRManager.shared.captureAndRecognizeText()
                if extractedText.isEmpty {
                    errorMessage = "No text found in screen capture."
                } else {
                    inputText = extractedText
                    success = true
                }
            } catch {
                // User pressed ESC or capture failed — silently abort, don't pop window
            }
            
            isWaitingForResponse = false
            
            if success {
                NSApp.unhide(nil)
                DispatchQueue.main.async {
                    onComplete()
                }
            }
        }
    }
    
    func submitPrompt(type: String) {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let settings = SettingsManager.shared
        let promptText: String
        switch type {
        case "Translate": promptText = settings.translatePrompt
        case "Polish":    promptText = settings.polishPrompt
        case "Search":    promptText = settings.searchPrompt
        default:          promptText = type
        }
        sendMessage(inputText, prefixPrompt: promptText)
    }
}
