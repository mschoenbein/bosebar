import Foundation

/// One noise cancelling mode as stored on the headphones (Quiet, Aware, custom slots).
public struct ModeConfig: Equatable, Sendable, Identifiable {
    public var index: UInt8
    /// Voice prompt id (two bytes). Must be written back unchanged.
    public var prompt: [UInt8]
    /// false for the built-in Quiet/Aware modes.
    public var editable: Bool
    public var configured: Bool
    public var name: String
    /// 0 = maximum noise cancelling, 10 = most ambient sound.
    public var cncLevel: UInt8
    public var autoCNC: Bool
    public var spatial: UInt8
    public var windBlock: Bool

    public var id: UInt8 { index }

    /// A custom slot that was never set up (not configured) or was deleted (named "None").
    public var isEmptySlot: Bool {
        editable && (!configured || name.trimmingCharacters(in: .whitespaces).lowercased() == "none")
    }

    /// The name to show. Modes created in the Bose app often have an empty name
    /// field and are identified only by their voice prompt ("Focus", "Commute", ...).
    public var displayName: String {
        if !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        if prompt[0] == 0, prompt[1] > 0, Int(prompt[1]) < Self.promptNames.count {
            return Self.promptNames[Int(prompt[1])]
        }
        return "Modus \(index)"
    }

    /// Voice prompt names by id (second prompt byte), from bosectl's constants.py.
    static let promptNames = [
        "None", "Quiet", "Aware", "Transparent", "Transparency", "Masking", "Comfort",
        "Commute", "Outdoor", "Workout", "Home", "Work", "Music", "Focus", "Relax",
        "Flight", "Airport", "Driving", "Training", "Gym", "Run", "Walk", "Hike",
        "Talk", "Call", "Whisper", "Hearing", "Learn", "Podcast", "Audiobook", "Calm",
        "Sleep", "Meditate", "Yoga", "Immersion", "Stereo", "Cinema",
    ]

    /// Parses the 47 byte payload of a `[31.6]` STATUS packet (prince layout).
    public init?(statusPayload p: [UInt8]) {
        guard p.count >= 47 else { return nil }
        index = p[0]
        prompt = [p[1], p[2]]
        editable = p[3] != 0
        configured = p[4] != 0
        // 32 byte field, UTF-8, null terminated.
        name = String(decoding: p[6..<38].prefix { $0 != 0 }, as: UTF8.self)
        cncLevel = p[42]
        autoCNC = p[43] != 0
        spatial = p[44]
        windBlock = p[46] != 0
    }

    /// The 39 byte payload for a `[31.6]` SETGET packet (writes this mode to the headphones).
    public var setGetPayload: [UInt8] {
        var nameField = Array(name.utf8.prefix(31))
        nameField += [UInt8](repeating: 0, count: 32 - nameField.count)
        return [index, prompt[0], prompt[1]] + nameField
            + [cncLevel, autoCNC ? 1 : 0, spatial, windBlock ? 1 : 0]
    }
}
