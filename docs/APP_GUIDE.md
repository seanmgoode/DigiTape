# DigiTape iOS App Guide

Current app project: **DigiTape iOS Controller 2.1**

## Main Modes

- **Home** shows the current distance and the active route, `RX` or `TX`.
- **RX route** connects to `DigiTape-RX`, the normal bridge path where RX stays paired to TX.
- **TX route** connects directly to `DigiTape-TX` for direct control or TX OTA updates.
- **Settings** shows firmware updates, connection state, route, RSSI, sensor, packet count, and emulator controls.
- **Emulator** is for app testing without hardware.

## OTA Updates

The app checks GitHub Releases automatically when it opens. Use Settings > Firmware Update to pick the listed RX or TX firmware and start OTA.

- To update RX, connect to RX and choose `RX 2.1`.
- To update TX, switch to TX, wait for route `TX`, then choose `TX 2.1`.
- Use `.ino.bin` files for app OTA.
- Use `.merged.bin` files only for full USB flashing.

## Expected Firmware

- RX: `2.1`
- TX: `2.1`

## BLE UUIDs

- Service: `6f8a1500-b5a3-4f4a-9d7f-1a2b3c4d5e6f`
- Distance: `6f8a1501-b5a3-4f4a-9d7f-1a2b3c4d5e6f`
- Settings: `6f8a1502-b5a3-4f4a-9d7f-1a2b3c4d5e6f`
- Status: `6f8a1503-b5a3-4f4a-9d7f-1a2b3c4d5e6f`
- OTA Control: `6f8a15f1-b5a3-4f4a-9d7f-1a2b3c4d5e6f`
- OTA Data: `6f8a15f2-b5a3-4f4a-9d7f-1a2b3c4d5e6f`
- OTA Status: `6f8a15f3-b5a3-4f4a-9d7f-1a2b3c4d5e6f`

## Cloud Firmware

The app checks the HTTPS firmware manifest automatically, shows available RX/TX firmware, downloads the selected `.ino.bin`, and starts OTA from Settings.

Manifest format example:

- `docs/firmware-manifest.example.json`

The manifest URL is set in `DigiTapeBLEManager.swift` as `firmwareManifestURL` and points to GitHub Releases latest download: `https://github.com/seanmgoode/DigiTape/releases/latest/download/firmware-manifest.json`.

See `docs/GITHUB_RELEASES.md` for the release setup.
