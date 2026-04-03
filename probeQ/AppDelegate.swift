import AppKit
import SwiftUI
import Carbon

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem?
    var settingsWindow: NSWindow?
    
    var chatWindow: NSWindow?
    var chatViewModel: ChatViewModel!
    
    // System monitors
    var hotKeyRefs: [EventHotKeyRef?] = []
    
    static var shared: AppDelegate!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        requestAccessibilityPermissions()
        setupMenuBar()
        setupShortcuts()
        
        // Globally catch ESC key when app is active
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // ESC key
                if let chatWin = AppDelegate.shared.chatWindow, chatWin.isKeyWindow {
                    AppDelegate.shared.closeChatWindow()
                    return nil
                }
                if let setWin = AppDelegate.shared.settingsWindow, setWin.isKeyWindow {
                    setWin.close()
                    return nil
                }
            }
            return event
        }
    }
    
    private func requestAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        let _ = AXIsProcessTrustedWithOptions(options)
    }
    
    // MARK: - Menu Bar
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "brain.head.profile", accessibilityDescription: "probeQ")
        }
        
        let menu = NSMenu()
        menu.addItem(withTitle: "New Chat", action: #selector(showNewChat), keyEquivalent: "n")
        
        let historyMenuItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        let historyMenu = NSMenu()
        historyMenu.delegate = self // Dynamically populates when clicked
        historyMenuItem.submenu = historyMenu
        menu.addItem(historyMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit probeQ", action: #selector(quitApp), keyEquivalent: "q")
        statusItem?.menu = menu
    }
    
    // Dynamically build history menu
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let manager = HistoryManager.shared
        if manager.sessions.isEmpty {
            let empty = NSMenuItem(title: "No History", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for session in manager.sessions {
                let item = NSMenuItem(title: session.title, action: #selector(openHistorySession(_:)), keyEquivalent: "")
                item.representedObject = session
                menu.addItem(item)
            }
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Clear All History", action: #selector(clearHistory), keyEquivalent: "")
        }
    }
    
    @objc func openHistorySession(_ sender: NSMenuItem) {
        guard let session = sender.representedObject as? ChatSession else { return }
        showChatWindow(session: session)
    }
    
    @objc func clearHistory() {
        HistoryManager.shared.clearHistory()
    }
    
    // MARK: - Global Shortcuts (Carbon)
    
    private func setupShortcuts() {
        // Register Carbon event handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let eventHandler: EventHandlerUPP = { (_, eventRef, _) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            
            DispatchQueue.main.async {
                AppDelegate.shared.handleHotKey(id: Int(hotKeyID.id))
            }
            return noErr
        }
        
        InstallEventHandler(GetApplicationEventTarget(), eventHandler, 1, &eventType, nil, nil)
        
        registerAllHotKeys()
    }
    
    // Call this if settings change
    func registerAllHotKeys() {
        // Unregister existing hotkeys
        for ref in hotKeyRefs {
            if let ref = ref { UnregisterEventHotKey(ref) }
        }
        hotKeyRefs.removeAll()
        
        let settings = SettingsManager.shared
        registerHotKey(binding: settings.ocrShortcut, id: 1)
        registerHotKey(binding: settings.translateShortcut, id: 2)
        registerHotKey(binding: settings.polishShortcut, id: 3)
        registerHotKey(binding: settings.searchShortcut, id: 4)
    }
    
    private func registerHotKey(binding: ShortcutBinding?, id: Int) {
        guard let binding = binding else { return }
        var hotKeyId = EventHotKeyID(signature: 0x70726251, id: UInt32(id))
        var hotKeyRef: EventHotKeyRef?
        
        var carbonFlags: UInt32 = 0
        let flags = NSEvent.ModifierFlags(rawValue: binding.modifierFlags)
        if flags.contains(.command) { carbonFlags |= UInt32(cmdKey) }
        if flags.contains(.option) { carbonFlags |= UInt32(optionKey) }
        if flags.contains(.control) { carbonFlags |= UInt32(controlKey) }
        if flags.contains(.shift) { carbonFlags |= UInt32(shiftKey) }
        
        RegisterEventHotKey(UInt32(binding.keyCode), carbonFlags, hotKeyId, GetApplicationEventTarget(), 0, &hotKeyRef)
        hotKeyRefs.append(hotKeyRef)
    }
    
    private func handleHotKey(id: Int) {
        let settings = SettingsManager.shared
        switch id {
        case 1: triggerOCR()
        case 2: triggerClipboardAction(prompt: settings.translatePrompt)
        case 3: triggerClipboardAction(prompt: settings.polishPrompt)
        case 4: triggerClipboardAction(prompt: settings.searchPrompt)
        default: break
        }
    }
    
    // MARK: - Actions
    
    private func triggerOCR() {
        showChatWindow(show: false)
        chatViewModel.clearHistory()
        chatViewModel.onOCRGrab(onComplete: { [weak self] in
            guard let window = self?.chatWindow else { return }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        })
    }
    
    private func triggerClipboardAction(prompt: String) {
        let pasteboard = NSPasteboard.general
        let initialCount = pasteboard.changeCount
        
        // 1. Force release of physical modifier keys AND the 'C' key to prevent them from interfering with Cmd+C
        // (If the user's custom shortcut uses 'C', the OS will ignore our synthetic 'C' because it thinks it's already pressed down)
        let src = CGEventSource(stateID: .hidSystemState)
        let modifiers: [CGKeyCode] = [54, 55, 56, 58, 59, 60, 61, 62, 0x08] // Right/Left versions of Cmd, Shift, Opt, Ctrl, plus the 'C' key
        for mod in modifiers {
            let keyUp = CGEvent(keyboardEventSource: src, virtualKey: mod, keyDown: false)
            keyUp?.post(tap: .cghidEventTap)
        }
        
        // 2. Synthesize purely isolated Cmd+C
        let cmddown = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: true)
        let cmdup = CGEvent(keyboardEventSource: src, virtualKey: 0x08, keyDown: false)
        cmddown?.flags = .maskCommand
        cmdup?.flags = .maskCommand
        
        let loc = CGEventTapLocation.cghidEventTap
        cmddown?.post(tap: loc)
        cmdup?.post(tap: loc)
        
        // 3. Poll for clipboard change dynamically to prevent focus-stealing race conditions
        Task {
            var retries = 10
            while pasteboard.changeCount == initialCount && retries > 0 {
                try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
                retries -= 1
            }
            
            await MainActor.run {
                self.showChatWindow()
                self.chatViewModel.clearHistory()
                if pasteboard.changeCount != initialCount, let text = ClipboardManager.getText(), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    self.chatViewModel.sendMessage(text, prefixPrompt: prompt)
                } else {
                    self.chatViewModel.errorMessage = "No text selected or clipboard is empty."
                }
            }
        }
    }
    
    // MARK: - Window Management
    
    func showChatWindow(session: ChatSession? = nil, show: Bool = true) {
        if chatViewModel == nil {
            chatViewModel = ChatViewModel()
        }
        
        if let session = session {
            chatViewModel.sessionId = session.id
            chatViewModel.messages = session.messages
            chatViewModel.errorMessage = nil
            chatViewModel.inputText = ""
        } else {
            // ALWAYS clear history and start fresh when invoked without a session
            chatViewModel.clearHistory()
        }
        
        if chatWindow == nil {
            let contentView = MainView(viewModel: chatViewModel)
            let hostingView = NSHostingView(rootView: contentView)
            
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 550),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.contentView = hostingView
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            chatWindow = window
        }
        
        chatWindow?.title = session != nil ? "probeQ - History" : "probeQ"
        
        if show {
            chatWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    // Auto-save history when window closes
    func windowDidClose(_ notification: Notification) {
        guard notification.object as? NSWindow == chatWindow else { return }
        closeChatWindow()
    }
    
    @objc func closeChatWindow() {
        guard let window = chatWindow else { return }
        
        if !chatViewModel.messages.isEmpty {
            HistoryManager.shared.saveSession(id: chatViewModel.sessionId, messages: chatViewModel.messages)
        }
        chatViewModel.clearHistory()
        
        window.orderOut(nil)
        chatWindow = nil
    }
    
    // MARK: - Menu Actions
    
    @objc func showNewChat() { showChatWindow() }
    
    @objc func openSettings() {
        if settingsWindow == nil {
            let hostingView = NSHostingView(rootView: SettingsView())
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "probeQ Settings"
            window.contentView = hostingView
            window.center()
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("probeQSettingsWindow")
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func quitApp() { NSApp.terminate(nil) }
    
    // MARK: - Cleanup
    
    func applicationWillTerminate(_ notification: Notification) {
        for ref in hotKeyRefs {
            if let ref = ref { UnregisterEventHotKey(ref) }
        }
    }
}
