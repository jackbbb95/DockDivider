# Product Requirements Document (PRD): macOS Dock Divider & Spacer Utility

**Document Version:** 1.2  
**Date:** October 30, 2026  
**Target Platform:** macOS 13.0 (Ventura) or later (Universal Binary: Apple Silicon & Intel)  
**Distribution Channel:** Direct distribution outside the Mac App Store (no App Sandbox; generated bundles are ad-hoc signed)  
**App Architecture:** Standalone SwiftUI utility window (no background daemon or menu bar agent)

---

## 1. Executive Summary & Product Vision

macOS does not provide a native user interface for organizing the Dock with visual dividers or blank spacers. Historically, users have relied on hidden Terminal commands (`defaults write com.apple.dock ...`) paired with `killall Dock` for blank spacers, or tedious multi-step workarounds (creating empty files, renaming to `.app`, designing custom transparent PNG lines in Figma, and manually pasting them into Finder's "Get Info" window) to get visual separator lines.

This utility solves that friction by providing a **lightweight, standalone application** that generates bespoke, self-contained `.app` bundles on the fly with pixel-perfect icons (native-style vertical lines, dots, custom text/SF Symbol labels, blank spacers, or custom images). Users simply configure their divider—and optionally assign a **Smart Click Action** (such as launching a group of apps, triggering a system utility action, or creating an "Invisible App Launcher" using a blank spacer)—and **drag and drop it directly from the app window onto their Dock**.

Because the utility relies on standard macOS file drag-and-drop (`NSItemProvider` / `NSPasteboard` with file URLs) rather than modifying `com.apple.dock.plist` or terminating the Dock process, it never needs Accessibility permissions and never runs a background process. Actions that drive System Events (Toggle Dark Mode, Toggle Mute) are AppleScript, so macOS may show an Automation prompt the first time one runs. It is distributed directly rather than through the Mac App Store: the app creates, repairs, and ad-hoc signs executable bundles in a user-selected folder, which is incompatible with App Sandbox requirements. Once dropped into the Dock, dividers persist indefinitely with **zero background processes** required.

---

## 2. Goals & Non-Goals

### Goals
* **Effortless Dock Organization:** Allow users to create and place unlimited visual dividers, custom labels, and spacers into the macOS Dock in seconds via intuitive drag-and-drop.
* **Direct-Distribution Safety:** Avoid private APIs, `com.apple.dock.plist` writes, and `killall Dock`. Generated bundles are ad-hoc signed and repaired in place after app upgrades.
* **Zero Background Footprint:** Ensure generated dividers are self-contained, valid `.app` bundles that require no background daemon, helper agent, or menu bar app running to stay in the Dock.
* **Silent or Smart Execution When Clicked:** Ensure that clicking a standard divider does nothing silently (no "damaged app" warning, no Dock bounce, no focus stealing), while allowing users to optionally bind **Click Actions** (App/URL Launcher, Apple Shortcuts, Shell Commands, System Actions, or Invisible Spacer Launchers).
* **Visual Fidelity:** Provide a default vertical line preset that closely matches the native macOS Dock separator (separating apps from recent/minimized items), alongside clean presets, SF Symbol/monogram labels, and custom image controls.
* **Safe Storage Lifecycle:** Keep the current draft across launches, show where generated files live, and make cleanup explicit and confirmation-based.

### Non-Goals
* **No Dock Mutation:** The app does not edit `com.apple.dock.plist` or restart the Dock. It reads Dock references only to identify unused generated bundles for an optional cleanup sheet; removal remains the user's action in the Dock.
* **No Background Theme Watcher:** The app will not run a background process to dynamically swap icons when macOS switches between Light and Dark mode. Instead, the default divider uses a balanced translucent tone (or user-selected tint/opacity) that looks great across wallpapers and themes.
* **No Plist/Terminal Injection:** The app will not programmatically restart the Dock or mutate system preference files.

---

## 3. Technical Feasibility & Distribution Strategy

### 3.1 How Drag-and-Drop Works Without Sandbox Restrictions
Wait-free Dock insertion works because the macOS Dock natively accepts any valid `.app` bundle dragged from Finder or an application window using the `public.file-url` pasteboard type.
* **No Permissions Needed:** When a user initiates a drag from the utility's "Drag Well", the app writes a uniquely named `.app` bundle into a persistent local directory and hands the `file://` URL to `NSItemProvider`. The user drops it directly into their desired position on the Dock.
* **Persistence Location:** Generated bundles live in `~/Library/Application Support/DockDividers/` by default. Users can choose a different root with `NSOpenPanel`; the app stores a security-scoped bookmark and places generated content in a `DockDividers` subfolder so the selected root never fills with invisible app bundles.
* **Direct Distribution:** Because DockDivider writes executable bundles, repairs them, and ad-hoc signs them with `/usr/bin/codesign`, it is distributed directly with Hardened Runtime enabled and App Sandbox disabled. It intentionally ships outside the Mac App Store.
* **Ownership Marker:** Every current bundle contains `Contents/Resources/.dockdivider.json`, recording the app version, runner version, and creation date. Repair recognises marked bundles and legacy bundles by their runner executable, and only rewrites a bundle when a plist, orientation, icon, or marked-runner repair is needed.

### 3.2 How Spacers & "Invisible App Hiders" Work via Drag-and-Drop
Passive spacers use the native Dock spacer file types rather than an app bundle:
* **Native Blank Spacer:** A zero-byte `.dockspace`, `.docksmallspace`, or `.dockflexspace` file. Dragging it into the Dock makes Dock.app create a true `DOCKSpacerTile`, with no tooltip bubble and no click target.
* **Invisible App Hider / Secret Launcher:** When a spacer needs a click action or a hover tooltip, DockDivider falls back to an `.app` bundle with a transparent icon and an invisible display name. This keeps the same visual gap while allowing an app, URL set, Shortcut, shell command, or system action to run when clicked.

### 3.3 Anatomy of a Generated Divider `.app` Bundle
Whenever a user configures a divider, a staging bundle is prepared so it is immediately ready when a drag gesture starts. Each generated bundle gets a unique UUID to allow unlimited duplicates in the Dock:

```text
Divider-<UUID8>.app/
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

* **`Info.plist` Configuration:**
  * `CFBundleIdentifier`: `com.dockdivider.item.<UUID>` (Unique ID ensures macOS treats every dragged divider as a distinct Dock item).
  * `CFBundleName` / `CFBundleDisplayName`: Defaults to a zero-width Unicode name so hovering over the divider shows a minimal pill rather than "Divider-123", or uses the user's custom Hover Tooltip string if specified.
  * `LSUIElement`: `true` (prevents the dummy app from appearing in the `Cmd+Tab` switcher, Force Quit menu, or showing an active dot underneath it).
  * `CFBundleIconFile` is intentionally omitted so IconServices does not wrap the rendered divider in a default app-icon squircle.
* **`MacOS/divider_runner` Executable & `ActionConfig.json`:**
  * A pre-compiled helper Mach-O binary is copied from the app's Resources into each bundle. It is ad-hoc signed as part of the generated bundle (`codesign --sign -`), not with a developer certificate.
  * When clicked in the Dock, `divider_runner` launches silently (`LSUIElement = true`), reads `Contents/Resources/ActionConfig.json`, executes the configured action (or immediately exits if set to `none`), and terminates with zero Dock bounce.
  * `DividerModel.json` preserves the visual configuration for repair and inspection. Custom artwork is stored once as `Resources/CustomImage.png`; the JSON omits the raw image data.

---

## 4. User Experience & Functional Requirements

### 4.1 Core User Flow
1. **Launch App:** User opens the utility. A single-window native macOS interface appears (~900x600 pt), restoring the last design from `Draft.json`. On a fresh install, a one-time welcome sheet explains the drag-to-Dock workflow; dismissing it marks onboarding complete in `UserDefaults`.
2. **Choose Style:** User selects between **Vertical Line**, **Dot / Pill**, **Custom Label (Text / SF Symbol)**, **Blank Spacer**, or **Custom Image**.
3. **Customize Appearance:** User tweaks thickness, height/scale, vertical offset, color/opacity, or hover tooltip and sees a real-time preview inside a simulated macOS Dock bar at the top of the window.
4. **Assign Click Action (Optional):** User leaves "When Clicked" on *Do Nothing (Silent)*, or selects a smart action (e.g., *Open Apps/URLs*, *System Utility Action*, *Run Apple Shortcut*, or *Run Terminal Command*).
5. **Drag to Dock:** User clicks and drags the preview tile from the **"Drag to Dock" well** directly into their macOS Dock at the exact spot they want it.
6. **Repeat or Quit:** The Drag Well automatically regenerates a fresh unique UUID behind the scenes so the user can immediately drag the exact same tile multiple times. User closes the window (`Cmd+Q`) when finished.

---

### 4.2 Feature Specifications

#### P0: Built-in Visual Presets & Styles
1. **Native Match Vertical Line (Default):**
   * Pre-configured to match the native macOS Dock separator (1px–1.5px effective stroke width at 1x, crisp retina rendering at 2x, rounded caps, ~65% height of the icon canvas, slight vertical offset to align with squircle app icons, white with 35–50% opacity for universal Light/Dark mode compatibility).
2. **Blank Spacer (and "Invisible App Hider"):**
   * Passive spacers use a native zero-byte `.dockspace`, `.docksmallspace`, or `.dockflexspace` file, giving a true Dock spacer tile with no tooltip and no click target.
   * When paired with a Click Action or custom hover tooltip, the same visual gap becomes an `.app` bundle with a transparent icon and an invisible display name, acting as an **Invisible App Hider / Secret Trigger**.
3. **Minimalist Alternates:**
   * **Single Dot / Pill:** A small centered circle or short vertical pill.
   * **Dashed / Dotted Line:** Subtle segmented vertical divider.

#### P0: Visual Customization Controls
* **Color & Opacity:**
  * Quick-select swatches: *Native Adaptive Gray/White*, *Pure White*, *Charcoal/Dark*, plus a standard macOS `ColorPicker` with alpha/opacity slider (10% to 100%).
* **Line Thickness / Weight:** Slider from Thin (1pt) to Bold (8pt).
* **Length / Scale:** Slider from 20% to 100% of Dock icon height.
* **Vertical Offset:** Slider (`-25%` to `+25%`) to nudge the divider up or down so it aligns optically with neighboring Dock icons.

#### P0: Drag-and-Drop Generator Well
* A prominent interactive card/well displaying the rendered icon at actual size.
* Supports native `onDrag` gesture providing the generated `.app` file URL.
* Automatically generates a new unique `.app` bundle instance after every completed drag operation so users can drag out 5 dividers in 5 seconds without clicking a "Generate New" button.

#### P1: Smart Click Actions & System Utilities
Users can configure what happens when a divider or blank spacer is clicked in the Dock via `ActionConfig.json`:
1. **Do Nothing (Default):** Immediately exits (`return 0;`). Zero bounce, zero focus change.
2. **Launch Section (Open Multiple Apps & URLs):**
   * User selects 1 or more `.app` bundles (via `NSOpenPanel`) and/or enters a list of URLs.
   * Clicking the divider launches all selected apps/URLs simultaneously via `NSWorkspace.shared.open(...)` — acting as a one-click workspace launcher (e.g., clicking the "Dev" divider opens Xcode, iTerm, and GitHub).
   * When combined with the **Blank Spacer** preset, this functions as an **Invisible App Hider** in the Dock.
3. **Built-in System Utility Actions:**
   * **Hide All Other Apps ("Boss Key"):** Uses `NSWorkspace.shared.hideOtherApplications()` to instantly declutter the screen.
   * **Start Screensaver / Lock Screen:** Launches `/System/Library/CoreServices/ScreenSaverEngine.app`.
   * **Open Screenshot & Recording UI:** Launches `/System/Applications/Utilities/Screenshot.app`.
   * **Trash:** Opens the Trash in Finder, or empties it after an in-app confirmation.
   * **Other utilities:** Toggle Dark Mode, Toggle Mute, Mission Control, Launchpad, Activity Monitor, Digital Color Meter, Clear Clipboard, Sleep Displays, Downloads, and AirDrop. Actions that are unavailable on the current macOS version are hidden from the picker.
4. **Run Apple Shortcut:**
   * User chooses a Shortcut name from the installed list (or types one manually). Clicking the divider invokes `/usr/bin/shortcuts run <name>`, falling back to the `shortcuts://run-shortcut` URL if the command-line tool is unavailable.
5. **Run Terminal Command / Shell Script:**
   * User enters a custom shell command or chooses a `.sh` script to execute on click, either in a terminal window or silently through a detached `/bin/zsh` process.

#### P1: Custom Labels (Hover Tooltips, Monograms & SF Symbols)
1. **Dock Hover Tooltip Label:**
   * Toggle between **Invisible (`\u{200B}`)** (default) and **Custom Hover Text** (e.g., `"Work"`, `"Social"`, `"Dev"`). Hovering over the divider in the Dock shows the native macOS Dock label pill as a clean section title.
2. **Visual Monogram / SF Symbol Divider Style:**
   * Allows rendering a 1–3 character text badge (e.g., `DEV`, `AI`, `>_`) either horizontally or stacked vertically, OR choosing from macOS's built-in **SF Symbols** library rendered with customizable scale, vertical offset, and opacity.

#### P1: Custom Image Mode
* **Image Import:** File picker or drag-and-drop zone accepting `.png`, `.svg`, `.heic`, or `.jpg`.
* **Transform Controls:**
  * **Scale Slider:** `10%` to `150%` (scales the image relative to the 1024x1024 icon canvas while preserving aspect ratio).
  * **Vertical Offset Slider:** `-50%` to `+50%` (allows shifting the custom graphic up or down to align with Dock icons).
  * **Opacity Slider:** `10%` to `100%`.

---

## 5. UI / Wireframe Concept

```text
+-------------------------------------------------------------------+
| ● ● ●                    Dock Divider                             |
+-------------------------------------------------------------------+
|                                                                   |
|   +-----------------------------------------------------------+   |
|   |  [Finder]  [Safari]   |   [Messages]   •   [Settings]     |   |
|   +-----------------------------------------------------------+   |
|                     Live Dock Alignment Preview                   |
|                                                                   |
|   Style: (•) Line  ( ) Dot  ( ) Label/Symbol  ( ) Spacer  ( ) Img |
|                                                                   |
|   -------------------------------------------------------------   |
|   Appearance                                                      |
|   Color / Tint:     [⚪ White ] [⚫ Dark ] [🎨 Custom]            |
|   Opacity:          [=============O------]  75%                   |
|   Thickness:        [===O----------------]  1.5 px                |
|   Height / Scale:   [============O-------]  65%                   |
|   Vertical Offset:  [---------O----------]   0 px                 |
|   Hover Tooltip:    [ Invisible (None)   ] (e.g. "Work", "Dev")   |
|   -------------------------------------------------------------   |
|   Click Behavior (Optional)                                       |
|   When Clicked:     [ Launch Apps / URLs (Invisible Hider)   ▾ ]  |
|   Target Apps:      [ + Add App... ]  (Xcode.app, Warp.app)       |
|   -------------------------------------------------------------   |
|                                                                   |
|        +-------------------------------------------------+        |
|        |                      |                          |        |
|        |                      |    <-- Drag Me to Dock   |        |
|        |                      |                          |        |
|        +-------------------------------------------------+        |
|         Drag this tile directly into your macOS Dock.             |
|         To remove a divider later, drag it out of the Dock.       |
+-------------------------------------------------------------------+
```

---

## 6. Technical Architecture & Implementation Details

### 6.1 Tech Stack
* **Language:** Swift 5 language mode (built with current Xcode; deployment target macOS 13.0)
* **UI Framework:** SwiftUI (single `Window` scene with `.windowResizability(.contentSize)`)
* **Graphics & Icon Pipeline:** `CoreGraphics` / `ImageRenderer` -> `NSImage` -> `.icns` generation via `CGImageDestinationCreateWithURL` (`UTType.icns`), with one-time image downsampling and a render cache.
* **Helper Executable (`divider_runner`):** Lightweight Swift/AppKit executable compiled as a separate target and embedded into the main app's Resources. The action model is shared with the app via `Shared/ActionConfig.swift`.

### 6.2 `ActionConfig.json` Schema (For Click Actions)
Each generated `.app` bundle includes `Contents/Resources/ActionConfig.json`:

```json
{
  "schemaVersion": 1,
  "actionType": "openAppsAndURLs",
  "appBundleURLs": [
    "/Applications/Xcode.app",
    "/Applications/Utilities/Terminal.app"
  ],
  "webURLs": [
    "https://github.com"
  ],
  "systemAction": "hideOthers",
  "shortcutName": "",
  "shellCommand": "",
  "runInTerminal": false
}
```
Supported `actionType` values:
* `"none"` (Default: exits immediately)
* `"openAppsAndURLs"` (Opens listed `/Applications` paths or file URLs and web URLs via `NSWorkspace`)
* `"systemAction"` (for example `"hideOthers"`, `"startScreensaver"`, `"screenshot"`, `"openTrash"`, `"emptyTrash"`, `"toggleDarkMode"`, `"toggleMute"`, `"missionControl"`, `"activityMonitor"`, `"sleepDisplays"`)
* `"runShortcut"` (Runs `/usr/bin/shortcuts run <name>`)
* `"shellCommand"` (Runs the command through a detached `/bin/zsh`, optionally in a terminal window)

### 6.3 Dynamic `.icns` Generation Pipeline
macOS Dock icons look sharpest when provided as a multi-resolution `.icns` file rather than a single bitmap pasted onto a folder.
1. Render the user's configuration (line, dot, SF Symbol/monogram, transparent spacer, or transformed custom image) with CoreGraphics at standard icon resolutions (`16x16`, `32x32`, `64x64`, `128x128`, `256x256`, `512x512`, and a single `1024x1024` slot) so the Dock can pick the best representation.
2. Write the representations into an `.icns` container using `ImageIO` (`CGImageDestinationCreateWithURL(url, UTType.icns.identifier as CFString, count, nil)`).
3. Assemble the bundle in a hidden `.staging-*` folder: copy the runner, write `Info.plist`, `PkgInfo`, `ActionConfig.json`, the divider model, optional `CustomImage.png`, and the ownership marker.
4. Ad-hoc sign the finished bundle (`codesign --force --deep --sign -`), then apply the un-enclosed artwork as a Finder custom icon and notify the filesystem so Finder and the Dock pick it up immediately. The custom icon is attached after signing, which is why generated bundles are valid for `codesign --verify` but not `--deep --strict`.
5. Hand the rendered `NSImage` to the staging pipeline instead of re-rendering it, so the icon the Dock shows matches the preview.

### 6.4 Orphaned File Hygiene (Storage Cleanup)
Since the app has no active divider list and generates a staging `.app` bundle whenever the draft changes, a user might tweak sliders and leave several unused bundles behind.
* **Disk Footprint:** Each generated `.app` bundle includes the compiled runner and a multi-resolution `.icns`; current debug builds are a few hundred kilobytes. Even 100 dividers use a small amount of disk space, but abandoned staging bundles still add up.
* **Staging Optimization:** Draft changes are debounced, staging happens off the main actor in a temporary directory, and only the latest revision is published. Replaced or rejected bundles are deleted automatically.
* **Cleanup:** A storage census compares generated bundles with the Dock's current file references. The user can review unused items in a sheet and move them to the Trash; live, staged, and in-flight bundles are excluded. Repair never rewrites bundles that lack the DockDivider ownership marker.

---

## 7. Edge Cases & Mitigations

| Edge Case | Impact | Mitigation |
| :--- | :--- | :--- |
| **User clicks a passive divider in the Dock** | Could show an error dialog ("App is damaged") or bounce in the Dock. | Include the valid, ad-hoc signed `divider_runner` executable with `LSUIElement = true` in `Info.plist`. When `actionType == "none"`, it exits immediately with no running indicator. |
| **macOS Gatekeeper / Quarantine on generated `.app`** | macOS might flag dynamically created `.app` bundles if unsigned or modified incorrectly. | Remove quarantine attributes, ad-hoc sign each finished bundle, and keep dynamic data (`AppIcon.icns`, `ActionConfig.json`, `DividerModel.json`) in `Contents/Resources/`. The Finder custom icon is attached after signing, so `codesign --verify` succeeds while `--deep --strict` reports Finder metadata; the Dock still launches the local bundle normally. |
| **User drags the same config multiple times** | macOS Dock ignores dragging the *exact same* `.app` path twice (it just moves the existing icon). | Every drag operation publishes a fresh `.app` bundle with a new `UUID` in its filename and `CFBundleIdentifier`. |
| **User deletes the utility app later** | Bundles in a custom folder survive; bundles in an app container would not. | Default to `~/Library/Application Support/DockDividers`, support a user-selected root with a security-scoped bookmark, and warn when the selected folder is inside an app container. |
| **User changes the storage folder** | Dock icons placed earlier keep pointing at the old folder, where Clean Up no longer looks. | Warn at switch time when the old folder still backs Dock icons, and point the user at the old folder before they delete it. |
| **App update changes action schema or runner behavior** | Older generated bundles could behave differently from the current editor. | Stamp each bundle with an ownership/runner-version marker and repair marked bundles whose runner version differs. Legacy unmarked bundles keep working and are migrated only when another repair (plist, orientation, or icon) touches them. |

---

## 8. Development Milestones

* **Milestone 1: Core Generator Engine & `divider_runner` (Day 1–2)**
  * Build the `.icns` generator in CoreGraphics/ImageIO.
  * Build the `divider_runner` helper target that reads `ActionConfig.json` and executes `none`, `openAppsAndURLs`, `systemAction`, `runShortcut`, and `shellCommand`.
  * Build the `.app` bundle synthesizer (`Info.plist`, `LSUIElement`, unique UUID per drag) and verify drag-and-drop onto the macOS Dock.
* **Milestone 2: SwiftUI Interface & Visual Presets (Day 3–4)**
  * Implement the live Dock preview bar and customization sliders (thickness, height, vertical offset, color/opacity).
  * Fine-tune the "Native Match" preset against macOS Sequoia/Sonoma's built-in Dock separator in both Light and Dark modes.
* **Milestone 3: Smart Click Actions, Custom Labels & Image Mode (Day 5–6)**
  * Add the Click Behavior configuration UI (App/URL picker, System Action presets, Shortcut/Command inputs, and "Invisible App Hider" workflow).
  * Add Custom Labels (Hover Tooltip input + Monogram/SF Symbol renderer) and Custom Image import (`PNG`/`SVG`) with scale and vertical offset controls.
* **Milestone 4: Distribution & Packaging (Day 7)**
  * Verify direct-distribution behavior, bundle repair, storage cleanup, and code signing/hardened-runtime settings; prepare release notes and a notarized build if distributing binaries.
