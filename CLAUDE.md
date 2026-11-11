# BoseBar

macOS menu bar app (Swift 6 / SwiftUI) that controls the noise cancelling mode of Bose QuietComfort Headphones ("prince", product ID 0x4075) via the BMAP protocol over a persistent RFCOMM channel.

The owner is new to Swift: keep code plain and well commented, no clever abstractions. Chat in German; code, comments and commits in English. The app's UI strings are German.

## Layout

- `Sources/BMAPKit/` – protocol + IOBluetooth transport, no UI (SwiftPM library)
- `Sources/bosebar-cli/` – test tool for real hardware
- `App/` – menu bar app; `project.yml` is the xcodegen input, `BoseBar.xcodeproj` is generated and not committed
- `Tools/release.sh <version>` – builds the release disk image

## Commands

```bash
swift test
xcodegen generate && xcodebuild -project BoseBar.xcodeproj -scheme BoseBar -configuration Release -derivedDataPath build build
```

## Testing against hardware

- Real headphones are the only test environment; unit tests cover packet encoding/parsing only.
- The CLI cannot be run from Claude's shell: macOS kills it (Bluetooth TCC, responsible process has no usage description). Run it through Terminal.app, e.g. write a `.command` file that redirects output to a file and `open` it.
- BoseBar holds the control channel while running. Quit it (`pkill -x BoseBar`) before using the CLI or bosectl, and restart it afterwards.
- `BMAP_DEBUG=1` prints all packet traffic to stderr.
- `/usr/bin/log show --predicate 'process == "bluetoothd"'` shows why an RFCOMM open failed (`log` alone is a zsh builtin).

## Bluetooth rules (learned the hard way)

- Never call `closeConnection()` on the `IOBluetoothDevice`: it drops the audio connection. Only close our own RFCOMM channel.
- Never use `openRFCOMMChannelSync` from Swift async code. It returns early with an error while bluetoothd keeps connecting; closing then leaves an orphaned connection that blocks the channel for every program (status 911 in the bluetoothd log) until the headphones reconnect. Use `openRFCOMMChannelAsync` and wait for the delegate callback.
- Take the channel from SDP (Serial Port service, UUID 0x1101; channel 9 on the owner's unit). Do not probe other channels: 14 speaks iAP, 25 is silent.
- If every open fails with `0xe00002bc` for all tools including bosectl, suspect an orphaned connection: the headphones must be switched off and on.

## Device facts (firmware 1.0.6-80+f5f219b)

- Modes: 0 Quiet, 1 Aware (both fixed), 2–3 custom slots. A custom mode may have an empty name field; it is then named after its voice prompt id (`ModeConfig.displayName`).
- Mode switch `START [31.3]` is acked with PROCESSING and applied asynchronously; read back after ~300 ms.
- Enabling Wind Block makes the firmware reset the mode's raw CNC level to 0.
- Protocol reference: bosectl (https://github.com/aaronsb/bosectl), `python/pybmap/` and `docs/quietcomfort-headphones-prince.md`.

## Release

- Releases are ad-hoc signed and not notarized (no Developer ID certificate yet). A notarytool keychain profile `bosebar-notary` exists.
- Every rebuild changes the ad-hoc signature: macOS may ask for Bluetooth permission again and the login item may need re-enabling.
- The app does not create or overwrite custom modes on its own; it only edits the active custom mode on user action.
