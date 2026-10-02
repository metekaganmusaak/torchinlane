# Example Flutter app release

Run from a Flutter application with ios/ and android/ directories:

```bash
torchinlane studio
```

Complete Setup, import store credentials, verify app access, add English/Turkish
locales, save texts and import localized images. Use the Upload panel to validate
and upload. Keep credentials and signing files out of Git.

Equivalent terminal workflow:

```bash
torchinlane init
torchinlane credentials import --platform ios --file /path/AuthKey_KEYID.p8
torchinlane credentials import --platform android --file /path/google.json
torchinlane credentials verify
torchinlane store init --locales en,tr
```

Edit `store/ios/en-US.json` and `store/android/en-US.json` and place images in:

```text
store/ios/images/tr/iphone/01-home.png
store/android/images/tr-TR/phoneScreenshots/01-home.png
store/android/images/tr-TR/featureGraphic/banner.png
```

```bash
# Print an agent task; paste it into Claude Code/Codex in this Flutter project.
torchinlane store prompt --from en --locales tr
# After the agent fills the target JSON files:
torchinlane store validate
torchinlane store push --scope metadata --dry-run
torchinlane deploy --platform ios,android --target production --with-store
```

The application needs valid native signing. Google releases default to draft;
Apple production is uploaded without review submission. For a later Google
note-only correction to an existing production release:

```bash
torchinlane store push --platform android --scope notes --track production --version-code 42
```

See [README](../README.md), [store content](../doc/store-content.md) and
[automation/signing](../doc/automation.md) for first-release prerequisites,
keyless CI and additional commands.
