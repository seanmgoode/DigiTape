# GitHub Firmware Releases

The iOS app checks the latest GitHub Release manifest at:

`https://github.com/seanmgoode/DigiTape/releases/latest/download/firmware-manifest.json`

## Current Release

Release tag:

`v2.1`

Assets to upload:

- `INSTALL_DigiTape_RX_2_1.ino.bin`
- `INSTALL_DigiTape_TX_2_1.ino.bin`
- `firmware-manifest.json`

The manifest prepared for this release is:

`docs/firmware-manifest.github-v2.1.json`

## Create With Script

From the app repo folder:

```sh
export GITHUB_TOKEN="your_token_with_repo_release_permission"
scripts/create_github_firmware_release.sh
```

## Manual GitHub UI Steps

1. Open `https://github.com/seanmgoode/DigiTape/releases/new`.
2. Tag: `v2.1`.
3. Title: `DigiTape Firmware v2.1`.
4. Upload the RX install binaries, TX install binary, and manifest.
5. The uploaded manifest asset must be named exactly `firmware-manifest.json`.
6. Publish release.

## Future Releases

For the next release, copy the manifest, update versions, update asset URLs to the new tag, and upload it as `firmware-manifest.json` on the new release.
