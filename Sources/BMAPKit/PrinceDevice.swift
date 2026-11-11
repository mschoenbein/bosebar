/// Everything specific to the Bose QuietComfort Headphones (2023), codename "prince".
/// A second headphone model would get its own file like this one.
public enum PrinceDevice {
    public static let productID = 0x4075
    /// RFCOMM channels to try if the headphones' service list does not name the
    /// serial port channel. The channel differs between units.
    public static let channels: [UInt8] = [8, 2, 9]

    // BMAP addresses (function block, function).
    static let firmware: (UInt8, UInt8) = (0, 5)
    static let productName: (UInt8, UInt8) = (1, 2)
    static let battery: (UInt8, UInt8) = (2, 2)
    static let allModes: (UInt8, UInt8) = (31, 1)
    static let currentMode: (UInt8, UInt8) = (31, 3)
    static let modeConfig: (UInt8, UInt8) = (31, 6)

    public static let quietIndex: UInt8 = 0
    public static let awareIndex: UInt8 = 1
}
