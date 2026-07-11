## 0.1.1

- `torchinlane init` no longer prompts for the App Store Connect `.p8` key path or the Google Play service account JSON path. Both are now fixed defaults (`ios/fastlane/api_key.p8`, `android/fastlane/fastlane-service-account.json`) printed at the end of the command.
- Add `torchinlane uninstall` — removes everything `init` created (fastlane dirs, `ExportOptions.plist`, `torchinlane.yaml`), leaving `changelogs/` untouched.
- Fix a path-resolution bug where `service_account_json` was interpreted against different base directories in `doctor` vs. the generated Android Appfile, causing `upload_to_play_store` to fail with a duplicated path.

## 0.1.0

- Initial release.
- `torchinlane init` — scaffold fastlane (iOS + Android) and `torchinlane.yaml` for a Flutter project.
- `torchinlane deploy` — clean, build, and upload to TestFlight/App Store or Play Internal/Production.
- `torchinlane bump` — bump pubspec.yaml version (build/patch/minor/major).
- `torchinlane doctor` — verify environment and project configuration.
- `torchinlane changelog translate|push|clear` — translate changelogs into 32 store locales via Claude API and push them to the stores.
- `torchinlane screenshots capture|prompts` — interactively capture raw screenshots and generate store-ready marketing image prompts via Claude API.
