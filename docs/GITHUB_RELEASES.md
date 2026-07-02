# GitHub Firmware Releases

The DigiTape app and firmware downloads page use the same manifest:

`https://digitape.co/firmware/latest.json`

The manifest points at the checked-in firmware package under:

`docs/firmware/packages/digitape_firmware_20260702_123830/`

## Current Release

Release version: `3.2.1`

Targets:

- `RX_MINI` - MiniRx 1.8 AMOLED
- `RX_241` - RX 2.41 AMOLED
- `TX` - DigiTape TX / Proto1

Each firmware entry includes:

- `version`
- `boardType`
- `hardwareRevision`
- `friendlyName`
- `bytes`
- `sha256`
- `signature`
- `signatureAlgorithm`

The app blocks OTA if size or SHA-256 checks do not match.

## Website Downloads

The public download page is:

`docs/firmware/firmware.html`

It links directly to the same `.ino.bin` files used by `latest.json`.

## GitHub Release Upload

Use the GitHub CLI when available:

```sh
scripts/create_github_firmware_release.sh
```

The release should include:

- `firmware-manifest.json`
- `MiniRX1.0.ino.bin`
- `MiniRX2.41.ino.bin`
- `DigiTape_TX_2_0_4.ino.bin`

Keep `docs/firmware/latest.json`, `docs/firmware/firmware_downloads.json`, and `docs/firmware/firmware.html` aligned whenever a new package is generated.

## Manual GitHub UI Steps

1. Open `https://github.com/seanmgoode/DigiTape/releases/new`.
2. Tag: `firmware-v3.2.1`.
3. Title: `DigiTape Firmware 3.2.1`.
4. Upload the three install `.ino.bin` files and `firmware-manifest.json`.
5. Publish release.

## Future Releases

For the next release, build the three targets, regenerate the package manifest with size/hash/signature fields, update `latest.json`, update `firmware.html`, then publish the GitHub release.
