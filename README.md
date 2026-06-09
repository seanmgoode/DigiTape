# DigiTape iOS Controller 2.0.2

Starter iPhone app for DigiTape RX/controller/emulator.

## Modes

- **RX**: live DigiTape receiver screen for `DigiTape-RX` over BLE.
- **Settings**: sends offset and response mode to the RX bridge using the RX 2.0.2 settings characteristic.
- **Emulator**: no-hardware test mode with distance, signal, and battery sliders.
- **Diagnostics**: RSSI, packet counter, TX firmware, sensor type, and status.

## BLE compatibility

Matches RX bridge firmware 2.0.2. The ESP32 RX should stay connected to the TX, advertise as `DigiTape-RX`, and expose this BLE service to the iPhone:

- Service UUID: `6f8a1500-b5a3-4f4a-9d7f-1a2b3c4d5e6f`
- Distance Characteristic: `6f8a1501-b5a3-4f4a-9d7f-1a2b3c4d5e6f`
- Settings Characteristic: `6f8a1502-b5a3-4f4a-9d7f-1a2b3c4d5e6f`

The app accepts both 15-byte packed and 16-byte aligned `DistancePacket` payloads.

## How to run

1. Open `DigiTapeController.xcodeproj` in Xcode.
2. Select your iPhone as the run target.
3. In Signing & Capabilities, select your Apple team.
4. Build and run.
5. Start in Emulator mode first, then turn Emulator Mode off and tap **Connect to DigiTape-RX**.

## Notes

This is a first working app shell. It does not yet include OTA updates, session recording, multi-tag UWB display, or polished DigiTape branding assets.
