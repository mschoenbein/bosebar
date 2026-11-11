import Foundation

/// High-level API for the headphones. Connect once, then call the methods as often as needed.
@MainActor
public final class BoseClient {
    /// The headphones report a new current mode (after `setMode`, or when the
    /// action button on the headphones is pressed).
    public var onModeChanged: ((UInt8) -> Void)?
    /// The connection is gone. Call `connect()` again once the headphones are back.
    public var onDisconnect: (() -> Void)?

    /// Latest mode configs received from the headphones, by mode index.
    private var modeCache: [UInt8: ModeConfig] = [:]
    private let transport = RFCOMMTransport()

    public init() {
        transport.onUnsolicited = { [weak self] in self?.handle($0) }
        transport.onClosed = { [weak self] in self?.onDisconnect?() }
    }

    public func connect() async throws {
        modeCache.removeAll()
        try await transport.open(
            productID: PrinceDevice.productID,
            fallbackChannels: PrinceDevice.channels,
            probe: get(PrinceDevice.firmware)
        )
    }

    public func disconnect() {
        transport.close()
    }

    // MARK: - Reading

    public func firmware() async throws -> String {
        String(decoding: try await transport.request(get(PrinceDevice.firmware)).payload, as: UTF8.self)
    }

    /// The Bluetooth name of the headphones.
    public func name() async throws -> String {
        // First payload byte is a flag, the name follows.
        String(decoding: try await transport.request(get(PrinceDevice.productName)).payload.dropFirst(), as: UTF8.self)
    }

    /// Battery level in percent.
    public func battery() async throws -> Int {
        guard let level = try await transport.request(get(PrinceDevice.battery)).payload.first else {
            throw BMAPError.unexpectedReply
        }
        return Int(level)
    }

    /// Index of the active mode.
    public func currentMode() async throws -> UInt8 {
        guard let index = try await transport.request(get(PrinceDevice.currentMode)).payload.first else {
            throw BMAPError.unexpectedReply
        }
        return index
    }

    /// All modes stored on the headphones, sorted by index.
    public func modes() async throws -> [ModeConfig] {
        // The headphones answer with one [31.6] STATUS packet per mode; `handle` collects them.
        try transport.send(BMAPPacket(PrinceDevice.allModes.0, PrinceDevice.allModes.1, .start))
        // ponytail: fixed wait instead of detecting the end of the list. Only used
        // once per connect; raise it if modes are ever missing.
        try await Task.sleep(for: .milliseconds(600))
        return modeCache.values.sorted { $0.index < $1.index }
    }

    // MARK: - Writing

    /// Switches to the mode with the given index.
    /// - Parameter announce: true = the headphones speak the mode name.
    public func setMode(_ index: UInt8, announce: Bool = false) async throws {
        let packet = BMAPPacket(PrinceDevice.currentMode.0, PrinceDevice.currentMode.1, .start,
                                [index, announce ? 1 : 0])
        // prince answers PROCESSING and applies the switch a moment later;
        // the new mode then arrives through `onModeChanged`.
        let reply = try await transport.request(packet)
        guard reply.op == .result || reply.op == .processing else { throw BMAPError.unexpectedReply }
    }

    // MARK: - Internals

    private func get(_ address: (UInt8, UInt8)) -> BMAPPacket {
        BMAPPacket(address.0, address.1, .get)
    }

    /// Packets the headphones send on their own.
    private func handle(_ packet: BMAPPacket) {
        guard packet.op == .status else { return }
        if (packet.fblock, packet.function) == PrinceDevice.modeConfig,
           let mode = ModeConfig(statusPayload: packet.payload) {
            modeCache[mode.index] = mode
        } else if (packet.fblock, packet.function) == PrinceDevice.currentMode,
                  let index = packet.payload.first {
            onModeChanged?(index)
        }
    }
}
