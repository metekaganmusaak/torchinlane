# Store content reference

## Storage and locale policy

`store/<platform>/<native-locale>.json` is the source of truth for new store
content. `store/<platform>/images/<native-locale>/<group>/` holds image files.
Locale codes are exact/case-sensitive. Use `store locales` to list them.
Commands accepting locale selections also understand legacy aliases (`en`,
`tr`, `pt`, `zh`, `tl`). Aliases map explicitly; unsupported entries are skipped
during initialization. Files written/uploaded by Studio use native codes.

Apple and Google support lists are distinct. For example:

| Input | Apple | Google |
| --- | --- | --- |
| `tr` | `tr` | `tr-TR` |
| `bn` | `bn-BD` | `bn-BD` |
| `he` | `he` | `iw-IL` |
| `tl` | unsupported | `fil` |
| `fa` | unsupported | `fa` |
| `zh-Hans` | `zh-Hans` | `zh-CN` |
| `zh-Hant` | `zh-Hant` | `zh-TW` |
| `pt-PT` | `pt-PT` | `pt-PT` |

A regional code that a store does not support is not silently replaced by a
language from another region. E.g. Google-only English regional variants do
not automatically become Apple en-US.

Registry sources, checked 2026-10-03:

- [Apple API locale shortcodes](https://developer.apple.com/documentation/appstoreconnectapi/managing-metadata-in-your-app-by-using-locale-shortcodes)
- [Apple store localizations](https://developer.apple.com/help/app-store-connect/reference/app-information/app-store-localizations/)
- [Fastlane Google locale registry](https://github.com/fastlane/fastlane/blob/master/supply/lib/supply/languages.rb)

The maintained Dart registry generates `fastlane/locales.json` during init/update;
Ruby reads that generated JSON. Tests require every native code to resolve to
itself. The registry is a versioned snapshot, not a runtime web scrape. Update it
when official support changes, then run `torchinlane update` in consuming apps.

## Text fields

| Platform | Field | Limit |
| --- | --- | --- |
| Apple | `name` | 2–30 characters |
| Apple | `subtitle` | 30 |
| Apple | `description` | 4000 |
| Apple | `keywords` | 100 UTF-8 bytes |
| Apple | `promotional_text` | 170 |
| Apple | `release_notes` | 4000 |
| Apple | `support_url`, `marketing_url`, `privacy_url` | HTTP(S) URL validation |
| Google | `title` | 30 |
| Google | `short_description` | 80 |
| Google | `full_description` | 4000 |
| Google | `release_notes` | 500 |
| Google | `video` | HTTP(S) URL validation; Google enforces YouTube rules |

Limits count Unicode code points locally, except Apple keywords which count UTF-8 bytes. Store APIs are the final authority.
Unknown fields are rejected. Blank fields do not delete remote text. `scope`
selects which content is validated/exported/uploaded. Metadata excludes release
notes; notes includes only release notes; images includes only image assets.

Sources: [Google listing fields](https://support.google.com/googleplay/android-developer/answer/9859152?hl=en),
[Apple app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/),
[Apple version information](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information/).

## Translation with Claude Code or Codex

The default translation workflow does not call an API:

```bash
torchinlane store prompt --from en
# Alias; explicit target locales are supported:
torchinlane store translate --from en --locales tr,de,pt-PT
```

Fill source texts and add target locales first. Without `--locales`, the task
uses the JSON locales already present for each store. `--locales all` includes
all supported native locales per store; unsupported codes are omitted separately
for each store. No files are changed during task generation.

In Studio choose **Prepare agent task**, then **Copy task**. Paste it into
Claude Code or Codex working in the Flutter project. The generated task includes
exact allowed target paths, source/target snapshots, pending fields, native locale
codes and limits. It instructs the agent to preserve existing translations and
URLs, protect newer edits, avoid invented features, and validate the result.
`--overwrite` explicitly permits replacing the listed translated fields. Review
the agent's diff; instructions are guidance to that agent, not a sandbox enforced
by Torchinlane. Click **Reload agent changes** to reload and validate in Studio.
No translation API key is needed by Torchinlane; the coding agent's own usage
limits still apply. Tasks contain selected store text, so share them deliberately.

Direct API translation remains optional:

```bash
# Requires ANTHROPIC_API_KEY; may incur separate API charges.
torchinlane store translate --api --from en --locales tr,de
```

API translation respects field limits, preserves populated fields by default,
and uses one request per target locale. Incomplete/truncated/over-limit responses
fail for that target. Completed locales remain saved. API CLI defaults to configured
changelog locales; Studio uses added locales. Legacy `changelog translate` remains
an API command. AI output is a draft; review brand names and claims before upload.

## Images

Apple groups: `iphone`, `ipad`. Google groups: `phoneScreenshots`,
`sevenInchScreenshots`, `tenInchScreenshots`, `tvScreenshots`, `wearScreenshots`,
`icon`, `featureGraphic`, `tvBanner`.

Images must be PNG/JPEG, within the tool's 20 MB input limit. Apple screenshots
must match a supported device resolution. Google general screenshot dimensions
must be 320–3840 px with the longest side no more than twice the shortest.
Feature graphic: 1024×500; icon: 512×512; TV banner: 1280×720. Transparent
screenshot/feature/banner pixels are rejected; Google icons may have alpha.

Count checks: up to 10 Apple images **per resolution**; up to 8 Google images
per screenshot group; one local icon/feature/banner. These are preflight checks,
not a complete store submission checklist. Required device sets, minimum
screenshots, device-specific requirements, content rules and promotion
eligibility remain store requirements.

Filenames sort lexicographically. Use zero-padded prefixes (`01`, `02`, …).
Studio's arrows rename the local files to a stable numbered order. Export names
retain the group (`ipad` in the filename helps Fastlane distinguish shared
Apple resolutions). The generated staging directories are cleaned after uploads.

Google uses checksum-based synchronization for supplied screenshot groups.
Unspecified groups remain unchanged. Apple appends by default. **Apple
`--replace-images` clears all existing device screenshot sets for each supplied
locale**, including sets absent locally; supply a complete locale set before
choosing replacement. This is Fastlane deliver's documented implementation
behavior, not a selective per-device patch.

Sources: [Google assets](https://support.google.com/googleplay/android-developer/answer/9866151?hl=en),
[Apple screenshots](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/),
[deliver](https://docs.fastlane.tools/actions/deliver/), [supply](https://docs.fastlane.tools/actions/supply/).

## First release and editable state

Create the application record before uploading content. For the current
Fastlane/Google flow, initialize the app in Play Console and upload its first
build there. Complete account verification, declarations, app signing and any
required testing/review steps. Later builds and localized content can be
uploaded by Torchinlane.

Apple metadata must target an editable app/version state; a .p8 key does not
create an app record automatically here. Apple's first version handles What's
New differently from update versions; Torchinlane detects the absence of a live Apple version and skips What's New
uploads while retaining the notes locally. Independent legacy Apple note-only
updates report that the first version has no What's New field. Metadata localization does not
add languages to your Flutter application's UI.

Pull saves remote text to ignored snapshots, reports differing fields, and
imports only with `--apply`, backing up existing local text. It does not fetch
screenshots. Google pull is listing metadata; choose an existing track/version
when pushing notes. Binary deploy remains separate from store content push.
