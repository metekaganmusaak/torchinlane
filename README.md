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

### Upgrading to a new version

> **Important:** upgrading the CLI does **not** touch already-scaffolded
> projects. When a new torchinlane version ships, each existing project must run
> `torchinlane update` to pick up template changes (new `scripts/build.sh`
> steps, Fastfile fixes, etc.). Skipping it means your project keeps running the
> old generated files.

```bash
dart pub global activate torchinlane   # 1. upgrade the CLI itself
torchinlane update                     # 2. run inside each project to re-sync
```

`update` never overwrites your own files (`torchinlane.yaml`, release notes,
`ExportOptions.plist`) and backs up every changed file as `*.bak`.

**First-time users don't need `update`.** A fresh `torchinlane init` always
generates from the current version's templates, so every change is already
included. `update` only matters for projects scaffolded by an older CLI.

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

`init` also writes an executable **`scripts/build.sh`** — an interactive,
menu-driven wrapper for the whole build+deploy flow (see below).

### `scripts/build.sh` — interactive build & deploy

Instead of remembering `torchinlane deploy` flags, run the generated script
from your project root:

```bash
sh scripts/build.sh
```

It walks you through the release step by step, in this order:

1. **Only-upload mode** — skip building and just upload the AAB/IPA already in
   `build/` (for retrying a failed upload).
2. **Platforms** — build Android, iOS, or both.
3. **Upload + target** — whether to upload, and to Internal (TestFlight / Play
   Internal testing) or Production (App Store / Play production).
4. **Release notes** — type your English (source-locale) notes right in the
   terminal, ending with an empty line. The previous notes are **cleared
   first** so a stale note is never shipped. An **empty note is allowed** (the
   stores keep their current text). If `ANTHROPIC_API_KEY` is set, the notes
   are **translated into every configured locale**; otherwise only the source
   note ships. Notes are cleared again after a successful upload.
5. **Version bump** — shows the exact resulting version for each choice before
   you pick, then runs `torchinlane bump`:

   ```text
   Version bump — current: 0.1.7
     1) patch  -> 0.1.8+1   (bug fix; z+1, build+1)
     2) minor  -> 0.2.0+1   (new feature; y+1, z=0, build+1)
     3) major  -> 1.0.0+1   (breaking change; x+1, y=z=0, build+1)
     4) build  -> 0.1.7+1   (same version, build+1 — re-upload)
     5) skip   -> 0.1.7   (no change)
   ```

6. **Deep clean** — optionally wipe native caches (`.gradle`, Pods,
   DerivedData) before building.

Builds are always **obfuscated** with `--split-debug-info` (symbol maps kept
in `build/debug-info`), and iOS builds verify that **dSYMs** were generated so
Crashlytics symbolication works. Uploads go through the fastlane lanes that
`init` scaffolded.

### `torchinlane uninstall`

Removes everything `torchinlane init` created — `ios/fastlane/`,
`android/fastlane/`, `fastlane/`, `ios/ExportOptions.plist`,
`scripts/build.sh`, and `torchinlane.yaml`. Leaves `changelogs/` untouched.

```bash
torchinlane uninstall          # asks for confirmation
torchinlane uninstall --yes    # skip confirmation
```

### `torchinlane update`

After you upgrade the CLI itself:

```bash
dart pub global activate torchinlane   # get the latest CLI
torchinlane update                     # re-apply its templates to this project
```

`update` reads your `torchinlane.yaml` and re-renders the generated files —
iOS/Android Fastfiles + Appfiles, `fastlane/ChangelogHelper.rb`, and
`scripts/build.sh` — so a project picks up template fixes shipped in a newer
CLI version. For each file that changed it prints a line diff and asks before
writing; every overwritten file is backed up as `<file>.bak` (gitignored).
User-owned files (`ios/ExportOptions.plist`, your release notes, and
`torchinlane.yaml`) are never touched.

```bash
torchinlane update            # diff + confirm each changed file
torchinlane update -y         # apply all changes without prompting
torchinlane update --dry-run  # show what would change, write nothing
```

For a full clean regeneration instead (overwrites everything, re-asks the
prompts), use `torchinlane init --force`.

### `torchinlane deploy`

Runs `flutter clean && flutter pub get`, builds (obfuscated), and uploads via
fastlane. Android and iOS build/upload independently — if one fails the
other still runs, and the command reports which platform(s) failed at the
end.

