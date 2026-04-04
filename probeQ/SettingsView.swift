import SwiftUI
import AppKit

// MARK: - Shortcut Recorder (click to record any key combo)

class ShortcutRecorderNSView: NSView {
    var currentBinding: ShortcutBinding?
    var provisionalBinding: ShortcutBinding?
    var isRecording = false
    var onShortcutRecorded: ((ShortcutBinding?) -> Void)?
    
    override var acceptsFirstResponder: Bool { true }
    
    override func mouseDown(with event: NSEvent) {
        isRecording = true
        provisionalBinding = currentBinding
        window?.makeFirstResponder(self)
        needsDisplay = true
    }
    
    override func keyDown(with event: NSEvent) {
        guard isRecording else { return }
        
        // Enter / Return to confirm
        if event.keyCode == 36 || event.keyCode == 76 {
            currentBinding = provisionalBinding
            onShortcutRecorded?(provisionalBinding)
            isRecording = false
            needsDisplay = true
            return
        }
        
        // Delete / Backspace to clear
        if event.keyCode == 51 {
            provisionalBinding = nil
            currentBinding = nil
            onShortcutRecorded?(nil)
            isRecording = false
            needsDisplay = true
            return
        }
        
        // Escape to cancel (handled by cancelOperation, but we catch basic Esc here too)
        if event.keyCode == 53 {
            isRecording = false
            needsDisplay = true
            return
        }
        
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.capsLock)
        
        // Require at least one modifier key
        guard !flags.isEmpty else { return }
        
        provisionalBinding = ShortcutBinding(keyCode: event.keyCode, modifierFlags: flags.rawValue)
        needsDisplay = true
    }
    
    // Allow Escape to cancel recording
    override func cancelOperation(_ sender: Any?) {
        isRecording = false
        needsDisplay = true
    }
    
    override func resignFirstResponder() -> Bool {
        isRecording = false
        needsDisplay = true
        return super.resignFirstResponder()
    }
    
    override var intrinsicContentSize: NSSize {
        NSSize(width: 160, height: 28)
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let rect = bounds.insetBy(dx: 1, dy: 1)
        
        // Background
        NSColor.controlBackgroundColor.setFill()
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        path.fill()
        
        // Border
        let borderColor = isRecording ? NSColor.controlAccentColor : NSColor.separatorColor
        borderColor.setStroke()
        path.lineWidth = isRecording ? 2 : 1
        path.stroke()
        
        // Text
        let text: String
        let color: NSColor
        if isRecording {
            if let prov = provisionalBinding {
                text = "\(prov.displayString) (Press Return)"
            } else {
                text = "Press shortcut…"
            }
            color = NSColor.controlAccentColor
        } else if let binding = currentBinding {
            text = binding.displayString
            color = NSColor.labelColor
        } else {
            text = "Click to set"
            color = NSColor.secondaryLabelColor
        }
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: color
        ]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let size = attrStr.size()
        let point = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
        attrStr.draw(at: point)
    }
}

struct ShortcutRecorderView: NSViewRepresentable {
    @Binding var binding: ShortcutBinding?
    
    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.currentBinding = binding
        view.onShortcutRecorded = { newBinding in
            binding = newBinding
        }
        return view
    }
    
    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.currentBinding = binding
        nsView.needsDisplay = true
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @ObservedObject private var settings = SettingsManager.shared
    
    var body: some View {
        TabView {
            GeneralTab(settings: settings)
                .tabItem { Label("General", systemImage: "gear") }
            
            PromptsTab(settings: settings)
                .tabItem { Label("Prompts", systemImage: "text.bubble") }
            
            ShortcutsTab(settings: settings)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
        }
        .frame(width: 520, height: 400)
    }
}

// MARK: - General Tab

struct GeneralTab: View {
    @ObservedObject var settings: SettingsManager
    
    @State private var draftProvider: String
    @State private var previousProvider: String
    @State private var draftCustomURL: String
    @State private var draftApiKey: String
    @State private var draftModelName: String
    @State private var draftHistoryLimit: Int
    @State private var availableModels: [LLMModelInfo] = []
    
    init(settings: SettingsManager) {
        self.settings = settings
        _draftProvider = State(initialValue: settings.apiProvider)
        _previousProvider = State(initialValue: settings.apiProvider)
        _draftCustomURL = State(initialValue: settings.customBaseURL)
        _draftApiKey = State(initialValue: settings.apiKey)
        _draftModelName = State(initialValue: settings.modelName)
        _draftHistoryLimit = State(initialValue: settings.historyLimit)
    }
    
