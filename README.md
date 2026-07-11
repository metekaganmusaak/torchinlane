# torchinlane

A global Dart CLI for Flutter app distribution: scaffold fastlane, build and
upload to TestFlight/App Store and Google Play, translate store changelogs
into 32 locales via the Claude API, and generate store-ready screenshot
marketing prompts.

## Install

```bash
dart pub global activate torchinlane
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
to commit — it holds paths and IDs, not secrets. Your App Store Connect `.p8`
key and Google Play service account JSON are added to `.gitignore`
automatically.

## License

MIT
