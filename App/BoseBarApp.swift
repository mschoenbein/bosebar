import SwiftUI

/// Launching BoseBar again while it is already running (Spotlight, double click)
/// lands here. We use that to bring back a hidden menu bar icon.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        HeadphoneStore.shared.reveal()
        return false
    }
}

@main
struct BoseBarApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var store = HeadphoneStore.shared

    var body: some Scene {
        // Reading the value here makes SwiftUI re-run `body` when it changes.
        let visible = store.showInMenuBar
        // isInserted = false removes the icon; the app keeps running in the background.
        MenuBarExtra(isInserted: .constant(visible)) {
            if store.connected {
                Text(store.battery.map { "\(store.name) – \($0) %" } ?? store.name)
                Divider()
                // One checkable entry per mode; the checkmark marks the active one.
                ForEach(store.modes) { mode in
                    Toggle(mode.displayName, isOn: Binding(
                        get: { store.currentMode == mode.index },
                        set: { _ in store.select(mode.index) }
                    ))
                }
            } else {
                Text(store.statusText)
            }
            Divider()
            Button("BoseBar beenden") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: store.iconName)
        }
    }
}
