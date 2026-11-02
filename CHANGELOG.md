# Changelog

All notable changes to DockDivider are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Line, dashed, dot, label, spacer, and custom-image divider styles with a live
  Dock preview, Dock-aware orientation, and color, opacity, thickness, height,
  and offset controls.
- Drag-to-Dock staging that publishes a fresh, signed bundle for every drag.
- Optional click actions: apps and URLs, Apple Shortcuts, shell commands and
  scripts, and built-in system actions.
- Draft persistence, a one-time welcome sheet, a custom storage folder with a
  security-scoped bookmark, disk-usage display, and confirmation-based cleanup.
- Ad-hoc signing, LaunchServices registration, Finder custom icons, and repair
  for older generated dividers.
- Universal Release build (`arm64` + `x86_64`) with hardened runtime.
- GitHub Actions CI for unit tests and an unsigned Release build.

### Security

- DockDivider never edits `com.apple.dock.plist` and never terminates the Dock.
- Generated divider bundles are ad-hoc signed locally; release builds of
  DockDivider itself are signed and notarized.
