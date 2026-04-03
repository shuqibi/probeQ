import AppKit

class ClipboardManager {
    static func getText() -> String? {
        return NSPasteboard.general.string(forType: .string)
    }
    
    static func setText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
