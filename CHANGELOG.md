# Changelog

## 0.1.9

- Add `torchinlane update`. After upgrading the CLI (`dart pub global activate torchinlane`), run `torchinlane update` in your project to re-apply the current templates. It reads `torchinlane.yaml`, re-renders the generated files (iOS/Android Fastfiles + Appfiles, `fastlane/ChangelogHelper.rb`, `scripts/build.sh`), shows a line diff for each changed file, and asks per file before writing — `-y` applies all, `--dry-run` only reports. Every overwritten file is backed up as `<file>.bak` (now gitignored). User-owned files (`ExportOptions.plist`, release notes, `torchinlane.yaml`) are never touched. For a full clean regeneration instead, use `torchinlane init --force`.

## 0.1.8

- Add an interactive build & deploy script. `torchinlane init` now writes `scripts/build.sh` to the project root (executable). Run `sh scripts/build.sh` instead of remembering CLI flags: it prompts for platforms (Android/iOS), only-upload mode, target (Internal/Production), a version bump, deep clean, and English release notes. The version prompt shows the exact resulting version for each choice (patch/minor/major/build/skip) before you pick, then runs `torchinlane bump`. Builds are always obfuscated with split debug info; iOS builds verify dSYMs for Crashlytics. Release notes are cleared before each run so a stale note is never shipped, translated to all configured locales when `ANTHROPIC_API_KEY` is set (empty notes are allowed), then cleared again after a successful upload. `torchinlane uninstall` removes the script.
- Fix `deliver` crashing with `Malformed version number string` during `torchinlane deploy --platform ios`. The generated iOS `release` lane now passes `skip_app_version_update: true`, so deliver no longer parses live App Store Connect version strings (a badly-named existing version like `1.0.3 + 13` no longer aborts the upload).

## 0.1.7

- Fix ios pre-check problem

## 0.1.6

- Tiny fix in Apple versioning.

## 0.1.5

- Updated Readme. Nothing else. Now you can use this version to upload your releases either production or internal tests. But in Google Play Store, you manually send your release to the store review.

## 0.1.4

- Bug fixes and try to make it as stable as rock!
- Also created new package logo to get some points!

## 0.1.3

- Fix `upload_to_play_store` crashing with `Could not find option 'release_notes'` during `torchinlane deploy --platform android`. The Play Store upload (Supply) action doesn't accept changelog text directly — it only reads changelogs from a `metadata_path` directory tree. `deploy_internal`, `deploy_production`, and `update_release_notes` now write release notes to a temp metadata directory (`<locale>/changelogs/default.txt`) and pass `metadata_path` instead.
- Fix a follow-up `Invalid request` error from the same flow: Supply derives its language list from the top-level folder names under `metadata_path`, so the temp directory can't have an extra nesting level — release notes are now written directly to `<tmp>/<play_locale>/changelogs/default.txt` instead of `<tmp>/android/<play_locale>/...`.
- Fix `torchinlane deploy --platform ios,android` skipping the iOS build entirely whenever the Android step failed. Android and iOS now build/upload independently — a failure in one no longer blocks the other — and the command reports which platform(s) failed at the end.
- Document the changelog workflow in the README: how to find your source locale, write `changelogs/<locale>/release_notes.txt`, translate it to the other 31 locales, and clear it after a release.

## 0.1.2

- `torchinlane init` no longer prompts for the App Store Connect `.p8` key path or the Google Play service account JSON path. Both are now fixed defaults (`ios/fastlane/api_key.p8`, `android/fastlane/fastlane-service-account.json`) printed at the end of the command.
- Add `torchinlane uninstall` — removes everything `init` created (fastlane dirs, `ExportOptions.plist`, `torchinlane.yaml`), leaving `changelogs/` untouched.
- Fix a path-resolution bug where `service_account_json` was interpreted against different base directories in `doctor` vs. the generated Android Appfile, causing `upload_to_play_store` to fail with a duplicated path.

## 0.1.1

- Improvements made, nothing much.

## 0.1.0

- Initial release.
- `torchinlane init` — scaffold fastlane (iOS + Android) and `torchinlane.yaml` for a Flutter project.
- `torchinlane deploy` — clean, build, and upload to TestFlight/App Store or Play Internal/Production.
- `torchinlane bump` — bump pubspec.yaml version (build/patch/minor/major).
- `torchinlane doctor` — verify environment and project configuration.
- `torchinlane changelog translate|push|clear` — translate changelogs into 32 store locales via Claude API and push them to the stores.
- `torchinlane screenshots capture|prompts` — interactively capture raw screenshots and generate store-ready marketing image prompts via Claude API.
