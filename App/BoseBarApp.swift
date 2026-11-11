import ServiceManagement
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
    /// Mirrors the login item state that macOS keeps (System Settings → General → Login Items).
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

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
                // Settings of the active custom mode. Quiet and Aware are fixed.
                if let mode = store.editableCurrentMode {
                    Divider()
                    // The headphones count the other way round (0 = strongest),
                    // so the menu shows 10 - raw value as "strength".
                    Picker(mode.windBlock ? "Geräuschunterdrückung (von Wind Block gesteuert)" : "Geräuschunterdrückung",
                           selection: Binding(
                               get: { 10 - Int(mode.cncLevel) },
                               set: { strength in store.updateCurrentMode { $0.cncLevel = UInt8(10 - strength) } }
                           )) {
                        ForEach((0...10).reversed(), id: \.self) { strength in
                            Text(strength == 10 ? "10 – maximal" : strength == 0 ? "0 – durchlässig" : "\(strength)")
                                .tag(strength)
                        }
                    }
                    // Measured on the device: with Wind Block on, the firmware
                    // forces the level to its own value, so choosing one is pointless.
                    .disabled(mode.windBlock)
                    Toggle("Wind Block", isOn: Binding(
                        get: { mode.windBlock },
                        set: { on in store.updateCurrentMode { $0.windBlock = on } }
                    ))
                }
            } else {
                Text(store.statusText)
            }
            Divider()
            Toggle("Beim Login starten", isOn: Binding(
                get: { launchAtLogin },
                set: { enable in
                    // macOS stores this itself; we only ask it to add or remove the app.
                    do {
                        if enable { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {
                        print("Login item change failed: \(error.localizedDescription)")
                    }
                    // Show what macOS actually did, also if the call failed.
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            ))
            Button("BoseBar beenden") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: store.iconName)
        }
    }
}
