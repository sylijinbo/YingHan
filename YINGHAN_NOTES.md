# YingHan Local Build Notes

Last updated: 2026-05-17

## Current Status

This project is now maintained as `YingHan` under the user's own GitHub repository.

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

## GitHub Repository

The active GitHub repository is:

```text
https://github.com/sylijinbo/YingHan.git
```

Local git state:

- Active branch: `main`
- Upstream: `origin/main`
- Remote fetch/push URL: `https://github.com/sylijinbo/YingHan.git`
- Old local `master` branch removed
- Old local release tags removed
- Old Xcode source-control checkout metadata removed

Current public history intentionally starts with a clean YingHan import:

```text
d0b6ad9 Initial YingHan import
82e4b7b Add bundled dictionaries
8c7cd63 Bind project metadata to YingHan repository
```

The GitHub Actions workflow file is not uploaded because the available GitHub token does not have the `workflow` scope. `.github/workflows/` is ignored locally until a token with that scope is available.

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

The current local packaging target for iterative testing is the app bundle only:

```text
dist/YingHan.app
```

During the current local test cycle, zip and pkg outputs are intentionally not required. The app bundle is installed directly into:

```text
~/Library/Input Methods/YingHan.app
```

The app bundle itself is ad-hoc signed for local testing.

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
  "enableRightShiftModeSwitch": false,
  "enableNextWordPrediction": false,
  "enableLeftCommandPinyinSwitch": false,
  "commitWordWithSpace": true,
  "enableRightCommandPinyinSwitch": true,
  "enableLeftShiftModeSwitch": true,
  "showTranslation": true,
  "candidatePanelLayout": "horizontal"
}
```

## Candidate Panel Layout

The preference key `candidatePanelLayout` controls the candidate panel layout:

- `vertical`: default legacy layout, backed by `kIMKSingleColumnScrollingCandidatePanel`
- `horizontal`: Sogou-like single-row layout, backed by `kIMKSingleRowSteppingCandidatePanel`

The preference web UI exposes this as a vertical/horizontal choice. The default remains `vertical` so existing installs do not unexpectedly change layout after upgrade.

Horizontal mode notes:

- The marked text above the candidate panel should continue to show the raw input letters, such as `d`, `de`, or `xiang`, while candidate highlight movement updates the internal selected candidate for commit.
- Number keys `1` through `9` should select the candidate shown at the matching visible screen position.
- Left/right arrows are intended to move the visible highlight by one candidate.
- Up/down arrows are intended to use InputMethodKit page stepping.
- The horizontal panel can show fewer than 9 candidates on a page because InputMethodKit decides how many fit in the current panel width. Avoid assuming a fixed 9-candidate page when maintaining selection state.

Current horizontal candidate debugging status:

- The installed app has been verified as `candidatePanelLayout: "horizontal"`.
- Left/right highlight movement has been partially corrected in recent iterations, but number-key selection is still reported as unresponsive in horizontal mode.
- Do not keep blind-patching number selection. The next useful debugging step is to add temporary logging around `handleEvent:client:`, the candidate-key entry point, and candidate commit paths to confirm whether digit key events reach `InputController.mm`.
- Log at least `event.keyCode`, `characters`, `charactersIgnoringModifiers`, candidate panel visibility, current layout, selected visible index, and selected candidate string.
- If digit key events do not reach the server, investigate `IMKCandidatesSendServerKeyEventFirst`, candidate-panel attributes after every `setPanelType:`, and whether IMK is consuming selection keys before YingHan.
- If digit key events do reach the server, fix `selectionKeyIndexForEvent:` or the commit path based on the logged values.

Latest local install verification:

```text
dist/YingHan.app/Contents/MacOS/YingHan
~/Library/Input Methods/YingHan.app/Contents/MacOS/YingHan
```

These were verified with matching SHA-256 hashes after the latest reinstall. The installed app was launched manually with:

```bash
/usr/bin/open -n "$HOME/Library/Input Methods/YingHan.app"
```

## Notes

## CC-CEDICT Update Strategy

`dictionary/cedict.json` is the source for pinyin-to-Chinese-and-English-definition candidates, such as:

```text
gaoji -> 高级 / high level / high grade / advanced / high-ranking
```

When updating CC-CEDICT:

- Update only `dictionary/cedict_1_0_ts_utf-8_mdbg.txt` and the generated `dictionary/cedict.json` unless explicitly requested otherwise.
- Do not mix this update with `pinyin_data.sqlite3`, Rime dictionaries, Google Pinyin data, English word databases, n-gram data, or candidate panel behavior.
- Download the latest CC-CEDICT from the MDBG export, generate the new `cedict.json` in a temporary directory, compare counts, and back up the current data before replacing files.
- The update note must include old/new CC-CEDICT date, old/new `entries`, raw added/removed/changed counts, `cedict.json` key/item count changes, SHA-256 hashes, backup path, and examples of newly added content.
- Include added-content examples in this format:

```text
yaoyaoling -> 110 / the emergency number for law enforcement in Mainland China and Taiwan
sanddayin -> 3D打印 / to 3D print; 3D printing
bzhan -> B站 / (coll.) Bilibili, Chinese video-sharing website featuring scrolled user comments 弹幕 overlaid on the videos
```

Fast repeatable update procedure:

1. Download to a temporary directory:

   ```bash
   rm -rf /private/tmp/yinghan-cedict-update
   mkdir -p /private/tmp/yinghan-cedict-update
   curl -L -o /private/tmp/yinghan-cedict-update/cedict_1_0_ts_utf-8_mdbg.txt.gz \
     https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz
   gzip -cd /private/tmp/yinghan-cedict-update/cedict_1_0_ts_utf-8_mdbg.txt.gz \
     > /private/tmp/yinghan-cedict-update/cedict_1_0_ts_utf-8_mdbg.txt
   ```

2. Generate the candidate JSON without touching project data:

   ```bash
   cp dictionary/cedict2json.js /private/tmp/yinghan-cedict-update/
   cp dictionary/google_pinyin_rawdict_utf16_65105_freq.txt /private/tmp/yinghan-cedict-update/
   cd /private/tmp/yinghan-cedict-update
   node cedict2json.js
   ```

3. Compare before replacing:

   - Parse old/new CEDICT by key `traditional|simplified|pinyin`.
   - Count old/new `entries`, added, removed, changed.
   - Count old/new `cedict.json` pinyin keys and total candidate/definition items.
   - Print samples of added, removed, changed entries.
   - Smoke check `gaoji -> 高级 / high level / high grade / advanced / high-ranking`.

4. Back up current project data:

   ```bash
   stamp=$(date +%Y%m%d-%H%M%S)
   backup="dictionary/backups/cedict-$stamp"
   mkdir -p "$backup"
   cp dictionary/cedict_1_0_ts_utf-8_mdbg.txt "$backup/"
   cp dictionary/cedict.json "$backup/"
   shasum -a 256 "$backup/cedict_1_0_ts_utf-8_mdbg.txt" "$backup/cedict.json" > "$backup/SHA256SUMS.txt"
   ```

5. Replace only after user confirmation:

   ```bash
   cp /private/tmp/yinghan-cedict-update/cedict_1_0_ts_utf-8_mdbg.txt dictionary/cedict_1_0_ts_utf-8_mdbg.txt
   cp /private/tmp/yinghan-cedict-update/cedict.json dictionary/cedict.json
   ```

6. Rebuild and install:

   ```bash
   ./script/build_local_clt.sh
   ./script/install_local_user.sh
   ```

7. Verify installed resource:

   ```bash
   shasum -a 256 dictionary/cedict.json \
     dist/YingHan.app/Contents/Resources/cedict.json \
     "$HOME/Library/Input Methods/YingHan.app/Contents/Resources/cedict.json"
   ```

8. Roll back if needed:

   ```bash
   cp dictionary/backups/cedict-YYYYMMDD-HHMMSS/cedict_1_0_ts_utf-8_mdbg.txt dictionary/
   cp dictionary/backups/cedict-YYYYMMDD-HHMMSS/cedict.json dictionary/
   ./script/build_local_clt.sh
   ./script/install_local_user.sh
   ```

Latest CC-CEDICT update:

- Updated on: 2026-05-17
- Source: MDBG CC-CEDICT export, `https://www.mdbg.net/chinese/export/cedict/cedict_1_0_ts_utf-8_mdbg.txt.gz`
- Old version: `2017-11-17T23:06:02Z`, `entries=115687`, CC BY-SA 3.0 header
- New version: `2026-05-17T09:29:34Z`, `entries=124927`, CC BY-SA 4.0 header
- Raw diff from the update report: `+17474` added, `-8234` removed, `18719` changed
- Generated `cedict.json`: `110249 -> 116406` pinyin keys, `580471 -> 602017` candidate/definition items
- Current SHA-256:
  - `dictionary/cedict_1_0_ts_utf-8_mdbg.txt`: `8025825b8b5a8c9e8d450c4c4d6ade939d6c41ce877204f639f9660ef03178a3`
  - `dictionary/cedict.json`: `23d6126a010a3871129b788ef41b80ce4fbd1fd5b87e93ae25f9213222627b73`
