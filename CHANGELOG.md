# Changelog

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