    var hasChanges: Bool {
        draftProvider != settings.apiProvider ||
        draftCustomURL != settings.customBaseURL ||
        draftApiKey != settings.apiKey ||
        draftModelName != settings.modelName ||
        draftHistoryLimit != settings.historyLimit
    }
    
    var body: some View {
        VStack {
            Form {
                Section(header: Text("API Configuration").font(.headline).fontWeight(.bold).foregroundColor(.primary)) {
                    Picker("API Provider", selection: $draftProvider) {
                        Text("Select a Provider...").tag("none")
                        Text("Google Gemini").tag("gemini")
                        Text("DeepSeek").tag("deepseek")
                        Text("Zhipu (GLM)").tag("zhipu")
                        Text("Qwen (Aliyun)").tag("qwen")
                        Text("OpenAI").tag("openai")
                        Text("Moonshot (Kimi)").tag("moonshot")
                        Text("Groq (Llama/Mixtral)").tag("groq")
                        Text("Grok (xAI)").tag("grok")
                        Text("Custom (OpenAI Compatible)").tag("custom")
                    }
                    .pickerStyle(MenuPickerStyle())
                    
                    if draftProvider != "none" {
                        if draftProvider == "custom" {
                            TextField("Base URL (e.g. http://localhost:11434/v1)", text: $draftCustomURL)
                        }
                        
                        HStack {
                            SecureField("API Key", text: $draftApiKey)
                            Button(action: {
                                draftApiKey = ""
                                settings.setProviderAPIKey("", for: draftProvider)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                            .help("Clear API Key for this brand")
                        }
                        
                        HStack {
                            TextField("Model Selector (Type or use Presets)", text: $draftModelName)
                            
                            if !availableModels.isEmpty {
                                Menu("Presets") {
                                    ForEach(availableModels) { model in
                                        Button(model.displayName) {
                                            draftModelName = model.name
                                        }
                                    }
                                }
                                .frame(width: 80)
                            }
                        }
                        .help("Type a custom model ID, or select one from the Presets menu dynamically fetched from the provider.")
                    }
                }
                .onChange(of: draftProvider) { newProvider in
                    if previousProvider != "none" {
                        settings.setProviderAPIKey(draftApiKey, for: previousProvider)
                        settings.setProviderModel(draftModelName, for: previousProvider)
                        settings.setProviderBaseURL(draftCustomURL, for: previousProvider)
                    }
                    if newProvider != "none" {
                        draftApiKey = settings.getProviderAPIKey(newProvider)
                        draftModelName = settings.getProviderModel(newProvider)
                        draftCustomURL = settings.getProviderBaseURL(newProvider)
                        availableModels = []
                    }
                    previousProvider = newProvider
                }
                .task(id: "\(draftProvider)-\(draftCustomURL)-\(draftApiKey)") {
                    guard draftProvider != "none" && !draftApiKey.isEmpty else { return }
                    // Re-fetch models when provider, URL, or API key changes
                    do {
                        let models = try await LLMManager.shared.getAvailableModels(provider: draftProvider, customURL: draftCustomURL, apiKey: draftApiKey)
                        availableModels = models
                        if !models.contains(where: { $0.name == draftModelName }), let first = models.first {
                            draftModelName = first.name
                        }
                    } catch {
                        print("Failed to dynamically fetch models: \(error)")
                    }
                }
                
                Section(header: Text("History").font(.headline).fontWeight(.bold).foregroundColor(.primary)) {
                    Picker("Store Past Chats", selection: $draftHistoryLimit) {
                        Text("Don't store history").tag(0)
                        Text("Store 20 chats").tag(20)
                        Text("Store 50 chats").tag(50)
                    }
                    .pickerStyle(MenuPickerStyle())
                }
            }
            .padding()
            
            HStack {
                Spacer()
                Button("Save Settings") {
                    settings.apiProvider = draftProvider
                    settings.customBaseURL = draftCustomURL
                    settings.apiKey = draftApiKey
                    settings.modelName = draftModelName
                    settings.historyLimit = draftHistoryLimit
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(!hasChanges)
                .controlSize(.large)
            }
            .padding([.horizontal, .bottom])
        }
    }
}

// MARK: - Prompts Tab

struct PromptsTab: View {
    @ObservedObject var settings: SettingsManager
    
    @State private var draftTranslate: String
    @State private var draftPolish: String
    @State private var draftSearch: String
    
    init(settings: SettingsManager) {
        self.settings = settings
        _draftTranslate = State(initialValue: settings.translatePrompt)
        _draftPolish = State(initialValue: settings.polishPrompt)
        _draftSearch = State(initialValue: settings.searchPrompt)
    }
    
    var hasChanges: Bool {
        draftTranslate != settings.translatePrompt ||
        draftPolish != settings.polishPrompt ||
        draftSearch != settings.searchPrompt
    }
    
    var body: some View {
        VStack {
            Form {
                Section("Translate Prompt") {
                    TextEditor(text: $draftTranslate)
                        .frame(height: 60)
                        .font(.body)
                }
                
                Section("Polish Prompt") {
                    TextEditor(text: $draftPolish)
                        .frame(height: 60)
                        .font(.body)
                }
                
                Section("Search Prompt") {
                    TextEditor(text: $draftSearch)
                        .frame(height: 60)
                        .font(.body)
                }
            }
            .padding()
            
            HStack {
                Spacer()
                Button("Save Prompts") {
                    settings.translatePrompt = draftTranslate
                    settings.polishPrompt = draftPolish
                    settings.searchPrompt = draftSearch
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(!hasChanges)
                .controlSize(.large)
            }
            .padding([.horizontal, .bottom])
        }
    }
}

// MARK: - Shortcuts Tab

struct ShortcutsTab: View {
    @ObservedObject var settings: SettingsManager
    
    @State private var draftOcr: ShortcutBinding?
    @State private var draftTranslate: ShortcutBinding?
    @State private var draftPolish: ShortcutBinding?
    @State private var draftSearch: ShortcutBinding?
    
    init(settings: SettingsManager) {
        self.settings = settings
        _draftOcr = State(initialValue: settings.ocrShortcut)
        _draftTranslate = State(initialValue: settings.translateShortcut)
        _draftPolish = State(initialValue: settings.polishShortcut)
        _draftSearch = State(initialValue: settings.searchShortcut)
    }
    
    var hasChanges: Bool {
        draftOcr != settings.ocrShortcut ||
        draftTranslate != settings.translateShortcut ||
        draftPolish != settings.polishShortcut ||
        draftSearch != settings.searchShortcut
    }
    
    var body: some View {
        VStack {
            Form {
                Text("Click a field, then press your combination (e.g. ⌘⇧O). Press Delete to clear.")
                    .foregroundColor(.secondary)
                    .font(.callout)
                
                Section("Shortcuts") {
                    HStack {
                        Text("OCR Capture")
                            .frame(width: 140, alignment: .trailing)
                        ShortcutRecorderView(binding: $draftOcr)
                            .onChange(of: draftOcr) { nv in resolveDuplicates(newVal: nv, source: "ocr") }
                    }
                    
                    HStack {
                        Text("Translate Clipboard")
                            .frame(width: 140, alignment: .trailing)
                        ShortcutRecorderView(binding: $draftTranslate)
                            .onChange(of: draftTranslate) { nv in resolveDuplicates(newVal: nv, source: "trans") }
                    }
                    
                    HStack {
                        Text("Polish Clipboard")
                            .frame(width: 140, alignment: .trailing)
                        ShortcutRecorderView(binding: $draftPolish)
                            .onChange(of: draftPolish) { nv in resolveDuplicates(newVal: nv, source: "pol") }
                    }
                    
                    HStack {
                        Text("Search Clipboard")
                            .frame(width: 140, alignment: .trailing)
                        ShortcutRecorderView(binding: $draftSearch)
                            .onChange(of: draftSearch) { nv in resolveDuplicates(newVal: nv, source: "sea") }
                    }
                }
            }
            .padding()
            
            HStack {
                Spacer()
                Button("Save Settings") {
                    settings.ocrShortcut = draftOcr
                    settings.translateShortcut = draftTranslate
                    settings.polishShortcut = draftPolish
                    settings.searchShortcut = draftSearch
                    
                    // Live reload!
                    AppDelegate.shared.registerAllHotKeys()
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(!hasChanges)
                .controlSize(.large)
            }
            .padding([.horizontal, .bottom])
        }
    }
    
    private func resolveDuplicates(newVal: ShortcutBinding?, source: String) {
        guard let newVal = newVal else { return }
        if source != "ocr" && draftOcr == newVal { draftOcr = nil }
        if source != "trans" && draftTranslate == newVal { draftTranslate = nil }
        if source != "pol" && draftPolish == newVal { draftPolish = nil }
        if source != "sea" && draftSearch == newVal { draftSearch = nil }
    }
}
