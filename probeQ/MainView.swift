import SwiftUI

// MARK: - Custom Input: Enter sends, Shift+Enter adds newline

struct ChatInputView: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.delegate = context.coordinator
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.textContainer?.widthTracksTextView = true
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text {
            textView.string = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onSubmit: onSubmit)
    }
    
    class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var onSubmit: () -> Void
        
        init(text: Binding<String>, onSubmit: @escaping () -> Void) {
            _text = text
            self.onSubmit = onSubmit
        }
        
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSStandardKeyBindingResponding.insertNewline(_:)) {
                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                    // Shift+Enter: insert newline
                    textView.insertNewlineIgnoringFieldEditor(nil)
                    return true
                }
                // Plain Enter: submit message
                onSubmit()
                return true
            }
            return false
        }
        
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
        }
    }
}

// MARK: - Main Chat View

struct MainView: View {
    @ObservedObject var viewModel: ChatViewModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Chat History Area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if viewModel.messages.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "sparkles")
                                    .font(.largeTitle)
                                    .foregroundColor(.blue)
                                Text("No history yet. Start by grabbing text or typing!")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.top, 60)
                        }
                        
                        ForEach(viewModel.messages) { message in
                            HStack {
                                if message.role == "user" { Spacer() }
                                Text(
                                    (try? AttributedString(
                                        markdown: message.parts,
                                        options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                                    )) ?? AttributedString(message.parts)
                                )
                                    .padding(12)
                                    .background(message.role == "user" ? Color.blue : Color(NSColor.controlBackgroundColor))
                                    .foregroundColor(message.role == "user" ? .white : .primary)
                                    .cornerRadius(12)
                                    .textSelection(.enabled)
                                    .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
                                    .frame(maxWidth: 320, alignment: message.role == "user" ? .trailing : .leading)
                                
                                if message.role == "model" { Spacer() }
                            }
                            .id(message.id)
                        }
                        
                        if viewModel.isWaitingForResponse && !viewModel.messages.isEmpty {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                            .id("loader")
                        }
                    }
                    .padding()
                }
                .background(Color(NSColor.underPageBackgroundColor).opacity(0.3))
                .onChange(of: viewModel.messages.count) { _ in
                    if let lastId = viewModel.messages.last?.id {
                        withAnimation { proxy.scrollTo(lastId, anchor: .bottom) }
                    }
                }
                .onChange(of: viewModel.isWaitingForResponse) { waiting in
                    if waiting {
                        withAnimation { proxy.scrollTo("loader", anchor: .bottom) }
                    }
                }
            }
            
            Divider()
            
            // Bottom Area: Input + Actions
            VStack(spacing: 12) {
                // Quick grab buttons
                HStack {
                    Button(action: { viewModel.onClipboardGrab() }) {
                        Label("Grab Clipboard", systemImage: "doc.on.clipboard")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    
                    Button(action: { viewModel.onOCRGrab() }) {
                        Label("Extract Text (OCR)", systemImage: "crop")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }
                
                if let error = viewModel.errorMessage {
                    Text(error)
                        .foregroundColor(Color(NSColor(name: nil, dynamicProvider: { appearance in
                            appearance.name == .darkAqua ? NSColor(red: 0.6, green: 0.6, blue: 0.8, alpha: 1.0) : NSColor(red: 0.2, green: 0.2, blue: 0.35, alpha: 1.0)
                        })))
                        .font(.caption)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                // Input — Enter sends, Shift+Enter adds newline
                ChatInputView(text: $viewModel.inputText) {
                    guard !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    guard !viewModel.isWaitingForResponse else { return }
                    viewModel.sendMessage(viewModel.inputText)
                }
                .frame(height: 80)
                
                // Submit buttons
                HStack(spacing: 8) {
                    Button("Translate") { viewModel.submitPrompt(type: "Translate") }
                        .buttonStyle(.bordered)
                    Button("Polish") { viewModel.submitPrompt(type: "Polish") }
                        .buttonStyle(.bordered)
                    Button("Search") { viewModel.submitPrompt(type: "Search") }
                        .buttonStyle(.bordered)
                    
                    Button(action: {
                        AppDelegate.shared?.openSettings()
                    }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Open Settings")
                    
                    Spacer()
                    
                    Button(action: {
                        guard !viewModel.inputText.isEmpty else { return }
                        viewModel.sendMessage(viewModel.inputText)
                    }) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(viewModel.inputText.isEmpty || viewModel.isWaitingForResponse ? .secondary : .blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.inputText.isEmpty || viewModel.isWaitingForResponse)
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 420, minHeight: 550)
    }
}
