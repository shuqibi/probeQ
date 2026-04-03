import Foundation

struct ChatSession: Identifiable, Codable {
    var id: UUID
    var date: Date
    var title: String
    var messages: [Message]
}

class HistoryManager: ObservableObject {
    static let shared = HistoryManager()
    private let historyKey = "probeQ_history_sessions"
    
    @Published var sessions: [ChatSession] = []
    
    private init() {
        loadHistory()
    }
    
    func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: historyKey),
           let saved = try? JSONDecoder().decode([ChatSession].self, from: data) {
            self.sessions = saved
        }
    }
    
    func saveSession(id: UUID, messages: [Message]) {
        let limit = SettingsManager.shared.historyLimit
        if limit == 0 {
            // If the user changed the limit to 0 while a chat was open, enforce it immediately
            clearHistory()
            return
        }
        
        let title = HistoryManager.generateTitle(from: messages)
        let session = ChatSession(id: id, date: Date(), title: title, messages: messages)
        
        if let index = sessions.firstIndex(where: { $0.id == id }) {
            // Update existing session
            sessions[index] = session
        } else {
            // Insert new session at top
            sessions.insert(session, at: 0)
        }
        
        enforceLimit()
        persist()
    }
    
    func deleteSession(id: UUID) {
        sessions.removeAll(where: { $0.id == id })
        persist()
    }
    
    func clearHistory() {
        sessions.removeAll()
        persist()
    }
    
    func enforceLimit() {
        let limit = SettingsManager.shared.historyLimit
        if limit == 0 {
            sessions.removeAll()
        } else if sessions.count > limit {
            sessions = Array(sessions.prefix(limit))
        }
    }
    
    private func persist() {
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }
    
    static func generateTitle(from messages: [Message]) -> String {
        guard let firstUserMessage = messages.first(where: { $0.role == "user" }) else {
            return "Empty Chat"
        }
        let text = firstUserMessage.parts.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count > 30 {
            return String(text.prefix(27)) + "..."
        }
        return text
    }
}
