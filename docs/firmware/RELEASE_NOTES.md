# DigiTape Firmware firmware-20260702_123830

Verified firmware package for DigiTape RX/TX devices.

## Downloads

### MiniRx 1.8 AMOLED

- Target: `minirx18`
- Role: `rx`
- File: `MiniRX1.0.ino.bin`
- Size: `2,243,984` bytes
- SHA-256: `c43ed3b26deafd000dbd903d818de40482dd236e16ebb4956632ae653377544c`

### RX 2.41 AMOLED

- Target: `rx241`
- Role: `rx`
- File: `MiniRX2.41.ino.bin`
- Size: `2,258,704` bytes
- SHA-256: `7e4339ba91551f170168fcd25c7b1f8b326667f1ae2b65a6049e08aeebf0a59c`

### DigiTape TX

- Target: `tx`
- Role: `tx`
- File: `DigiTape_TX_2_0_4.ino.bin`
- Size: `1,162,448` bytes
- SHA-256: `2786e232b56e2d9688988ca29d8b48ad1bff9e05aa913c8082c3ad1146f3491f`

## Verification

- Manifest hash is included in `latest.json`.
- Firmware binaries include ECDSA P-256 SHA-256 signatures.
- Run `python3 tools/digitape_firmware.py verify-package <package>` before upload.

## Update Notes

- Use the RX, TX, or app firmware page to pick the matching device target.
- Do not flash a TX binary to an RX or RX binary to a TX. The local dashboard identifies boards before flashing.
