# Changelog

## 0.2.6

- Fix "Breakpad symbol generation failed" during iOS builds. `scripts/build.sh`
  no longer sends Dart symbols to `crashlytics:symbols:upload` for iOS (iOS is
  symbolicated from dSYMs; symbols are still archived). Android uploads only
  `app.android-*.symbols`. Run `torchinlane update` in each app.

## 0.2.5

- Fix lost Crashlytics symbols. `scripts/build.sh` archived split-debug-info
  symbols under `build/debug-info-archive/`, which the next build's
  `flutter clean` deleted. They are now kept in `debug-info-archive/<version>/`
  at the project root (git-ignored). Run `torchinlane update` in each app.

## 0.2.4

- Fix App Store Connect "Upload Symbols Failed" warnings. Prebuilt frameworks
  such as `objective_c.framework` (Flutter native assets) ship without a dSYM.
  After `flutter build ipa`, missing dSYMs are now generated with `dsymutil`
  and the IPA is re-exported so they are bundled. Applies to
  `torchinlane deploy` and the generated `scripts/build.sh`.
- Existing apps must run `torchinlane update -y` to regenerate `scripts/build.sh`.

## 0.2.3

- Fix store access checks and other Fastlane commands failing with
  `require_relative: cannot infer basepath`. Fastlane evaluates Appfiles without
  a source filename; both generated Appfiles now load StoreHelper from the
  Appfile working directory using an absolute path.
- Add regression coverage for filename-less Appfile evaluation and verify both
  platforms with the real Fastlane 2.230.0 Appfile reader.
- Existing apps must run `torchinlane update -y` after upgrading the CLI, then
  restart Studio. Credentials and store text do not need to be re-entered.

## 0.2.2

- Add a Turkish/English interface language selector to Studio. Navigation,
  setup help, field labels, readiness messages, counters and locale/asset names
  update immediately without reloading the workspace.
- Remember the language across page reloads and Studio restarts. Prefer the
  current browser's saved choice, then the saved user preference, then browser
  language (Turkish for `tr`, English otherwise).
- Preserve unsaved project settings, store text, selected locales, imported
  files and generated agent tasks when switching interface language. Store
  metadata, coding-agent task text and native process diagnostics are unchanged.
- Allow saving the UI preference while a job runs; workspace edits remain locked.
- Add localization coverage and preference persistence tests, and verify both
  interfaces and live switching in Chrome on desktop/mobile.


## 0.2.1

- Replace Studio's crowded screens with a Turkish step-by-step workflow:
  readiness overview, setup, source texts, translation, images and upload.
- Detect existing configuration, generated file versions, credential formats,
  source texts, missing translations and local images. Explain which steps can
  be skipped and show only the selected store's setup. Remember store selection.
- Separate local credential presence from live app-access verification. Cache
  successful verification for the current server session and invalidate it when
  the app identity or credential contents change.
- Simplify API-free translation to add languages, copy an agent task, then reload
  and validate its results. Show language names and missing-field counts; skip
  completed translation tasks. Move API/overwrite/bulk options under details.
- Reuse common source text between stores without overwriting populated fields;
  reject incompatible limits before writing. Default standalone uploads to
  metadata and request Google version/track only when notes are included.
- Add explicit, non-installing tool checks and distinguish store-content upload
  from building/signing an app. Keep advanced operations available in details.
- Preserve the Studio session on browser reload. Avoid rewriting unchanged
  generated/configuration files. Mark the AI key optional in doctor and add
  `torchinlane --version` / `-v`.
- Update screenshots, usage documentation and the Turkish quick-start guide.
  Validate readiness/source reuse with automated tests and the wizard in Chrome
  on desktop/mobile; no live store upload is performed by these checks.

## 0.2.0

### Upgrade notes

- After upgrading the CLI, run `torchinlane update -y` in each initialized Flutter
  project to regenerate Fastlane helpers and the shared store locale registry.
  Changed generated files are backed up; configuration and store content remain.
- `store translate` generates a Claude Code/Codex task by default. Add `--api`
  for optional direct Anthropic translation. Legacy `changelog translate` retains
  its API behavior. See [migration instructions](doc/migration.md).

### Added

- Local Torchinlane Studio GUI: project setup, credential import, locale editing,
  field counters, screenshot import/order, validation, exports, uploads, remote
  text comparison/import, and build/deploy logs.
- `store init/locales/validate/export/translate/prompt/push/pull` for localized
  App Store and Google Play metadata, images and release notes. Native locale
  catalogs and field limits are separate for each store; blank upload fields
  preserve existing remote content.
- API-free coding-agent translation tasks with exact target paths, source/target
  snapshots, pending fields, locale-specific limits and validation instructions.
  Studio supports preparing/copying tasks and reloading/validating agent edits.
- Credential import/reusable profiles, live app-access verification, Google Cloud
  service-account/WIF bootstrap, and environment-based credential overrides.
- iOS Fastlane match signing sync and Android release signing integration for
  standard Flutter Groovy/Kotlin projects using an existing upload keystore.
- GitHub Actions workflow generation with independent iOS/Android jobs, signing
  restoration and optional keyless Google authentication.
- `deploy --with-store`, explicit Google release status/rollout options,
  noninteractive initialization, scoped store uploads and dry-run plans.

