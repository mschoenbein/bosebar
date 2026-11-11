# BoseBar

Menüleisten-App für macOS, die den Noise-Cancelling-Modus der **Bose QuietComfort Headphones (2023, „prince“, Product-ID 0x4075)** umschaltet. Die App hält eine dauerhafte Bluetooth-Steuerverbindung (BMAP über RFCOMM), dadurch dauert ein Wechsel nur Sekundenbruchteile.

- Menüleisten-Icon zeigt den Modus (Quiet / Aware / Custom)
- Menü: Gerätename, Akku in %, alle Modi zum Anklicken
- Verbindet sich selbst neu, wenn der Kopfhörer wieder da ist
- Ohne verbundenen Kopfhörer ist das Icon ausgeblendet; die App läuft unsichtbar weiter. BoseBar erneut starten blendet das Icon wieder ein (z. B. zum Beenden)

## Bauen und installieren

Voraussetzungen: Xcode, `xcodegen` (`brew install xcodegen`).

```bash
xcodegen generate
```

```bash
xcodebuild -project BoseBar.xcodeproj -scheme BoseBar -configuration Release -derivedDataPath build build
```

```bash
cp -R build/Build/Products/Release/BoseBar.app /Applications/
```

Beim ersten Start fragt macOS nach der Bluetooth-Berechtigung – erlauben. Die App ist nur ad-hoc signiert; nach einem Neubau kann macOS die Frage erneut stellen.

## Entwicklung

```bash
swift test
```

Test gegen echte Hardware (in Terminal.app ausführen, Kopfhörer verbunden). Mehrere Befehle laufen über **eine** Verbindung, jeder mit Zeitmessung:

```bash
swift run bosebar-cli status quiet aware status
```

`BMAP_DEBUG=1` davor gibt den kompletten Paketverkehr auf stderr aus.

Aufbau:

- `Sources/BMAPKit/` – Protokoll und Bluetooth-Transport, ohne UI
- `Sources/bosebar-cli/` – kleines Testwerkzeug
- `App/` – SwiftUI-Menüleisten-App
- `project.yml` – Vorlage für das Xcode-Projekt (xcodegen)

## Hinweise

- Läuft gleichzeitig `bosectl` oder die Bose-App auf dem iPhone, kann der Steuerkanal belegt sein. Die App zeigt das im Menü an und versucht es alle 5 Sekunden erneut.
- Die App schließt immer nur ihren eigenen Steuerkanal, nie die Audio-Verbindung.

## Lizenz

MIT, siehe [LICENSE](LICENSE). BoseBar ist ein privates Projekt und steht in keiner Verbindung zur Bose Corporation.

## Danksagung

Das Protokollwissen stammt aus [bosectl](https://github.com/aaronsb/bosectl) von Aaron Bockelie (MIT-Lizenz):

> MIT License – Copyright (c) 2026 Aaron Bockelie
>
> Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
