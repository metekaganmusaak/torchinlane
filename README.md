# torchinlane

A global Dart CLI for Flutter app distribution: scaffold fastlane, build and
upload to TestFlight/App Store and Google Play, translate store changelogs
into 32 locales via the Claude API, and generate store-ready screenshot
marketing prompts.

## Requirements

- Dart SDK `^3.5.0`
- Flutter project layout (`pubspec.yaml`, `ios/`, `android/`)
- Ruby + [fastlane](https://fastlane.tools) installed for `deploy` (`gem install fastlane` or via Bundler)
- `ANTHROPIC_API_KEY` env var for `changelog translate`
- App Store Connect API key (`.p8`) for iOS deploy/changelog push
- Google Play service account JSON for Android deploy/changelog push

## Install

```bash
dart pub global activate torchinlane
```

Make sure `~/.pub-cache/bin` is on your `PATH` so the `torchinlane` executable
is found:

```bash
export PATH="$PATH:$HOME/.pub-cache/bin"
```

## Usage

Run inside any Flutter project (needs `pubspec.yaml`, `ios/`, `android/`).

### `torchinlane init`

Interactively scaffolds `ios/fastlane/`, `android/fastlane/`,
`fastlane/ChangelogHelper.rb`, `changelogs/<locale>/release_notes.txt`, and a
`torchinlane.yaml` config file for your project's bundle IDs, team IDs, and
API keys.

```bash
torchinlane init
```

After it finishes, place your credentials at the fixed default paths it
prints:

- App Store Connect `.p8` key → `ios/fastlane/api_key.p8`
- Google Play service account JSON → `android/fastlane/fastlane-service-account.json`

Both paths are added to `.gitignore` automatically.

### `torchinlane uninstall`

Removes everything `torchinlane init` created — `ios/fastlane/`,
`android/fastlane/`, `fastlane/`, `ios/ExportOptions.plist`, and
`torchinlane.yaml`. Leaves `changelogs/` untouched.

```bash
torchinlane uninstall          # asks for confirmation
torchinlane uninstall --yes    # skip confirmation
```

### `torchinlane deploy`

Runs `flutter clean && flutter pub get`, builds (obfuscated), and uploads via
fastlane.

```bash
torchinlane deploy --platform ios,android --target internal
torchinlane deploy --platform ios --target production
torchinlane deploy --platform android --target internal --upload-only
torchinlane deploy --dry-run
```

### `torchinlane bump`

```bash
torchinlane bump build   # 1.0.16+57 -> 1.0.16+58
torchinlane bump patch   # 1.0.16+57 -> 1.0.17+58
torchinlane bump minor   # 1.0.16+57 -> 1.1.0+58
torchinlane bump major   # 1.0.16+57 -> 2.0.0+58
```

### `torchinlane changelog`

Requires `ANTHROPIC_API_KEY` in the environment.

```bash
torchinlane changelog translate --from en   # writes changelogs/<locale>/release_notes.txt for 31 other locales
torchinlane changelog push --platform ios,android  # push notes to stores without a binary upload
torchinlane changelog clear  # empty all release_notes.txt after a release
```

### `torchinlane screenshots`

```bash
torchinlane screenshots capture --platform ios --locale en   # interactive: navigate, press Enter, repeat
torchinlane screenshots prompts   # analyzes the project and writes screenshots/store_prompts.md
```

### `torchinlane doctor`

```bash
torchinlane doctor
```

## Configuration

`torchinlane init` writes `torchinlane.yaml` to your project root. It is safe
to commit — it holds paths and IDs, not secrets. Credential paths
(`asc_key_path`, `service_account_json`) are fixed defaults, not prompted
for, and are added to `.gitignore` automatically.

```yaml
app_name: MyApp
ios:
  bundle_id: com.example.myapp
  team_id: ABCDE12345
  itc_team_id: ABCDE12345 # optional, defaults to team_id
  apple_id: you@example.com
  asc_key_id: XXXXXXXXXX
  asc_issuer_id: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
  asc_key_path: ios/fastlane/api_key.p8 # fixed default, not prompted
  firebase_crashlytics: false # optional, uploads dSYMs when true
android:
  package_name: com.example.myapp
  service_account_json: android/fastlane/fastlane-service-account.json # fixed default, not prompted
changelogs:
  dir: changelogs # optional
  source_locale: en # optional
  locales: [ar, bn, cs, ...] # optional, defaults to 32 store locales
build:
  obfuscate: true
  split_debug_info: build/debug-info
screenshots:
  output_dir: screenshots
  ios_devices: []
  android_devices: []
  locales: [en]
```

## Troubleshooting

- **`torchinlane: command not found`** — `~/.pub-cache/bin` is not on `PATH`
  (see Install above).
- **`torchinlane doctor` fails on fastlane** — install fastlane and confirm
  `fastlane --version` runs from your project's `ios/` or `android/` dir.
- **`changelog translate` errors with a missing key** — export
  `ANTHROPIC_API_KEY` in your shell before running the command.
- **Deploy fails to authenticate with App Store Connect** — verify
  `asc_key_path` points at a valid `.p8` file and `asc_key_id`/`asc_issuer_id`
  match the key generated in App Store Connect > Users and Access > Keys.
- **Deploy fails to authenticate with Google Play** — verify the service
  account JSON path is correct and the service account has been granted
  access to the app in Play Console.

## License

MIT
