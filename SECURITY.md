# Security Policy

## Reporting a vulnerability

Please report security issues privately through GitHub's **Report a
vulnerability** button on the repository's **Security** tab. Do not open a
public issue for a security problem.

## Scope

DockDivider is a local, unsandboxed macOS utility. It creates and ad-hoc signs
app bundles, and a generated tile can run shell commands, Apple Shortcuts, or
AppleScript **only when the user configures those actions**. Reports about
actions the user explicitly configured are not vulnerabilities.

Generated divider bundles are ad-hoc signed and are not a sandbox or an
integrity boundary. Treat them as local files that back Dock tiles.

No signing certificates, notarization profiles, or other credentials are part
of this repository.
