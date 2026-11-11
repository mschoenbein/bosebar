import Testing
@testable import BMAPKit

// Byte examples are taken from bosectl's docs/quietcomfort-headphones-prince.md.

@Test func encodesPackets() {
    // Read current mode.
    #expect(BMAPPacket(31, 3, .get).bytes == [0x1f, 0x03, 0x01, 0x00])
    // Switch to Quiet without voice prompt.
    #expect(BMAPPacket(31, 3, .start, [0, 0]).bytes == [0x1f, 0x03, 0x05, 0x02, 0x00, 0x00])
    // Request all modes.
    #expect(BMAPPacket(31, 1, .start).bytes == [0x1f, 0x01, 0x05, 0x00])
}

@Test func parsesConcatenatedPackets() {
    // PROCESSING ack followed directly by the STATUS with the new mode.
    var buffer: [UInt8] = [0x1f, 0x03, 0x07, 0x00, 0x1f, 0x03, 0x03, 0x01, 0x01]
    let packets = BMAPPacket.parseAll(&buffer)
    #expect(packets == [BMAPPacket(31, 3, .processing), BMAPPacket(31, 3, .status, [1])])
    #expect(buffer.isEmpty)
}

@Test func keepsIncompletePacketUntilRestArrives() {
    var buffer: [UInt8] = [0x02, 0x02, 0x03, 0x02, 90] // announces 2 payload bytes, has 1
    #expect(BMAPPacket.parseAll(&buffer).isEmpty)
    buffer.append(0)
    #expect(BMAPPacket.parseAll(&buffer) == [BMAPPacket(2, 2, .status, [90, 0])])
    #expect(buffer.isEmpty)
}

@Test func dropsGarbage() {
    var buffer: [UInt8] = [0x41, 0x54, 0x0d, 0x0a, 0x00] // operator nibble 0x0d is invalid
    #expect(BMAPPacket.parseAll(&buffer).isEmpty)
    #expect(buffer.isEmpty)
}

/// Builds a 47 byte STATUS payload like the "Music" slot from the docs.
private func musicStatusPayload() -> [UInt8] {
    var p = [UInt8](repeating: 0, count: 47)
    p[0] = 3                    // mode index
    p[1] = 0x00; p[2] = 0x0c    // voice prompt MUSIC
    p[3] = 1                    // editable
    p[4] = 1                    // configured
    p.replaceSubrange(6..<11, with: Array("Music".utf8))
    p[41] = 0x09                // capability bits
    p[42] = 5                   // raw CNC
    p[46] = 1                   // wind block
    return p
}

@Test func parsesModeConfigStatus() throws {
    let mode = try #require(ModeConfig(statusPayload: musicStatusPayload()))
    #expect(mode.index == 3)
    #expect(mode.prompt == [0x00, 0x0c])
    #expect(mode.editable)
    #expect(mode.configured)
    #expect(mode.name == "Music")
    #expect(mode.cncLevel == 5)
    #expect(!mode.autoCNC)
    #expect(mode.spatial == 0)
    #expect(mode.windBlock)
    #expect(!mode.isEmptySlot)
    #expect(ModeConfig(statusPayload: [UInt8](repeating: 0, count: 46)) == nil)
}

@Test func buildsModeConfigSetGet() throws {
    var mode = try #require(ModeConfig(statusPayload: musicStatusPayload()))
    mode.cncLevel = 7
    let p = mode.setGetPayload
    #expect(p.count == 39)
    #expect(Array(p[0..<3]) == [3, 0x00, 0x0c])
    #expect(Array(p[3..<8]) == Array("Music".utf8))
    #expect(p[8..<35].allSatisfy { $0 == 0 })
    #expect(Array(p[35...]) == [7, 0, 0, 1])
    // Full packet header as in the docs: 1f 06 02 27
    #expect(Array(BMAPPacket(31, 6, .setGet, p).bytes.prefix(4)) == [0x1f, 0x06, 0x02, 0x27])
}

@Test func detectsEmptyCustomSlot() throws {
    var deleted = musicStatusPayload()
    deleted.replaceSubrange(6..<38, with: Array("None".utf8) + [UInt8](repeating: 0, count: 28))
    #expect(try #require(ModeConfig(statusPayload: deleted)).isEmptySlot)

    var neverConfigured = musicStatusPayload()
    neverConfigured[4] = 0
    #expect(try #require(ModeConfig(statusPayload: neverConfigured)).isEmptySlot)
}

// Captured from the real headphones: slot 2, prompt 00 0d, configured, empty name field.
@Test func namesModeAfterVoicePromptWhenNameIsEmpty() throws {
    var p = [UInt8](repeating: 0, count: 47)
    p.replaceSubrange(0..<6, with: [0x02, 0x00, 0x0d, 0x01, 0x01, 0x01])
    p[41] = 0x09
    let mode = try #require(ModeConfig(statusPayload: p))
    #expect(mode.name.isEmpty)
    #expect(!mode.isEmptySlot)
    #expect(mode.displayName == "Focus")
    #expect(try #require(ModeConfig(statusPayload: musicStatusPayload())).displayName == "Music")
}

@Test func matchesRepliesToRequests() {
    let getMode = BMAPPacket(31, 3, .get)
    let startMode = BMAPPacket(31, 3, .start, [0, 0])
    #expect(RFCOMMTransport.isReply(BMAPPacket(31, 3, .status, [1]), to: getMode))
    #expect(!RFCOMMTransport.isReply(BMAPPacket(2, 2, .status, [90]), to: getMode))
    #expect(RFCOMMTransport.isReply(BMAPPacket(31, 3, .processing), to: startMode))
    #expect(RFCOMMTransport.isReply(BMAPPacket(31, 3, .error, [6]), to: startMode))
    // The STATUS after a START is the mode change notification, not the ack.
    #expect(!RFCOMMTransport.isReply(BMAPPacket(31, 3, .status, [0]), to: startMode))
}
