# DigiTape Firmware Security

## Current Protection

- Firmware downloads are listed in `docs/firmware/latest.json`.
- Each firmware entry includes byte size and SHA-256.
- The app blocks OTA when the downloaded size or SHA-256 does not match the manifest.
- The package manifest includes ECDSA P-256 SHA-256 signatures for each binary.
- GitHub Releases hosts the downloadable `.ino.bin` assets.

## Next Firmware-Side Checks

1. RX/TX OTA code should verify the incoming byte count before calling `Update.end()`.
2. RX/TX OTA code should verify SHA-256 before accepting the image.
3. RX/TX should reject an OTA image whose manifest `boardType` does not match the local board identity.
4. RX/TX should report the accepted manifest version and hash in `STATUS?`.

## Secure Boot

Secure boot is a board-provisioning step, not just an app setting. Do not burn eFuses until the update/recovery path is stable.

Recommended order:

1. Keep unsigned dev boards for recovery and testing.
2. Add manifest hash checks on RX/TX.
3. Add signed manifest verification on RX/TX.
4. Confirm OTA rollback/recovery.
5. Enable flash encryption and secure boot only on a test board first.

Secure boot should be treated as a production-lock step because a bad key or bad boot image can permanently block normal flashing.
