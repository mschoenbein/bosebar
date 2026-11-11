# BoseBar

A small macOS menu bar app that switches the noise cancelling mode of the **Bose QuietComfort Headphones (2023, codename "prince", product ID 0x4075)**. It keeps a persistent Bluetooth control connection (BMAP over RFCOMM), so a mode switch takes a fraction of a second.

> **Unofficial project.** BoseBar is an independent hobby project. It is not affiliated with, endorsed by, or supported by Bose Corporation. "Bose" and "QuietComfort" are trademarks of Bose Corporation and are used here only to say which headphones the app works with. Use at your own risk.

- Menu bar icon reflects the current mode (Quiet / Aware / custom)
- Menu shows device name, battery level and all modes; click one to switch
- Reconnects on its own when the headphones come back
- For custom modes: noise cancelling level (0–10) and Wind Block
- Optional "Beim Login starten" (launch at login) in the menu
- The icon is hidden while no headphones are connected; the app keeps running in the background. Launch BoseBar again to bring the icon back (for example to quit it)

## Tested on one device only

BoseBar has been tested with exactly one pair of headphones: Bose QuietComfort Headphones, firmware `1.0.6-80+f5f219b`, on macOS 27. Other units, firmware versions and Bose models are untested and may not work. The app's menu and messages are in German.

## Download

Get `BoseBar-<version>.dmg` from the [latest release](https://github.com/mschoenbein/bosebar/releases/latest), open it and drag BoseBar into the Applications folder. Requires macOS 14 or later (Apple Silicon or Intel).

**The app is not notarized by Apple**, so macOS blocks the first launch with a warning that it cannot verify the app. To allow it:

1. Try to open BoseBar once and dismiss the warning.
2. Open System Settings → Privacy & Security, scroll down and click "Open Anyway" next to the BoseBar message.

Or remove the download flag in Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/BoseBar.app
```

If you would rather not run an unverified binary, build it yourself:

## Build from source

Requirements: Xcode and `xcodegen` (`brew install xcodegen`).

```bash
xcodegen generate
```

```bash
xcodebuild -project BoseBar.xcodeproj -scheme BoseBar -configuration Release -derivedDataPath build build
```

```bash
cp -R build/Build/Products/Release/BoseBar.app /Applications/
```

On first launch macOS asks for Bluetooth permission; allow it. The app is ad-hoc signed, so macOS may ask again after a rebuild. If you dismissed the prompt, enable BoseBar under System Settings → Privacy & Security → Bluetooth.

## Development

```bash
swift test
```

To test against real hardware, run the command line tool from Terminal.app with the headphones connected. All commands run over **one** connection and each is timed:

```bash
swift run bosebar-cli status quiet aware status
```

Prefix it with `BMAP_DEBUG=1` to print all packet traffic to stderr.

Layout:

- `Sources/BMAPKit/` – protocol and Bluetooth transport, no UI
- `Sources/bosebar-cli/` – small test tool
- `App/` – SwiftUI menu bar app
- `Tools/make-icon.swift` – draws the app icon
- `Tools/release.sh` – builds the release disk image
- `project.yml` – input for xcodegen, which generates the Xcode project

## Notes

- If `bosectl` or the Bose app on a phone is using the control channel at the same time, it may be busy. The app shows this in its menu and retries every 5 seconds.
- The app only ever closes its own control channel, never the audio connection.
- Turning Wind Block on makes the firmware reset the mode's noise cancelling level (observed: raw CNC forced to 0). The level picker is disabled while Wind Block is on.
- Do not open the RFCOMM channel with `openRFCOMMChannelSync` from Swift async code: it returns early, and closing at that moment leaves an orphaned connection inside `bluetoothd` that blocks the channel for every program until the headphones reconnect. See the comment in `RFCOMMTransport.swift`.

## License

MIT, see [LICENSE](LICENSE).

## Acknowledgements

Built with [Claude Code](https://claude.com/claude-code).

The protocol knowledge comes from [bosectl](https://github.com/aaronsb/bosectl) by Aaron Bockelie (MIT License):

> MIT License – Copyright (c) 2026 Aaron Bockelie
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
