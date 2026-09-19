---
name: release-macos-app
description: >-
  Automates cutting a new release for the macOS Office Attendance app: generates
  HTML release notes from git commits, bumps the version in project.yml, runs
  macOS-app/build.sh with the Sparkle notes, and updates appcast.xml.
metadata:
  disable-model-invocation: false
---

# Release macOS App

Use this skill when the user asks to create, cut, or build a new release for the macOS app (e.g. "release v1.3.3", "cut a release", "build and publish a new version").

## Release Workflow

### 1. Determine Target Version
- If the user specified a version (e.g. `1.3.3`), use it.
- If not specified, inspect `macOS-app/project.yml` for `MARKETING_VERSION` and suggest the next patch or minor version.

### 2. Inspect Recent Git History
Run `git log` to find changes since the last release:
```bash
git log -n 15 --oneline
```
Identify features, bug fixes, UI updates, and stability improvements since the previous release commit.

### 3. Generate HTML Release Notes for Sparkle
Draft concise, user-friendly HTML formatted specifically for Sparkle's `<description>` tag.

Format template:
```html
<h2>What's New in <VERSION></h2>
<ul>
  <li><b><Category>:</b> <Short description of user-facing change></li>
</ul>
```

Categories to use where applicable:
- `<b>Feature:</b>` / `<b>Settings:</b>`
- `<b>Fix:</b>` / `<b>Stability:</b>`
- `<b>History:</b>` / `<b>Sync:</b>`

### 4. Confirm with User
Present the target version and the draft HTML release notes to the user before running the build:
> "Targeting release **v<VERSION>** with the following release notes:
> ...
> Shall I proceed with building and packaging the release?"

### 5. Execute Build Script
Once confirmed, run the build script from `macOS-app/`:
```bash
cd macOS-app && ./build.sh --release=<VERSION> --notes="<ESCAPED_HTML_NOTES>"
```

### 6. Verify & Push Instructions
1. Check `macOS-app/appcast.xml` to ensure the new `<item>` entry contains the correct `<description><![CDATA[ ... ]]></description>` block, version numbers, and EdDSA signature.
2. Remind or assist the user to:
   - Push commit & tag: `git push origin main`
   - Create GitHub release tagged `v<VERSION>`
   - Upload `macOS-app/OfficeAttendance-<VERSION>.dmg` as a release asset.
