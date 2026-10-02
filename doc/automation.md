# Credentials, signing and unattended releases

## One-time actions that remain outside the CLI

- Register/verify Apple and Google developer accounts; accept agreements and
  complete account-specific/legal declarations.
- Apple Account Holder requests API access; generate/download the first `.p8`
  in App Store Connect. A private key is downloadable only once. Enter Key ID,
  Issuer ID and Developer Team ID; an individual key has no team issuer.
- Create store app records. The Fastlane/Google initialization flow requires
  the first build uploaded in Play Console.
- Grant the Google service account Play Console app/release permissions.
- Supply or create the app's signing identities. Torchinlane can create iOS
  certificates/profiles via `match --write`, subject to Apple permissions; the
  Android signing command imports an existing upload keystore.

After those steps, routine content translation, validation, signing restoration,
building, binary upload and localized store updates can run without terminal
prompts. Apple review submission remains manual in this version. Google serving
status is explicit; drafts are not served even on the internal track.

## Google bootstrap

Prerequisites: `gcloud`, an existing Cloud project, a logged-in principal with
service enablement and IAM permissions. Organizations may prohibit JSON keys.

```bash
gcloud auth login
torchinlane credentials bootstrap-google --project-id my-cloud-project --dry-run
# Enable APIs, create/reuse account and create/import its key:
torchinlane credentials bootstrap-google --project-id my-cloud-project --create-key
```

The default service account ID is `torchinlane`; override with `--account`.
Cloud APIs enabled: Google Play Developer API, IAM, IAM Credentials. The command
does not create a Cloud project, enroll a Play developer or grant Cloud Owner.
It prints the service-account email for the remaining Play Console invitation.
Created keys are imported through the protected credential importer and the
intermediate key file is deleted. Existing different imported keys are not
silently replaced; choose a new configured path/profile for rotation.

For keyless GitHub CI:

```bash
torchinlane credentials bootstrap-google \
  --project-id my-cloud-project --repository ExactOwner/ExactRepo
```

Creates/reuses `torchinlane-github` pool and a repository-specific provider.
The provider's condition and principal-set grant restrict authentication to
that exact repository. The provider resource printed by the command is used
in `ci init`. The service account still needs Play Console permissions. Protect
who can edit/run release workflows in that repository.

Google `external_account` and service-account JSON work with Fastlane. A current
Fastlane release also supports `authorized_user` OAuth JSON. OAuth client
creation, consent-screen configuration and user login are not automated here.
Do not advertise a zero-configuration Google OAuth sign-in button: it would
still require those prerequisites.

## Reusable credential profiles

```bash
torchinlane credentials import --platform ios --file AuthKey_KEYID.p8 --profile company-apple
torchinlane credentials import --platform android --file google.json --profile company-google
```

Profiles are stored outside the repo under `~/.torchinlane/credentials/`, with
0700 directories and 0600 files on POSIX. Each project's YAML records the
absolute path. Import the same credential into another project using the same
profile, or set its YAML path to the existing profile file. CI should use the
environment overrides rather than another computer's absolute paths.

Default local imports protect the destination file and add a gitignore entry.
The CLI validates credential structure, then `credentials verify` checks live
app access. Import does not prove permissions. `doctor --verify-credentials`
also performs the live check after local/tool checks. Google's verification
uses an uncommitted edit that is discarded.

## Android upload signing

```bash
export KEYSTORE_PASSWORD='your store password'
export KEY_PASSWORD='your key password'
torchinlane signing android --keystore /path/upload-keystore.jks --alias upload --dry-run
torchinlane signing android --keystore /path/upload-keystore.jks --alias upload
```

The command backs up and updates a stock Flutter `build.gradle` or
`build.gradle.kts`, imports the key to `.torchinlane/upload-keystore.jks`, and
writes `android/key.properties`. Use the upload key already registered for a
published app. Custom Gradle signing layouts are preserved and reported for
manual integration. For them, read the generated `key.properties` fields in
your existing release signing block; do not add a second `signingConfigs`
block blindly. Password env names can be customized with
`--store-password-env` and `--key-password-env`.

## iOS certificates and provisioning

Use a private encrypted match repository accessible by SSH or
`MATCH_GIT_BASIC_AUTHORIZATION`; set `MATCH_PASSWORD` for repository encryption.

```bash
torchinlane signing sync --git-url git@github.com:company/certificates.git --write
```

`--write` lets Fastlane create/renew Apple distribution certificates and
App Store profiles and save them in the repository. Later machines should run
without `--write` to reuse existing identities. All signing sync operations
configure local Release/Profile settings in `ios/Runner.xcodeproj` and set
ExportOptions to manual signing with the installed profile; local files get
`.bak` backups. Read-only refers to the match repository/Apple identity
creation, not the local Xcode project. CI sets up a temporary keychain.

