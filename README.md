# DigiTape iOS Controller 2.1

iPhone and Apple Watch app for DigiTape RX/TX control, TAG distance display, OTA updates, and emulator testing.

## Modes

- **RX/TX**: live DigiTape distance screen over BLE, with route switching.
- **TAG**: TX-side RYUW/UWB TAG distance display and diagnostics.
- **Watch**: Apple Watch companion display for the current phone distance, including TAG.
- **Emulator**: no-hardware test mode with distance, signal, and battery sliders.
- **Diagnostics**: firmware updates, RSSI, packet age, TX voltage, sensor type, and TAG status.

## BLE compatibility

Matches the current DigiTape RX/TX firmware line. The ESP32 RX should stay connected to the TX, advertise as `DigiTape-RX`, and expose this BLE service to the iPhone:

- Service UUID: `6f8a1500-b5a3-4f4a-9d7f-1a2b3c4d5e6f`
- Distance Characteristic: `6f8a1501-b5a3-4f4a-9d7f-1a2b3c4d5e6f`
- Settings Characteristic: `6f8a1502-b5a3-4f4a-9d7f-1a2b3c4d5e6f`

The app accepts legacy `DistancePacket` payloads and newer payloads with TX input voltage appended.

## How to run

1. Open `DigiTape.xcodeproj` in Xcode.
2. Select your iPhone as the run target.
3. In Signing & Capabilities, select your Apple team.
4. Build and run.
5. Start in Emulator mode first, then turn Emulator Mode off and tap **Connect**.

## Notes

OTA updates, TX/RX routing, TAG distance, and Watch display are available in the app. Session recording and multi-tag UWB display are still future work.

## Documentation

- App guide: `docs/APP_GUIDE.md`
- App releases: `docs/RELEASES.md`
- Product release tracker: `../../../Documentation/RELEASE_TRACKER.md`
