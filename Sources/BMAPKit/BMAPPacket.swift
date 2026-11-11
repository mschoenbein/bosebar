import Foundation

/// The operator of a BMAP packet (low nibble of the flags byte).
public enum BMAPOperator: UInt8, Sendable {
    case set = 0, get, setGet, status, error, start, result, processing
}

/// One BMAP packet: `[fblock, function, flags, payloadLength, ...payload]`.
public struct BMAPPacket: Equatable, Sendable {
    public var fblock: UInt8
    public var function: UInt8
    public var op: BMAPOperator
    public var payload: [UInt8]

    public init(_ fblock: UInt8, _ function: UInt8, _ op: BMAPOperator, _ payload: [UInt8] = []) {
        self.fblock = fblock
        self.function = function
        self.op = op
        self.payload = payload
    }

    /// The bytes that go over the wire.
    public var bytes: [UInt8] {
        [fblock, function, op.rawValue, UInt8(payload.count)] + payload
    }

    /// Removes all complete packets from the front of `buffer` and returns them.
    ///
    /// The headphones may send several packets back to back, and one packet may
    /// arrive split over two Bluetooth chunks. An incomplete packet stays in
    /// `buffer` until the rest arrives. If the bytes are not BMAP at all
    /// (invalid operator), the buffer is emptied so we can resync.
    public static func parseAll(_ buffer: inout [UInt8]) -> [BMAPPacket] {
        var packets: [BMAPPacket] = []
        var pos = 0
        while pos + 4 <= buffer.count {
            guard let op = BMAPOperator(rawValue: buffer[pos + 2] & 0x0F) else {
                buffer.removeAll()
                return packets
            }
            let end = pos + 4 + Int(buffer[pos + 3])
            if end > buffer.count { break } // incomplete, wait for more data
            packets.append(BMAPPacket(buffer[pos], buffer[pos + 1], op, Array(buffer[pos + 4..<end])))
            pos = end
        }
        buffer.removeFirst(pos)
        return packets
    }
}

public enum BMAPError: Error, LocalizedError, Equatable {
    /// No paired headphones with a live Bluetooth connection.
    case notConnected
    /// Headphones are connected, but no RFCOMM channel answered BMAP.
    case channelUnavailable
    case timeout
    /// The headphones answered with an ERROR packet (payload[0] = code).
    case device(code: UInt8)
    case unexpectedReply
    /// Quiet and Aware are fixed; only custom modes can be changed.
    case notEditable

    public var errorDescription: String? {
        switch self {
        case .notConnected: "Nicht verbunden"
        case .channelUnavailable: "Steuerkanal belegt (läuft bosectl oder die Bose-App?)"
        case .timeout: "Keine Antwort vom Kopfhörer"
        case .device(let code): "Kopfhörer meldet Fehler \(code)"
        case .unexpectedReply: "Unerwartete Antwort vom Kopfhörer"
        case .notEditable: "Dieser Modus ist nicht veränderbar"
        }
    }
}
