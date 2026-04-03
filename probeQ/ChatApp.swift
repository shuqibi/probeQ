import SwiftUI

@main
struct ChatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // All windows (chat + settings) are managed programmatically by AppDelegate.
        // We still need at least one Scene for the @main App protocol.
        WindowGroup {
            EmptyView()
                .frame(width: 0, height: 0)
                .hidden()
        }
        .windowResizability(.contentSize)
    }
}
