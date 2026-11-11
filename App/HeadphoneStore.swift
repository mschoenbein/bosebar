import BMAPKit
import Observation

/// The state the menu shows. Owns the connection and reconnects on its own.
@MainActor
@Observable
final class HeadphoneStore {
    /// One instance for the whole app (the app delegate needs to reach it too).
    static let shared = HeadphoneStore()

    private(set) var connected = false
    /// false while the headphones are off or out of range. Stays true if they are
    /// there but the control channel failed, so the error is visible in the menu.
    private var headphonesPresent = false
    /// Set when the user launches the app again while it is hidden (see `reveal`).
    private var revealed = false

    /// The menu bar icon is hidden while the headphones are away.
    var showInMenuBar: Bool { headphonesPresent || revealed }

    /// Shows the icon although no headphones are connected, so the app can be
    /// quit from its menu. Ends with the next successful connection.
    func reveal() { revealed = true }
    /// Shown in the menu while not connected ("Nicht verbunden" or an error).
    private(set) var statusText = "Nicht verbunden"
    private(set) var name = ""
    private(set) var battery: Int?
    private(set) var modes: [ModeConfig] = []
    private(set) var currentMode: UInt8?

    private let client = BoseClient()

    init() {
        // The headphones report mode changes themselves (also for the action button).
        client.onModeChanged = { [weak self] in self?.currentMode = $0 }
        client.onDisconnect = { [weak self] in self?.markDisconnected(BMAPError.notConnected) }
        Task { await run() }
    }

    /// SF Symbol for the menu bar, reflecting the current mode.
    var iconName: String {
        guard connected else { return "headphones" }
        switch currentMode {
        case PrinceDevice.quietIndex: return "headphones.circle.fill"
        case PrinceDevice.awareIndex: return "ear"
        default: return "slider.horizontal.3"
        }
    }

    func select(_ index: UInt8) {
        guard connected else { return }
        currentMode = index // show it right away; the headphones confirm below
        Task {
            do {
                try await client.setMode(index)
                // The switch is applied asynchronously, so read back a moment later.
                try await Task.sleep(for: .milliseconds(300))
                currentMode = try await client.currentMode()
            } catch {
                markDisconnected(error)
            }
        }
    }

    // MARK: - Connection handling

    /// Runs forever: connects when the headphones show up, refreshes the battery while connected.
    /// ponytail: polls every 5 s instead of using IOBluetooth connect notifications.
    private func run() async {
        var tick = 0
        while true {
            if !connected {
                await connect()
            } else if tick % 12 == 0, let level = try? await client.battery() { // once a minute
                battery = level
            }
            tick += 1
            try? await Task.sleep(for: .seconds(5))
        }
    }

    private func connect() async {
        do {
            try await client.connect()
            name = try await client.name()
            battery = try await client.battery()
            // Hide custom slots that were never set up.
            modes = try await client.modes().filter { !$0.isEmptySlot }
            currentMode = try await client.currentMode()
            connected = true
            headphonesPresent = true
            revealed = false
        } catch {
            markDisconnected(error)
        }
    }

    private func markDisconnected(_ error: Error) {
        client.disconnect() // closes only our control channel, never the audio connection
        connected = false
        statusText = error.localizedDescription
        headphonesPresent = (error as? BMAPError) != .notConnected
    }
}
