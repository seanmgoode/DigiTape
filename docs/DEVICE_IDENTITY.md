# DigiTape Device Identity

Every DigiTape board should expose the same identity fields over serial, BLE diagnostics, and future OTA manifests.

## Required Fields

- `deviceId`: unique stable board ID, normally derived from ESP MAC/eFuse.
- `boardType`: `TX`, `RX_241`, or `RX_MINI`.
- `hardwareRevision`: physical board/display revision, such as `2.41`, `1.8`, or `prototype`.
- `firmwareVersion`: app-visible firmware version, currently `3.2.1`.
- `groupId`: paired DigiTape network/group ID.
- `friendlyName`: user-facing board name, such as `Proto1`, `RX`, or `MiniRx`.

## Current Release Defaults

| Target | Friendly Name | Board Type | Hardware Revision | Firmware |
| --- | --- | --- | --- | --- |
| TX | Proto1 | DigiTape TX | prototype | 3.2.1 |
| RX_241 | RX | RX 2.41 AMOLED | 2.41 | 3.2.1 |
| RX_MINI | MiniRx | MiniRx 1.8 AMOLED | 1.8 | 3.2.1 |

## Serial Command Shape

`STATUS?` and `HEALTH?` should include the identity block:

```json
{
  "deviceId": "E4107AD4DB1C",
  "boardType": "RX_MINI",
  "hardwareRevision": "1.8",
  "firmwareVersion": "3.2.1",
  "groupId": "digitape-default",
  "friendlyName": "MiniRx"
}
```

The app and DigiTape Dev should use these fields to prevent flashing a TX build to an RX board.