Multi-target projects, extensions, flavors and enterprise/ad-hoc signing require
additional app identifiers and profiles; the generated lane handles the
configured Runner bundle ID/App Store type. Existing export fields are
preserved when profile mapping/signingStyle are updated.

## GitHub Actions generation

```bash
torchinlane ci init --platform ios,android \
  --flutter-version stable \
  --wif-provider projects/123/locations/global/workloadIdentityPools/torchinlane-github/providers/github-ID \
  --service-account torchinlane@my-cloud-project.iam.gserviceaccount.com \
  --signing-git-url git@github.com:company/certificates.git
```

Creates a manual `workflow_dispatch` workflow with a target selector and a
store-upload checkbox, separate macOS/Ubuntu jobs, serialized release runs,
Ruby/Flutter/Fastlane setup, CLI/template update, signing restoration, API
verification and deploy. Files are not overwritten unless `--force` is supplied;
existing workflow files receive a backup. `--dry-run` prints YAML only.

The CLI version is pinned to the generator version. If you use an unpublished
development version, replace its pub.dev activation line with your private
Git/source installation.
For reproducibility, pass a Flutter version tag instead of the moving `stable`
branch and pin Gem/action revisions according to your CI policy.

Required repository secrets:

| Platform | Secret | Value |
| --- | --- | --- |
| Android | `ANDROID_KEYSTORE_BASE64` | Base64 of the existing upload keystore |
| Android | `ANDROID_KEYSTORE_PASSWORD` | Store password |
| Android | `ANDROID_KEY_PASSWORD` | Key password |
| Android | `ANDROID_KEY_ALIAS` | Registered upload key alias |
| Android, JSON mode | `GOOGLE_PLAY_CREDENTIALS_JSON` | Service account JSON |
| iOS | `ASC_KEY_P8` | Raw .p8 contents |
| iOS | `ASC_KEY_ID` | Key ID; config may also supply this |
| iOS | `ASC_ISSUER_ID` | Team issuer UUID; blank for individual keys |
| iOS | `MATCH_PASSWORD` | Match repository encryption password |
| iOS, HTTPS repo | `MATCH_GIT_BASIC_AUTHORIZATION` | Base64 basic authorization for private Git |

For an SSH match URL, arrange an SSH deploy key in the runner or use an HTTPS
URL with basic authorization. The generator does not create private Git repos
or provision deploy keys. WIF mode requires no `GOOGLE_PLAY_CREDENTIALS_JSON`.
Authentication runs after tool/signing setup and immediately before verification
and deployment. Long-lived/retried builds may require refreshing CI OIDC
credentials; runner tokens have provider-specific lifetime constraints.

Android CI restores key.properties and applies the standard Gradle integration.
For iOS, omitting `--signing-git-url` generates a clearly failing prerequisite
step that must be replaced with existing signing setup or regenerated. A key
alone is insufficient to build a signed IPA.

The generated workflow leaves Google releases as drafts and Apple versions
unsubmitted. To automate Google serving, add `--release-status completed` to
its deploy step, or `--release-status inProgress --rollout 0.1` for a staged
production rollout. Account review/testing restrictions still apply.

## What is and is not automated

| Operation | Current behavior |
| --- | --- |
| Locale text/image upload | Automatic from saved project content |
| Metadata/release-note translation | API-free coding-agent tasks; optional API for unattended translation |
| Google IAM/API/WIF setup | Automated after gcloud login/permissions |
| Credential import/reuse/access test | Automated |
| Android stock Gradle signing | Automated from an existing upload key |
| iOS certificates/profiles | Fastlane match sync/create with explicit write mode |
| GitHub release workflow | Generated; secrets/account prerequisites required |
| Screenshot navigation and localized artwork | App-specific integration/design work remains |
| App creation/initial Play build | Console bootstrap remains |
| Apple key generation/API access | Authorized user action remains |
| Legal/privacy declarations and developer registration | Account owner supplies these |
| Apple final review submission | Manual in this release |

Primary references:
[Apple API setup](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-api/),
[Google API setup](https://developers.google.com/android-publisher/getting_started),
[Google IAM](https://docs.cloud.google.com/iam/docs/service-accounts-create),
[GitHub Google authentication](https://github.com/google-github-actions/auth),
[Fastlane match](https://docs.fastlane.tools/actions/match/),
[Flutter Android signing](https://docs.flutter.dev/deployment/android#sign-the-app).