- Rollback backup: `dictionary/backups/cedict-20260517-222615`
- Smoke check:

```text
gaoji -> 高级 / high level / high grade / advanced / high-ranking
ceshi -> 测试
```

Examples of newly added content from the 2026 update:

```text
yaoyaoling -> 110 / the emergency number for law enforcement in Mainland China and Taiwan
sanddayin -> 3D打印 / to 3D print; 3D printing
bzhan -> B站 / (coll.) Bilibili, Chinese video-sharing website featuring scrolled user comments 弹幕 overlaid on the videos
jiujiuliu -> 996 / 9am-9pm, six days a week (work schedule)
cpzhi -> CP值 / value for money; bang for your buck
```

CocoaPods generated support files may still contain upstream names such as `Pods-hallelujah`. Those are generated dependency integration names and are currently left in place to avoid breaking the existing CocoaPods project wiring.

The repository-level validation rule is still:

```bash
sh format-code.sh
sh unit-tests.sh
bash build.sh
```

On the current machine these commands are blocked by local tooling:

- `format-code.sh` needs `clang-format`; `brew` is not installed.
- `unit-tests.sh` and `build.sh` need full Xcode; the active developer directory is `/Library/Developer/CommandLineTools`.

Use `./script/build_local_clt.sh` for local app bundle builds until full Xcode and formatting tools are available.