### Fixed

- App Store production release notes were skipped by metadata settings. Notes
  now upload through isolated metadata staging; Apple's first release omits
  unavailable What's New. TestFlight sends localized What to Test and waits for
  build processing when notes are supplied.
- Apple Bangla and Google Hebrew locale codes, unsupported Apple Filipino,
  regional locale preservation and shared Dart/Ruby locale mapping.
- Google note-only updates now target a selected track/version and merge locales
  while preserving release status, version codes and other releases.
- Over-limit notes are rejected instead of silently truncated; Apple keywords
  are validated against the 100 UTF-8 byte limit.
- Configured credential/changelog paths, quoted YAML strings, shell escaping,
  Android binary screenshot capture, HTTP timeouts/client cleanup and temporary
  staging cleanup.
- Release notes are retained after upload for retries. Platform failures are
  reported independently so successful platform work can complete.

### Documentation and validation

- Rewrite README/examples and add store content, migration, automation and
  Turkish implementation guides, including credential/signing setup and the
  manual account steps that remain.
- Expand to 50 automated tests covering content validation, translation tasks,
  credentials, Studio APIs, signing/CI generation and generated Fastlane lanes.
  Verify Studio in Chrome on desktop/mobile. Live store uploads and real signing
  are not exercised without app-specific credentials.

## 0.1.12

- Fix `CocoaPods not installed or not in valid state` aborting an iOS deploy. The old check was a bare `which pod`, which succeeds whenever the binary merely exists — so a CocoaPods install broken by a system Ruby or Xcode upgrade was reported as ✓ by `doctor` and only blew up later, at `pod install`, after a full build had already run. Tool detection now distinguishes four states instead of found/not-found: `ok`, `broken` (resolves but won't execute), `installedNotOnPath` (gem present in a gem bin dir the shell never exported), and `missing` — and applies the matching repair for each.
- Install and repair the Ruby toolchain automatically. `torchinlane init` now sets up fastlane and CocoaPods at their latest published versions *before* asking for your bundle IDs, so a broken toolchain surfaces immediately instead of after ten config prompts (`--skip-tools` opts out; failures only warn, since scaffolding on a non-building machine is valid). Installation uses `gem install --no-document`, falls back to `--user-install` when the active gem dir isn't writable (macOS system Ruby) rather than escalating to sudo, and runs `pod setup` after installing CocoaPods so the first `pod install` doesn't fail on a missing spec repo.
- Fix `doctor` reporting fastlane as missing when it is installed but not on `PATH`. Instead of just naming the problem, `torchinlane doctor --fix` now installs what's missing, reinstalls what's broken, and appends the gem bin directory to your shell profile (`~/.zshrc`, `~/.bashrc`, or `~/.bash_profile`, written once and marked). Note that a profile export cannot affect the already-running shell, so `doctor` tells you to reload it.
- Preflight tools before `torchinlane deploy`. fastlane (and CocoaPods, for iOS) are verified and repaired up front, so a missing gem no longer wastes a full `flutter build ipa` before failing. Deploy steps also run with the gem bin directories prepended to `PATH`, so a gem installed moments earlier in the same run resolves without reloading your shell first.
- `doctor` now prints real versions (`✓ fastlane 2.230.0`, `✓ pod 1.16.2`) rather than a bare "on PATH", and treats CocoaPods as required only on macOS.

## 0.1.11

- Automate Flutter symbol handling for obfuscated builds. The generated `scripts/build.sh` now, after each Android and iOS build, archives the `--split-debug-info` symbols per version to `build/debug-info-archive/<version>/` (so they survive `flutter clean`) and, when a Firebase App ID is configured, uploads them to Crashlytics via `firebase crashlytics:symbols:upload` — so obfuscated Dart crash reports symbolicate automatically. Without a Firebase App ID it archives only and prints the exact `flutter symbolize` command for manual de-obfuscation. Two optional config fields were added — `ios.firebase_app_id` and `android.firebase_app_id` (also promptable in `torchinlane init`, overridable via `IOS_FIREBASE_APP_ID` / `ANDROID_FIREBASE_APP_ID` env vars). Existing projects: run `torchinlane update` to pick up the new build script.
- Add an automatic update notice. Every `torchinlane` command now checks pub.dev for a newer release and, if one exists, prints a non-blocking warning telling you to run `dart pub global activate torchinlane` then `torchinlane update`. The check is cached for 24h (`~/.torchinlane/version_check.json`), times out fast, fails silently offline, and can be disabled with `TORCHINLANE_SKIP_VERSION_CHECK=1`.

## 0.1.10

- Fix iOS deploy reporting failure after a successful build and store upload. The generated iOS `upload_dsyms_to_crashlytics` lane called `upload_symbols_to_crashlytics` unconditionally, which raises (`Failed to find Fabric's upload_symbols binary`) when Firebase Crashlytics is selected but not fully configured (missing `GoogleService-Info.plist` or the `FirebaseCrashlytics` pod) — crashing the whole lane even though TestFlight/App Store upload already succeeded. The lane now checks for the `upload-symbols` binary and `GoogleService-Info.plist` first, prints a clear "skipping dSYM upload" notice and exits gracefully if either is missing, and passes `binary_path` explicitly when present.

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
