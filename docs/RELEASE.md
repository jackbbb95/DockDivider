# Releasing DockDivider

This is the checklist for a GitHub release. Everything ships as a signed,
notarized DMG attached to a GitHub Release; there is no App Store build.

## One-time setup

1. Join the [Apple Developer Program](https://developer.apple.com/programs/)
   and create a **Developer ID Application** certificate in Xcode or the
   developer portal. An “Apple Development” certificate cannot be used for
   distribution.
2. Confirm the identity is in your keychain:
   ```bash
   security find-identity -v -p codesigning
   ```
3. Store notarization credentials in a local keychain profile. Use an
   app-specific password from <https://appleid.apple.com>:
   ```bash
   xcrun notarytool store-credentials "DockDividerNotary" \
     --apple-id "you@example.com" \
     --team-id "YOURTEAMID" \
     --password "app-specific-password"
   ```
   The profile name and password must never be committed.

## Prepare the version

1. Bump **Version** and **Build** in the project’s General settings
   (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`).
2. Update `CHANGELOG.md`: move items from `[Unreleased]` into a new
   `## [x.y.z] - YYYY-MM-DD` section.
3. Commit the release changes and push them.
4. Run the tests locally:
   ```bash
   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
     xcodebuild -project DockDivider.xcodeproj -scheme DockDivider \
     -configuration Debug -destination 'platform=macOS' \
     -only-testing:DockDividerTests test CODE_SIGNING_ALLOWED=NO
   ```

## Build the artifact

A local signed dry run (no notarization):

```bash
NOTARIZE=0 ./scripts/release.sh
```

A real release:

```bash
NOTARY_PROFILE=DockDividerNotary ./scripts/release.sh
```

Useful overrides:

- `RELEASE_VERSION=1.0.1` — build a version without editing the project.
- `BUILD_NUMBER=2` — override the build number.
- `SIGNING_IDENTITY="Developer ID Application: …"` — pick a specific identity
  when more than one is installed.
- `DEVELOPMENT_TEAM=…` — override the team read from the project.

The script archives a universal Release, signs the app and its embedded
`divider_runner` with hardened runtime and a timestamp, verifies the signature,
notarizes and staples the app and the DMG, and writes a SHA-256 checksum.
Artifacts land in `build/release/<version>/`.

## Verify before publishing

```bash
codesign -dv --verbose=4 build/release/<version>/DockDivider.app
codesign --verify --deep --strict --verbose=2 build/release/<version>/DockDivider.app
spctl -a -vv build/release/<version>/DockDivider.app
xcrun stapler validate build/release/<version>/DockDivider-<version>.dmg
shasum -a 256 -c build/release/<version>/DockDivider-<version>.dmg.sha256
```

Then test the DMG on a **clean standard user account**:

- First launch opens without a Gatekeeper bypass.
- Onboarding appears once and does not return.
- Dragging a divider into the Dock works on a bottom and a side Dock.
- The default storage folder, a custom local folder, and Clean Up work.
- System Event actions show the Automation prompt once; the divider still works
  without granting it.
- Removing a divider from the Dock and re-dragging a new one behaves correctly.

## Publish

```bash
git tag v<version>
git push origin main --tags
```

Create a GitHub Release for the tag and attach:

- `DockDivider-<version>.dmg`
- `DockDivider-<version>.dmg.sha256`
- optionally `DockDivider-<version>.zip`

Use the matching `CHANGELOG.md` section as the release notes. Mention that the
app is notarized and that generated divider bundles are ad-hoc signed locally.

## Known, expected behavior

- **Generated divider bundles do not pass `codesign --verify --deep --strict`.**
  They carry a Finder custom icon applied after signing, so strict verification
  reports Finder metadata. `codesign --verify` succeeds and the Dock launches
  them normally. Only the DockDivider app itself is notarized.
- **System Events actions need Automation permission.** macOS prompts on first
  use; no Accessibility or Full Disk Access is required.
- **The release script never uploads.** Publishing the GitHub Release is a
  manual step so the artifact can be checked first.
