# DockDivider

A modern, native macOS utility to create custom visual dividers, spacers, labels, and quick-action tiles for your macOS Dock.

![macOS 14+](https://img.shields.io/badge/macOS-14.0%2B-blue)
![Swift 6](https://img.shields.io/badge/Swift-6.0-orange)
![Xcode 16](https://img.shields.io/badge/Xcode-16%2B-blue)

---

## ✨ Features

- **Multiple Divider Styles**:
  - **Line**: Clean vertical/horizontal separator with customizable thickness, height, opacity, and color.
  - **Dashed**: Segmented dashed divider with configurable dash pattern and count.
  - **Dot**: Subtle circular separator dot.
  - **Label**: Vertical or horizontal text labels and SF Symbols.
  - **Spacer**: Native macOS blank spacers (`Full`, `Half`, and `Flexible`) utilizing native Dock tile spacers with zero tooltip bubbles.
  - **Image**: Custom user image or icon with configurable corner radii.
- **Dock Sampling Eyedropper**: One-click magnifying eyedropper to sample the exact color, opacity, and dimensions of macOS's native Dock divider.
- **Live Dock Preview**: Accurate desktop canvas preview with customizable wallpaper and light/dark glass appearance.
- **Dock Orientation Aware**: Supports both Bottom Dock and Left/Right Side Dock, with automatic background maintenance that adapts divider orientation if you move your Dock.
- **Interactive Click Actions**:
  - Launch one or more applications and open web URLs.
  - Execute Apple Shortcuts directly.
  - Run shell commands (either interactively in your default terminal—e.g. Ghostty or Terminal—or silently in the background).
  - 15 Built-in System Utility actions (Hide Other Apps, Toggle Dark Mode, Mute Audio, Open Trash, Empty Trash, Digital Color Meter, Activity Monitor, Sleep Displays, etc.).
- **Drag & Drop**: Seamlessly drag divider bundles directly from the app window straight into the macOS Dock.
- **Zero-Width App Bundles**: Synthesized `.app` bundles use invisible zero-width unicode identifiers to eliminate distracting text beneath dividers in your Dock.

---

## 🛠️ Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15.0+ / Xcode 16.0+
- Swift 5.9+ / Swift 6

---

## 🚀 Building & Running

1. Clone the repository:
   ```bash
   git clone https://github.com/jackbbb95/DockDivider.git
   cd DockDivider
   ```
2. Open `DockDivider.xcodeproj` in Xcode:
   ```bash
   open DockDivider.xcodeproj
   ```
3. Select the `DockDivider` scheme and choose **My Mac** as the destination.
4. Press `Cmd + R` to build and run, or `Cmd + U` to execute the comprehensive test suite.

---

## 🧱 Architecture

The project consists of two primary targets:
- **`DockDivider.app`**: The main SwiftUI application containing the live preview canvas, customization controls, and bundle synthesizer.
- **`divider_runner`**: A standalone, zero-dependency Mach-O binary compiled into each generated divider bundle (`Contents/MacOS/divider_runner`) to instantly execute click actions with minimal overhead (< 15 ms).

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
