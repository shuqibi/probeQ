import Foundation
import AppKit

// MARK: - Shortcut Data Model

struct ShortcutBinding: Codable, Equatable {
    var keyCode: UInt16
    var modifierFlags: UInt  // NSEvent.ModifierFlags.rawValue
    
    var displayString: String {
        var parts: [String] = []
        let flags = NSEvent.ModifierFlags(rawValue: modifierFlags)
        if flags.contains(.control) { parts.append("⌃") }
        if flags.contains(.option) { parts.append("⌥") }
        if flags.contains(.shift) { parts.append("⇧") }
        if flags.contains(.command) { parts.append("⌘") }
        if let key = Self.keyCodeName(keyCode) {
            parts.append(key)
        }
        return parts.joined()
    }
    
    static func keyCodeName(_ code: UInt16) -> String? {
        let map: [UInt16: String] = [
            0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X",
            8:"C", 9:"V", 11:"B", 12:"Q", 13:"W", 14:"E", 15:"R",
            16:"Y", 17:"T", 18:"1", 19:"2", 20:"3", 21:"4", 22:"6",
            23:"5", 24:"=", 25:"9", 26:"7", 27:"-", 28:"8", 29:"0",
            30:"]", 31:"O", 32:"U", 33:"[", 34:"I", 35:"P", 37:"L",
            38:"J", 39:"'", 40:"K", 41:";", 42:"\\", 43:",", 44:"/",
            45:"N", 46:"M", 47:".", 48:"Tab", 49:"Space", 50:"`",
            51:"Delete", 53:"Esc",
            123:"←", 124:"→", 125:"↓", 126:"↑",
            122:"F1", 120:"F2", 99:"F3", 118:"F4", 96:"F5", 97:"F6",
            98:"F7", 100:"F8", 101:"F9", 109:"F10", 103:"F11", 111:"F12",
        ]
        return map[code]
    }
}

// MARK: - Settings Manager

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    @Published var apiProvider: String {
        didSet { UserDefaults.standard.set(apiProvider, forKey: "probeQ_apiProvider") }
    }
    
    @Published var customBaseURL: String {
        didSet { UserDefaults.standard.set(customBaseURL, forKey: "probeQ_customBaseURL") }
    }
    
    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: "probeQ_apiKey") }
    }
    
    @Published var modelName: String {
        didSet { UserDefaults.standard.set(modelName, forKey: "probeQ_modelName") }
    }
    
    // Per-provider memory helpers
    func getProviderAPIKey(_ provider: String) -> String {
        if let key = UserDefaults.standard.string(forKey: "probeQ_apiKey_\(provider)") { return key }
        return provider == apiProvider ? apiKey : ""
    }
    func setProviderAPIKey(_ key: String, for provider: String) {
        UserDefaults.standard.set(key, forKey: "probeQ_apiKey_\(provider)")
    }
    
    func getProviderModel(_ provider: String) -> String {
        if let model = UserDefaults.standard.string(forKey: "probeQ_modelName_\(provider)") { return model }
        return provider == apiProvider ? modelName : ""
    }
    func setProviderModel(_ model: String, for provider: String) {
        UserDefaults.standard.set(model, forKey: "probeQ_modelName_\(provider)")
    }
    
    func getProviderBaseURL(_ provider: String) -> String {
        if let url = UserDefaults.standard.string(forKey: "probeQ_customBaseURL_\(provider)") { return url }
        return provider == apiProvider ? customBaseURL : ""
    }
    func setProviderBaseURL(_ url: String, for provider: String) {
        UserDefaults.standard.set(url, forKey: "probeQ_customBaseURL_\(provider)")
    }
    
    @Published var historyLimit: Int {
        didSet {
            UserDefaults.standard.set(historyLimit, forKey: "probeQ_historyLimit")
            HistoryManager.shared.enforceLimit()
        }
    }
    
    @Published var translatePrompt: String {
        didSet { UserDefaults.standard.set(translatePrompt, forKey: "probeQ_translatePrompt") }
    }
    
    @Published var polishPrompt: String {
        didSet { UserDefaults.standard.set(polishPrompt, forKey: "probeQ_polishPrompt") }
    }
    
    @Published var searchPrompt: String {
        didSet { UserDefaults.standard.set(searchPrompt, forKey: "probeQ_searchPrompt") }
    }
    
    // Full keybinding shortcuts (any modifier + any key)
    @Published var ocrShortcut: ShortcutBinding? {
        didSet { saveBinding(ocrShortcut, forKey: "probeQ_ocrShortcut") }
    }
    @Published var translateShortcut: ShortcutBinding? {
        didSet { saveBinding(translateShortcut, forKey: "probeQ_translateShortcut") }
    }
    @Published var polishShortcut: ShortcutBinding? {
        didSet { saveBinding(polishShortcut, forKey: "probeQ_polishShortcut") }
    }
    @Published var searchShortcut: ShortcutBinding? {
        didSet { saveBinding(searchShortcut, forKey: "probeQ_searchShortcut") }
    }
    
    private init() {
        let oldKey = UserDefaults.standard.string(forKey: "geminiAPIKey")
        self.apiProvider = UserDefaults.standard.string(forKey: "probeQ_apiProvider") ?? "none"
        self.customBaseURL = UserDefaults.standard.string(forKey: "probeQ_customBaseURL") ?? ""
        self.apiKey = UserDefaults.standard.string(forKey: "probeQ_apiKey") ?? oldKey ?? ""
        self.modelName = UserDefaults.standard.string(forKey: "probeQ_modelName") ?? "gemini-2.5-flash"
        self.historyLimit = UserDefaults.standard.object(forKey: "probeQ_historyLimit") as? Int ?? 20
        self.translatePrompt = UserDefaults.standard.string(forKey: "probeQ_translatePrompt")
            ?? "Translate the following text to English (or if it is already English, translate it to Chinese). Be highly accurate."
        self.polishPrompt = UserDefaults.standard.string(forKey: "probeQ_polishPrompt")
            ?? "Polish the following text so it reads flawlessly, naturally, and professionally."
        self.searchPrompt = UserDefaults.standard.string(forKey: "probeQ_searchPrompt")
            ?? "Search/Explain the following query in detail but remain very concise."
        
        // Defaults: ⌃⌥O, ⌃⌥T, ⌃⌥P, ⌃⌥S
        let ctrlOpt = NSEvent.ModifierFlags([.control, .option]).rawValue
        self.ocrShortcut       = Self.loadBinding(forKey: "probeQ_ocrShortcut")       ?? ShortcutBinding(keyCode: 31, modifierFlags: ctrlOpt)
        self.translateShortcut = Self.loadBinding(forKey: "probeQ_translateShortcut") ?? ShortcutBinding(keyCode: 17, modifierFlags: ctrlOpt)
        self.polishShortcut    = Self.loadBinding(forKey: "probeQ_polishShortcut")    ?? ShortcutBinding(keyCode: 35, modifierFlags: ctrlOpt)
        self.searchShortcut    = Self.loadBinding(forKey: "probeQ_searchShortcut")    ?? ShortcutBinding(keyCode: 1,  modifierFlags: ctrlOpt)
    }
    
    private func saveBinding(_ binding: ShortcutBinding?, forKey key: String) {
        if let binding = binding, let data = try? JSONEncoder().encode(binding) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
    
    private static func loadBinding(forKey key: String) -> ShortcutBinding? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let binding = try? JSONDecoder().decode(ShortcutBinding.self, from: data) else { return nil }
        return binding
    }
}