```bash
torchinlane deploy --platform ios,android --target internal
torchinlane deploy --platform ios --target production
torchinlane deploy --platform android --target production
torchinlane deploy --platform ios,android --target production
torchinlane deploy --platform android --target internal --upload-only
torchinlane deploy --dry-run
```

#### Flags

| Flag | Default | What it does |
| --- | --- | --- |
| `--platform` | `ios,android` | Which platform(s) to build/deploy. `ios`, `android`, or `ios,android`. |
| `--target` | `internal` | `internal` = TestFlight (iOS) / Internal Testing track (Android). `production` = App Store / Play Store production track — see below, this still requires a manual final step. |
| `--upload-only` | off | Skip `flutter build`; upload the AAB/IPA that's already in `build/`. Useful for retrying a failed upload without rebuilding. |
| `--skip-clean` | off | Skip `flutter clean && flutter pub get` before building. Faster iteration when you know the build is already clean. |
| `--deep-clean` | off | Also wipe `android/.gradle`, `android/app/build`, `ios/Pods`, `ios/Podfile.lock` before building. Use when you suspect stale native caches. |
| `--skip-release-notes` | off | Upload without attaching changelog text, regardless of what's in `changelogs/`. |
| `--dry-run` | off | Print every command that would run, without executing anything. Good for sanity-checking a config before a real deploy. |

#### `--target internal` — what happens

- **Android**: builds an AAB, uploads it to the Play Console **Internal Testing** track as a draft. Visible immediately to your internal testers list, no review needed.
- **iOS**: builds an IPA, uploads it to App Store Connect and submits it to **TestFlight**. Available to internal testers right away; external testers need Apple's (usually quick) beta review.

#### `--target production` — what happens

This uploads the build to the production track/App Store, but **does not
publish it live** — the final "make it public" step is manual, on purpose,
so a script can never accidentally ship to real users.

- **Android**: uploads the AAB to the Play Console **production** track with
  `release_status: draft`. It sits there until you go to Play Console →
  Production → Review release → **Start rollout to production**.
- **iOS**: uploads the IPA to App Store Connect with `submit_for_review:
  false` and `automatic_release: false`. The build appears in App Store
  Connect but is never submitted for review automatically. You attach it to
  a version and hit **Submit for Review** yourself.

So `torchinlane deploy --target production` gets the binary in front of
Apple/Google, but you still press the final button in each store's
dashboard.

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

#### How to update the changelog for a release

`torchinlane init` scaffolds an empty `changelogs/<locale>/release_notes.txt`
for every locale. `torchinlane deploy` reads these files and attaches them to
the store upload automatically — **if a file is empty, deploy does not fail,
it just uploads without release notes for that locale.**

1. **Find your source locale.** It's whatever you entered at the
   `Source locale for changelog translation` prompt during `torchinlane
   init` (check `changelogs.source_locale` in `torchinlane.yaml` if you
   forgot — it defaults to `en`).

2. **Write your release notes into that locale's file.** For example, if
   your source locale is `en`:

   ```bash
   echo "Bug fixes and performance improvements." > changelogs/en/release_notes.txt
   ```

   Or open `changelogs/en/release_notes.txt` in an editor and write freely
   — multi-line text is fine.

3. **(Optional) Translate to the other 31 store locales** using the Claude
   API:

   ```bash
   export ANTHROPIC_API_KEY=your-key
   torchinlane changelog translate --from en
   ```

   This reads `changelogs/en/release_notes.txt` and writes a translated
   version into every other `changelogs/<locale>/release_notes.txt`. Skip
   this step if you only ship one locale, or want to write translations by
   hand.

4. **Deploy.** `torchinlane deploy` picks up the notes automatically:

   ```bash
   torchinlane deploy --platform ios,android --target internal
   ```

   Pass `--skip-release-notes` to upload a build without attaching any
   changelog, regardless of what's in the files.

5. **After the release, clear the notes** so next time's changelog doesn't
   accidentally reuse old text:

   ```bash
   torchinlane changelog clear
   ```

If you'd rather push updated release notes to the stores without shipping a
new binary (e.g. you forgot to add notes to an already-uploaded build), use:

```bash
torchinlane changelog push --platform ios,android
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
