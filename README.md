# DockDivider

A native macOS utility for creating visual dividers, labels, spacers, and
clickable action tiles that live directly in your Dock.

DockDivider generates self-contained `.app` bundles and native Dock spacer
files. Drag one from the app window into your Dock; there is no daemon, menu
bar agent, or background process left behind.

![macOS 13+](https://img.shields.io/badge/macOS-13.0%2B-blue)
![Swift 5](https://img.shields.io/badge/Swift-5%20language%20mode-orange)
![Xcode 16+](https://img.shields.io/badge/Xcode-16%2B-blue)

---

## Features

- **Divider styles**
  - **Line** — a native-style separator with configurable thickness, height,
    opacity, color, and orientation.
  - **Dashed** — a segmented separator whose dash count and spacing are
    derived from thickness, height, and opacity so every resolution matches.
  - **Dot** — a small centered circle.
  - **Label** — horizontal or vertical text, or an SF Symbol.
  - **Spacer** — true native Dock spacers (`.dockspace`, `.docksmallspace`,
    `.dockflexspace`) when no click action or tooltip is configured.
  - **Image** — PNG, JPEG, HEIC, TIFF, or SVG artwork with scale, offset,
    opacity, and corner-radius controls.
- **Live Dock preview** with light/dark glass and wallpaper context.
- **Dock-aware orientation** for bottom and side Docks.
- **Optional click actions**
  - Launch a set of apps and web URLs.
  - Run an Apple Shortcut.
  - Run a shell command or a chosen script, in the background or a terminal.
  - Built-in system actions such as Hide Others, Toggle Dark Mode, Empty Trash,
    Mission Control, and Activity Monitor.
- **Drag-to-Dock workflow** with revisioned background staging, so an edited
  divider is never dragged with stale content.
- **Draft persistence** in Application Support, separate from `UserDefaults`.
- **First-run onboarding** with a one-time welcome sheet and starter presets
  (Line, Dashed, Dot, Label, Spacer).
- **Storage management** showing total disk usage and a confirmation-based
  cleanup sheet.
- **Accessibility** labels, keyboard-reachable drag fallback, and
  validation-before-drag for incomplete configurations.

---

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 16.0 or later (the project uses filesystem-synchronized groups and the Swift 5 language mode)
- No third-party dependencies

DockDivider is distributed directly, outside the Mac App Store. The app is not
sandboxed because it creates and repairs executable bundles in a folder you
choose, and it ad-hoc signs each generated bundle so the Dock can launch it.

---

## Building and running

```bash
git clone https://github.com/jackbbb95/DockDivider.git
cd DockDivider
open DockDivider.xcodeproj
```

Select the **DockDivider** scheme and **My Mac**, then press `Cmd+R`.
Run the test suite with `Cmd+U`, or from the command line:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project DockDivider.xcodeproj \
  -scheme DockDivider \
  -configuration Debug \
  -destination 'platform=macOS' \
  -only-testing:DockDividerTests test \
  CODE_SIGNING_ALLOWED=NO
```

---

## Storage and safety

Generated bundles live in `~/Library/Application Support/DockDividers` by
default. Choose **Change…** in the footer to use a different root; DockDivider
creates a `DockDividers` subfolder inside it (unless the selected folder is
already named that).

Each generated bundle contains:

```text
Divider-XXXXXXXX.app/
└── Contents/
    ├── Info.plist
    ├── PkgInfo
    ├── MacOS/
    │   └── divider_runner
    └── Resources/
        ├── AppIcon.icns
        ├── ActionConfig.json
        ├── DividerModel.json
        ├── CustomImage.png        # image style only
        └── .dockdivider.json      # ownership/version marker
```

The divider artwork is also attached as a Finder custom icon (`Icon\r` plus
Finder metadata) so the Dock shows the bare line instead of wrapping it in the
system app-icon squircle. That attachment happens after the bundle is ad-hoc
signed, so generated bundles pass `codesign --verify` but not
`codesign --verify --deep --strict`. This only affects signature inspection of
local files; the Dock launches them normally.

Deleting a bundle breaks the Dock icon that points to it. Use **Clean Up…** to
review bundles that are no longer referenced by the Dock; live and currently
staged bundles are always excluded. The folder's `README.txt` explains the same
rules for anyone browsing it in Finder.

Changing the storage folder does not move dividers that are already in the Dock.
They keep launching from the old folder, and **Clean Up…** only reviews the
current one. DockDivider warns when this happens; remove those Dock icons before
deleting the old folder.

DockDivider never edits `com.apple.dock.plist`, never runs `killall Dock`, and
never deletes files without an explicit confirmation.

---

## Architecture

- **`DockDivider.app`** — SwiftUI editor, live preview, icon renderer, bundle
  synthesizer, storage maintenance, and drag staging.
- **`divider_runner`** — a small standalone Mach-O executable embedded in each
  generated bundle. It reads `ActionConfig.json`, performs the configured
  action, and exits. The shared action model is compiled from
  `Shared/ActionConfig.swift` into both targets so they cannot drift.
- **`StorageLocationStore`** — owns the selected storage folder and its
  security-scoped bookmark.
- **`StagingController`** — revisioned staging state machine, drag ownership,
  and cleanup of superseded artifacts.
- **`BundleRepairer`** — throttled repair passes with off-main scanning and
  signing, keeping launch and activation responsive.
- **`DraftPersistence`** — saves the last design as `Draft.json` outside
  `UserDefaults`.

The model layer (`DividerModel`, `ActionConfig`) is pure Foundation. AppKit and
SwiftUI helpers live in separate extensions or views.

---

## Privacy

DockDivider collects no analytics and makes no network requests. Generated
bundles run only when you click them in the Dock. Actions that drive System
Events (Toggle Dark Mode, Toggle Mute) are AppleScript, so macOS may ask for
Automation permission; the divider still works without it, minus that action.
See `DockDivider/PrivacyInfo.xcprivacy` for the required-reason API
declarations.

---

## License

MIT License. See [LICENSE](LICENSE) for details.
