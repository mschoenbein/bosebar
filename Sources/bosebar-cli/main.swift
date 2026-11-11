// Test tool for real hardware. Runs several commands on ONE open connection
// and prints how long each took, e.g.:
//
//   swift run bosebar-cli status quiet aware status
//
// Commands: status | quiet | aware | mode <index> | cnc <0-10> | wind on|off
// cnc and wind change the ACTIVE mode and only work on custom modes.
import BMAPKit
import Foundation

let client = BoseClient()
let clock = ContinuousClock()

/// Runs `body` and prints the elapsed time.
@MainActor
func timed(_ label: String, _ body: () async throws -> Void) async throws {
    let start = clock.now
    try await body()
    let ms = (clock.now - start).components
    print("  [\(label): \(ms.seconds * 1000 + ms.attoseconds / 1_000_000_000_000_000) ms]")
}

@MainActor
func switchMode(_ index: UInt8) async throws {
    try await client.setMode(index)
    try await Task.sleep(for: .milliseconds(300)) // switch is applied asynchronously
    print("Mode index now: \(try await client.currentMode())")
}

/// Reads the active mode, lets `change` modify it and writes it back.
@MainActor
func changeCurrentMode(_ change: (inout ModeConfig) -> Void) async throws {
    let current = try await client.currentMode()
    guard var mode = try await client.modes().first(where: { $0.index == current }) else {
        throw BMAPError.unexpectedReply
    }
    change(&mode)
    let confirmed = try await client.write(mode)
    print("\(confirmed.displayName): cnc=\(confirmed.cncLevel) wind=\(confirmed.windBlock)")
}

do {
    try await timed("connect") { try await client.connect() }

    var args = Array(CommandLine.arguments.dropFirst())
    if args.isEmpty { args = ["status"] }
    while !args.isEmpty {
        let command = args.removeFirst()
        switch command {
        case "status":
            try await timed("status") {
                print("Name:     \(try await client.name())")
                print("Firmware: \(try await client.firmware())")
                print("Battery:  \(try await client.battery()) %")
                let current = try await client.currentMode()
                for mode in try await client.modes() {
                    print("\(mode.index == current ? " *" : "  ") \(mode.index) \(mode.displayName)\(mode.isEmptySlot ? " (empty slot)" : "")"
                        + "  cnc=\(mode.cncLevel) wind=\(mode.windBlock) editable=\(mode.editable)")
                }
            }
        case "quiet":
            try await timed("quiet") { try await switchMode(PrinceDevice.quietIndex) }
        case "aware":
            try await timed("aware") { try await switchMode(PrinceDevice.awareIndex) }
        case "mode":
            guard !args.isEmpty, let index = UInt8(args.removeFirst()) else {
                print("usage: mode <index>")
                exit(2)
            }
            try await timed("mode \(index)") { try await switchMode(index) }
        case "cnc":
            guard !args.isEmpty, let level = UInt8(args.removeFirst()), level <= 10 else {
                print("usage: cnc <0-10>")
                exit(2)
            }
            try await timed("cnc \(level)") { try await changeCurrentMode { $0.cncLevel = level } }
        case "wind":
            guard !args.isEmpty, ["on", "off"].contains(args[0]) else {
                print("usage: wind on|off")
                exit(2)
            }
            let on = args.removeFirst() == "on"
            try await timed("wind \(on ? "on" : "off")") { try await changeCurrentMode { $0.windBlock = on } }
        default:
            print("Unknown command: \(command)")
            exit(2)
        }
    }
    client.disconnect()
} catch {
    print("Error: \(error.localizedDescription)")
    exit(1)
}
