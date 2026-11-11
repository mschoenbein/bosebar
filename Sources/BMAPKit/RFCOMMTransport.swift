import Foundation
@preconcurrency import IOBluetooth

/// Keeps one RFCOMM channel to the headphones open and sends/receives BMAP packets.
///
/// Everything runs on the main actor: IOBluetooth delivers its delegate
/// callbacks on the run loop of the thread that opened the channel, which is
/// the main run loop here. So no locks are needed.
///
/// IMPORTANT: never call `closeConnection()` on the IOBluetoothDevice. That
/// disconnects the headphones from the Mac completely (audio stops). We only
/// ever close our own RFCOMM channel.
@MainActor
public final class RFCOMMTransport: NSObject, @preconcurrency IOBluetoothRFCOMMChannelDelegate {
    /// Called for every packet that is not the answer to a pending request.
    public var onUnsolicited: ((BMAPPacket) -> Void)?
    /// Called when the channel closes (headphones off, out of range, ...).
    public var onClosed: (() -> Void)?

    private var channel: IOBluetoothRFCOMMChannel?
    private var buffer: [UInt8] = []
    /// While true, incoming data is thrown away (startup chatter after opening).
    private var discarding = false

    /// The one request currently waiting for its answer.
    private struct Pending {
        let request: BMAPPacket
        let continuation: CheckedContinuation<BMAPPacket, Error>
        let timeout: Task<Void, Never>
    }
    private var pending: Pending?
    /// End of the request queue; each new request waits for this one first.
    private var queueTail: Task<Void, Never>?

    /// Set while `openChannel` waits for the "open complete" callback.
    private var openWaiter: CheckedContinuation<IOReturn, Never>?
    private var openTimeout: Task<Void, Never>?

