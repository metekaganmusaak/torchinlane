## 0.1.1

- Fix default `service_account_json` path (was `android/fastlane/...`, now `fastlane/...` — relative to the `android/` dir where fastlane runs, fixing a duplicated-path lookup failure in `upload_to_play_store`).

## 0.1.0

- Initial release.
- `torchinlane init` — scaffold fastlane (iOS + Android) and `torchinlane.yaml` for a Flutter project.
- `torchinlane deploy` — clean, build, and upload to TestFlight/App Store or Play Internal/Production.
- `torchinlane bump` — bump pubspec.yaml version (build/patch/minor/major).
- `torchinlane doctor` — verify environment and project configuration.
- `torchinlane changelog translate|push|clear` — translate changelogs into 32 store locales via Claude API and push them to the stores.
- `torchinlane screenshots capture|prompts` — interactively capture raw screenshots and generate store-ready marketing image prompts via Claude API.
