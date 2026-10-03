# Upgrade to 0.2.3

Run `dart pub global activate torchinlane 0.2.3`, close any running Studio,
then run `torchinlane update -y` inside your Flutter project and reopen it with
`torchinlane studio`. This regenerates both Appfiles to fix Fastlane’s
`require_relative: cannot infer basepath` error. Changed generated files receive
`.bak` backups; credentials and store content are reused. Studio’s generated-file
repair button can also perform this update after restarting the upgraded CLI.

# Upgrade from 0.1.x to 0.2.0

1. Upgrade/install the CLI: `dart pub global activate torchinlane 0.2.0`.
   For a development checkout, use
   `dart pub global activate --source path /path/to/torchinlane`.
2. Run `torchinlane update --dry-run`, then `torchinlane update -y` inside every
   previously initialized app. Generated Fastfiles now require StoreHelper and
   the generated locale JSON. Changed files receive `.bak` backups.
3. Run `torchinlane store init --locales en,tr,...` or add locales in Studio.
   This creates new store JSON files without touching old `changelogs/`.
4. Import credentials or reuse their configured paths. Custom `.p8`, Google
   JSON and changelog paths are now honored by generated lanes. For reusable
   credential profiles, absolute paths are local to that machine; CI should
   override them using environment variables.
5. Run `torchinlane credentials verify --platform ...` and `store validate`.

## Behavior changes

- App Store production release notes are actually uploaded as metadata. First
  Apple versions skip the unavailable What's New field without deleting local notes.
- Deploy checks live app access before building; `--skip-credential-check` skips
  this in an already verified CI job. Platforms with failed access checks are
  reported while other platforms can proceed.
- TestFlight can attach localized notes; processing is awaited when notes are
  supplied, with a 30-minute timeout. Empty notes preserve the faster upload.
- Bangla maps to Apple `bn-BD`, Google Hebrew to `iw-IL`, and Filipino is skipped
  on Apple. The registry includes native regional variants and new Apple
  languages. Default legacy source locales remain unchanged (32).
- Independent Android note updates require an explicit `--version-code` and
  accept `--track`. Other languages' notes and release properties are preserved.
- Over-limit notes now fail instead of being silently cut. Duplicate legacy
  folders resolving to one store locale fail instead of overwriting each other.
- Successful generated build-script uploads retain notes; clear explicitly.
- Google internal builds remain **drafts** by default, therefore are not served.
  Choose `--release-status completed` explicitly to serve a release.
- Empty metadata JSON fields mean no change, not deletion. The new JSON notes
  override legacy notes for the same release when `deploy --with-store` runs.
- Android screenshot capture now reads raw PNG bytes.
- API model is configurable through `TORCHINLANE_AI_MODEL`; default is
  `claude-sonnet-4-6`. The previous fixed model ID was replaced.

## New files and ownership

Generated/managed: iOS/Android Fastfiles/Appfiles, ChangelogHelper, StoreHelper,
locale JSON and `scripts/build.sh`. `update` regenerates these.

User-owned: `torchinlane.yaml`, `store/`, `changelogs/`, ExportOptions, signing
assets/configuration and generated CI workflows. `update` does not remove or
replace them. GUI setup preserves advanced configuration while updating fields
you edited and synchronizes generated files with backups. Signing commands
explicitly update signing files with backups as documented.

The old `screenshots` YAML section was never loaded by the capture command;
it remains reserved. The current command reads devices directly and writes
`screenshots/`; locale labels do not switch the application language.

Historical CHANGELOG entries describe the release they belong to. Current
behavior is documented in README and the new 0.2.0 entry.

## Translation default

`store translate` now prints a local coding-agent task rather than contacting
Anthropic. `store prompt` is an explicit alias. Scripts that need the former
direct API behavior must add `--api`. Studio task generation works without
`ANTHROPIC_API_KEY`; only its optional API button requires that key. Legacy
`changelog translate` retains its API behavior.

## Studio improvements in 0.2.1

Upgrade with `dart pub global activate torchinlane 0.2.1`, then reopen Studio.
Existing store files and credential paths need no conversion. The panel opens a
readiness checklist, recognizes completed steps and remembers the selected stores.
Successful live access checks last for the server session; restarting Studio asks
for a new check, but never requires importing a still-valid key again. The default
standalone upload is metadata only; select release notes/all explicitly when
needed. Advanced options remain available under details.
