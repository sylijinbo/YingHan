# YingHan Local Build Notes

Last updated: 2026-05-17

## Current Status

This local fork is renamed from the upstream `hallelujahIM` project to `YingHan`.

Visible project names are now:

- Project folder: `YingHan`
- Xcode project: `YingHan.xcodeproj`
- Xcode workspace: `YingHan.xcworkspace`
- Asset folder: `YingHan/Images.xcassets`
- Prefix header: `YingHan_Prefix.pch`

Runtime identity is:

- App name: `YingHan`
- App bundle: `YingHan.app`
- Executable: `YingHan`
- Bundle ID / input source ID: `com.jinboli.inputmethod.yinghan`
- InputMethodKit connection: `YingHan_1_Connection`
- User support directory: `~/Library/Application Support/YingHan`
- User install path: `~/Library/Input Methods/YingHan.app`

The icon files intentionally use the original upstream icon assets:

- `him.icns`
- `him.png`

## Local Build

This project can be built with Command Line Tools only. Full Xcode is not required for the local build path.

Build the app:

```bash
./script/build_local_clt.sh
```

Build and launch the staged app:

```bash
./script/build_local_clt.sh --run
```

The staged app is written to:

```text
dist/YingHan.app
```

## Packaging

The latest local packaging outputs are:

```text
dist/YingHan.zip
dist/YingHan-user.pkg
```

`YingHan.zip` is a portable archive of `YingHan.app`.

`YingHan-user.pkg` installs the app into the current user's input method folder:

```text
~/Library/Input Methods/YingHan.app
```

The package is unsigned. The app bundle itself is ad-hoc signed for local testing.

## Install

Install for the current user:

```bash
./script/install_local_user.sh
```

The install script does this:

- builds `dist/YingHan.app` if needed
- stops an existing `YingHan` process
- copies the app to `~/Library/Input Methods/YingHan.app`
- registers the input source
- enables the input source
- restarts `TextInputMenuAgent` and `SystemUIServer`

Expected successful install output includes:

```text
TISRegisterInputSource status: 0
Found source: com.jinboli.inputmethod.yinghan
TISEnableInputSource status: 0
Installed /Users/jinboli/Library/Input Methods/YingHan.app
```

`TISSelectInputSource status: -50` can still appear on this machine. In the latest test, registration, enablement, installed bundle validation, process launch, and the preference server all succeeded despite that select status.

## Verification

Useful checks:

```bash
codesign --verify --deep --strict --verbose=2 dist/YingHan.app
codesign --verify --deep --strict --verbose=2 "$HOME/Library/Input Methods/YingHan.app"
ps ax | rg 'YingHan|TextInputMenuAgent|SystemUIServer'
curl -sS http://127.0.0.1:62718/preference
```

The preference page is:

```text
http://127.0.0.1:62718/index.html
```

The latest verified preference response included:

```json
{
  "enableRightShiftModeSwitch": true,
  "enableNextWordPrediction": false,
  "enableLeftCommandPinyinSwitch": false,
  "commitWordWithSpace": true,
  "enableRightCommandPinyinSwitch": true,
  "enableLeftShiftModeSwitch": false,
  "showTranslation": true
}
```

## Finder Copy

The working project is:

```text
/Users/jinboli/Documents/Codex/2026-05-16/build-macos-apps-swiftpm-macos-users/YingHan
```

The Finder-facing copy is:

```text
/Users/jinboli/Documents/YingHan
```

Sync the latest working project to the Finder-facing copy:

```bash
./script/export_to_documents.sh
```

That script backs up an existing `/Users/jinboli/Documents/YingHan` before replacing it.

## Notes

CocoaPods generated support files may still contain upstream names such as `Pods-hallelujah`. Those are generated dependency integration names and are currently left in place to avoid breaking the existing CocoaPods project wiring.