    /// Set the environment variable BMAP_DEBUG=1 to print all traffic to stderr.
    private static let debug = ProcessInfo.processInfo.environment["BMAP_DEBUG"] != nil
    private func log(_ message: @autoclosure () -> String) {
        if Self.debug { FileHandle.standardError.write(Data("[bmap] \(message())\n".utf8)) }
    }
    private func hex(_ bytes: some Sequence<UInt8>) -> String {
        bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    // MARK: - Open / close

    /// Finds the connected headphones and opens the BMAP channel.
    ///
    /// - Parameters:
    ///   - fallbackChannels: RFCOMM channel ids to try if the headphones' service
    ///     list does not name the serial port channel.
    ///   - probe: A harmless GET. A channel only counts as BMAP if it answers
    ///     this with STATUS (some channels accept the connection but stay silent).
    public func open(productID: Int, fallbackChannels: [UInt8], probe: BMAPPacket) async throws {
        close()
        let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        // `productID` is not in the public header, but the selector exists (bosectl uses it too).
        guard let device = paired.first(where: {
            $0.isConnected() && $0.responds(to: Selector(("productID")))
                && ($0.value(forKey: "productID") as? Int) == productID
        }) else { throw BMAPError.notConnected }

        // BMAP runs on the Serial Port (SPP) service. Its channel differs between
        // units (8 or 9 seen), so ask the service list (SDP) instead of guessing.
        var candidates = fallbackChannels
        if Self.serialPortChannel(of: device) == nil {
            device.performSDPQuery(nil) // macOS has no cached service list yet: fetch it
            try await Task.sleep(for: .milliseconds(1500))
        }
        if let id = Self.serialPortChannel(of: device) { candidates = [id] }

        for id in candidates {
            guard let opened = await openChannel(id, on: device) else { continue }
            channel = opened

            // Throw away whatever the headphones send right after opening.
            discarding = true
            try await Task.sleep(for: .milliseconds(500))
            discarding = false
            buffer.removeAll()

            if let reply = try? await request(probe, timeout: .seconds(1)), reply.op == .status { return }
            close()
        }
        throw BMAPError.channelUnavailable
    }

    private static func serialPortChannel(of device: IOBluetoothDevice) -> UInt8? {
        var id: BluetoothRFCOMMChannelID = 0
        guard let record = device.getServiceRecord(for: IOBluetoothSDPUUID(uuid16: 0x1101)),
              record.getRFCOMMChannelID(&id) == kIOReturnSuccess else { return nil }
        return id
    }

    /// Opens one RFCOMM channel and waits until macOS reports the result.
    ///
    /// Do NOT use `openRFCOMMChannelSync` here: inside Swift async code it returns
    /// at once with an error while macOS keeps connecting in the background.
    /// Closing in that moment leaves a connection inside bluetoothd that nobody
    /// owns, and the channel then stays blocked for every program until the
    /// headphones reconnect. (Found the hard way.)
    private func openChannel(_ id: UInt8, on device: IOBluetoothDevice) async -> IOBluetoothRFCOMMChannel? {
        var opened: IOBluetoothRFCOMMChannel?
        let started = device.openRFCOMMChannelAsync(&opened, withChannelID: id, delegate: self)
        guard started == kIOReturnSuccess, let opened else {
            log("open channel \(id): could not start (\(String(format: "0x%08x", started)))")
            return nil
        }
        // The result arrives in `rfcommChannelOpenComplete`.
        let status = await withCheckedContinuation { continuation in
            openWaiter = continuation
            openTimeout = Task {
                try? await Task.sleep(for: .seconds(5))
                if !Task.isCancelled { self.finishOpen(kIOReturnTimeout) }
            }
        }
        log("open channel \(id): status \(String(format: "0x%08x", status))")
        return status == kIOReturnSuccess ? opened : nil
    }

    private func finishOpen(_ status: IOReturn) {
        openTimeout?.cancel()
        openTimeout = nil
        openWaiter?.resume(returning: status)
        openWaiter = nil
    }

    public func rfcommChannelOpenComplete(_ rfcommChannel: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        finishOpen(error)
    }

    /// Closes our RFCOMM channel only. The audio connection stays untouched.
    public func close() {
        channel?.close()
        channel = nil
        buffer.removeAll()
        finishPending(.failure(BMAPError.notConnected))
    }

    // MARK: - Sending

    /// Sends a packet without waiting for an answer.
    public func send(_ packet: BMAPPacket) throws {
        guard let channel else { throw BMAPError.notConnected }
        var bytes = packet.bytes
        log("tx \(hex(bytes))")
        guard channel.writeSync(&bytes, length: UInt16(bytes.count)) == kIOReturnSuccess else {
            throw BMAPError.notConnected
        }
    }

    /// Sends a packet and returns the answer from the same address.
    /// Requests are queued, so only one is on the wire at a time.
    public func request(_ packet: BMAPPacket, timeout: Duration = .seconds(3)) async throws -> BMAPPacket {
        let previous = queueTail
        let task = Task {
            await previous?.value
            return try await self.exchange(packet, timeout: timeout)
        }
        queueTail = Task { _ = try? await task.value }
        return try await task.value
    }

    private func exchange(_ packet: BMAPPacket, timeout: Duration) async throws -> BMAPPacket {
        try send(packet)
        let reply = try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task {
                try? await Task.sleep(for: timeout)
                if !Task.isCancelled { self.finishPending(.failure(BMAPError.timeout)) }
            }
            pending = Pending(request: packet, continuation: continuation, timeout: timeoutTask)
        }
        if reply.op == .error { throw BMAPError.device(code: reply.payload.first ?? 0) }
        return reply
    }

    private func finishPending(_ result: Result<BMAPPacket, Error>) {
        guard let current = pending else { return }
        pending = nil
        current.timeout.cancel()
        current.continuation.resume(with: result)
    }

    /// Is `packet` the answer to `request`? Same address is required. A START
    /// is acknowledged with RESULT/PROCESSING/ERROR; a STATUS from the same
    /// address is a separate notification (e.g. the mode change that follows).
    nonisolated static func isReply(_ packet: BMAPPacket, to request: BMAPPacket) -> Bool {
        guard packet.fblock == request.fblock, packet.function == request.function else { return false }
        return !(request.op == .start && packet.op == .status)
    }

    // MARK: - IOBluetoothRFCOMMChannelDelegate

    public func rfcommChannelData(_ rfcommChannel: IOBluetoothRFCOMMChannel!,
                                  data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        let chunk = UnsafeRawBufferPointer(start: dataPointer, count: dataLength)
        log("rx \(hex(chunk))\(rfcommChannel === channel ? "" : " (other channel)")\(discarding ? " (discarded)" : "")")
        guard rfcommChannel === channel, !discarding else { return }
        buffer.append(contentsOf: chunk)
        for packet in BMAPPacket.parseAll(&buffer) {
            if let current = pending, Self.isReply(packet, to: current.request) {
                finishPending(.success(packet))
            } else {
                onUnsolicited?(packet)
            }
        }
    }

    public func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        log("channel closed")
        // Ignore the late callback of a channel we closed ourselves while probing.
        guard rfcommChannel === channel else { return }
        channel = nil
        buffer.removeAll()
        finishPending(.failure(BMAPError.notConnected))
        onClosed?()
    }
}
