/// Fastlane scaffold templates, ported from a working Fastfile/Appfile setup.
/// Placeholders use {{name}} syntax and are replaced by [renderTemplate].
library;

const iosAppfileTemplate = '''
app_identifier("{{bundle_id}}")
apple_id("{{apple_id}}")
itc_team_id("{{itc_team_id}}")
team_id("{{team_id}}")
''';

const androidAppfileTemplate = '''
json_key_file("{{service_account_json}}")
package_name("{{package_name}}")
''';

const iosFastfileTemplate = '''
require_relative '../../fastlane/ChangelogHelper'

default_platform(:ios)

platform :ios do
  desc "Push a new beta build to TestFlight"
  lane :beta do
    api_key = app_store_connect_api_key(
      key_id: "{{asc_key_id}}",
      issuer_id: "{{asc_issuer_id}}",
      key_filepath: File.expand_path("../api_key.p8", __FILE__),
      duration: 1200,
      in_house: false
    )

    changelogs_dir = File.expand_path('../../changelogs', __dir__)
    skip_release_notes = ENV['FASTLANE_SKIP_RELEASE_NOTES'] == '1'
    testflight_changelog = ChangelogHelper.testflight_changelog(changelogs_dir, '{{source_locale}}')

    upload_options = {
      api_key: api_key,
      ipa: Dir[File.expand_path("../../../build/ios/ipa/*.ipa", __FILE__)].first,
      skip_waiting_for_build_processing: true
    }

    upload_options[:changelog] = testflight_changelog if !skip_release_notes && !testflight_changelog.to_s.empty?

    upload_to_testflight(upload_options)
{{#firebase}}
    upload_dsyms_to_crashlytics
{{/firebase}}
  end
{{#firebase}}

  desc "Upload dSYMs to Firebase Crashlytics"
  private_lane :upload_dsyms_to_crashlytics do
    dsym_directory = File.expand_path("../../../build/ios/archive/Runner.xcarchive/dSYMs", __FILE__)
    zipped_dsym_path = File.expand_path("../../../build/ios/dSYMs.zip", __FILE__)
    gsp_path = File.expand_path("../../Runner/GoogleService-Info.plist", __FILE__)

    if File.directory?(dsym_directory)
      dsym_files = Dir.glob("#{dsym_directory}/*.dSYM")

      if dsym_files.empty?
        UI.error("dSYM files not found: #{dsym_directory}")
      else
        UI.success("Found #{dsym_files.count} dSYM files")
        sh "cd \\"#{dsym_directory}\\" && zip -r \\"#{zipped_dsym_path}\\" *.dSYM"

        if File.exist?(zipped_dsym_path)
          upload_symbols_to_crashlytics(
            gsp_path: gsp_path,
            dsym_path: zipped_dsym_path
          )
          UI.success("dSYMs uploaded to Firebase Crashlytics")
        else
          UI.error("Failed to create dSYM zip")
        end
      end
    else
      UI.error("dSYM directory not found: #{dsym_directory}")
    end
  end
{{/firebase}}

  desc "Release to App Store production (all locales)"
  lane :release do
    changelogs_dir = File.expand_path('../../changelogs', __dir__)
    skip_release_notes = ENV['FASTLANE_SKIP_RELEASE_NOTES'] == '1'

    api_key = app_store_connect_api_key(
      key_id: "{{asc_key_id}}",
      issuer_id: "{{asc_issuer_id}}",
      key_filepath: File.expand_path("../api_key.p8", __FILE__),
      duration: 1200,
      in_house: false
    )

    release_notes = ChangelogHelper.app_store_release_notes(changelogs_dir)
    deliver_options = {
      api_key: api_key,
      ipa: Dir[File.expand_path("../../../build/ios/ipa/*.ipa", __FILE__)].first,
      submit_for_review: false,
      automatic_release: false,
      force: true,
      skip_metadata: true,
      skip_screenshots: true,
      skip_app_version_update: true
    }

    deliver_options[:release_notes] = release_notes if !skip_release_notes && !release_notes.empty?

    deliver(deliver_options)
{{#firebase}}
    upload_dsyms_to_crashlytics
{{/firebase}}
  end

  desc "Update App Store release notes only (no binary upload)"
  lane :update_release_notes do
    changelogs_dir = File.expand_path('../../changelogs', __dir__)
    release_notes = ChangelogHelper.app_store_release_notes(changelogs_dir)

    api_key = app_store_connect_api_key(
      key_id: "{{asc_key_id}}",
      issuer_id: "{{asc_issuer_id}}",
      key_filepath: File.expand_path("../api_key.p8", __FILE__),
      duration: 1200,
      in_house: false
    )

    deliver(
      api_key: api_key,
      release_notes: release_notes,
      skip_binary_upload: true,
      skip_screenshots: true,
      skip_metadata: false,
      force: true
    )
  end
{{#firebase}}

  desc "Standalone lane to only upload dSYMs"
  lane :upload_dsyms do
    upload_dsyms_to_crashlytics
  end
{{/firebase}}
end
''';

const androidFastfileTemplate = '''
require_relative '../../fastlane/ChangelogHelper'

default_platform(:android)

platform :android do
  desc "Upload AAB to Google Play Internal Testing"
  lane :deploy_internal do
    changelogs_dir = File.expand_path('../../changelogs', __dir__)
    skip_release_notes = ENV['FASTLANE_SKIP_RELEASE_NOTES'] == '1'
    metadata_path = skip_release_notes ? nil : ChangelogHelper.write_google_play_metadata(changelogs_dir)

    upload_options = {
      track: 'internal',
      aab: '../build/app/outputs/bundle/release/app-release.aab',
      release_status: 'draft'
    }
    if metadata_path
      upload_options[:metadata_path] = metadata_path
      upload_options[:skip_upload_metadata] = true
      upload_options[:skip_upload_images] = true
      upload_options[:skip_upload_screenshots] = true
      upload_options[:skip_upload_changelogs] = false
    else
      upload_options[:skip_upload_metadata] = true
    end

    upload_to_play_store(upload_options)
  end

  desc "Upload AAB to Google Play Production"
  lane :deploy_production do
    changelogs_dir = File.expand_path('../../changelogs', __dir__)
    skip_release_notes = ENV['FASTLANE_SKIP_RELEASE_NOTES'] == '1'
    metadata_path = skip_release_notes ? nil : ChangelogHelper.write_google_play_metadata(changelogs_dir)

    upload_options = {
      track: 'production',
      aab: '../build/app/outputs/bundle/release/app-release.aab',
      release_status: 'draft'
    }
    if metadata_path
      upload_options[:metadata_path] = metadata_path
      upload_options[:skip_upload_metadata] = true
      upload_options[:skip_upload_images] = true
      upload_options[:skip_upload_screenshots] = true
      upload_options[:skip_upload_changelogs] = false
    else
      upload_options[:skip_upload_metadata] = true
    end

    upload_to_play_store(upload_options)
  end

  desc "Update Google Play release notes only (no binary upload)"
  lane :update_release_notes do
    changelogs_dir = File.expand_path('../../changelogs', __dir__)
    metadata_path = ChangelogHelper.write_google_play_metadata(changelogs_dir)

    upload_to_play_store(
      track: 'internal',
      metadata_path: metadata_path,
      skip_upload_aab: true,
      skip_upload_apk: true,
      skip_upload_metadata: true,
      skip_upload_images: true,
      skip_upload_screenshots: true,
      skip_upload_changelogs: false,
      validate_only: false
    )
  end
end
''';

const changelogHelperTemplate = r'''
require 'tmpdir'
require 'fileutils'

module ChangelogHelper
  GOOGLE_PLAY_LOCALE_MAP = {
    'ar' => 'ar', 'bn' => 'bn-BD', 'cs' => 'cs-CZ', 'da' => 'da-DK', 'de' => 'de-DE',
    'el' => 'el-GR', 'en' => 'en-US', 'es' => 'es-ES', 'fa' => 'fa', 'fi' => 'fi-FI',
    'fr' => 'fr-FR', 'he' => 'he', 'hi' => 'hi-IN', 'hu' => 'hu-HU', 'id' => 'id',
    'it' => 'it-IT', 'ja' => 'ja-JP', 'ko' => 'ko-KR', 'nl' => 'nl-NL', 'no' => 'no-NO',
    'pl' => 'pl-PL', 'pt' => 'pt-BR', 'ro' => 'ro', 'ru' => 'ru-RU', 'sk' => 'sk',
    'sv' => 'sv-SE', 'th' => 'th', 'tl' => 'fil', 'tr' => 'tr-TR', 'uk' => 'uk',
    'vi' => 'vi', 'zh' => 'zh-CN',
  }.freeze

  APP_STORE_LOCALE_MAP = {
    'ar' => 'ar-SA', 'bn' => 'bn', 'cs' => 'cs', 'da' => 'da', 'de' => 'de-DE',
    'el' => 'el', 'en' => 'en-US', 'es' => 'es-ES', 'fa' => nil, 'fi' => 'fi',
    'fr' => 'fr-FR', 'he' => 'he', 'hi' => 'hi', 'hu' => 'hu', 'id' => 'id',
    'it' => 'it', 'ja' => 'ja', 'ko' => 'ko', 'nl' => 'nl-NL', 'no' => 'no',
    'pl' => 'pl', 'pt' => 'pt-BR', 'ro' => 'ro', 'ru' => 'ru', 'sk' => 'sk',
    'sv' => 'sv', 'th' => 'th', 'tl' => 'fil', 'tr' => 'tr', 'uk' => 'uk',
    'vi' => 'vi', 'zh' => 'zh-Hans',
  }.freeze

  def self.google_play_release_notes(changelogs_dir)
    notes = []
    GOOGLE_PLAY_LOCALE_MAP.each do |app_locale, play_locale|
      file = File.join(changelogs_dir, app_locale, 'release_notes.txt')
      next unless File.exist?(file)
      text = File.read(file).strip
      next if text.empty?
      notes << { language: play_locale, text: text[0, 500] }
    end
    notes
  end

  # Supply (upload_to_play_store) reads changelogs from a metadata directory
  # tree, not from a release_notes: parameter. It also derives the language
  # list from the top-level folder names under metadata_path, so those must
  # be the play_locale codes directly (no extra nesting). Writes
  # <tmp>/<play_locale>/changelogs/default.txt for every locale that has
  # release notes and returns the metadata root path, or nil if none do.
  def self.write_google_play_metadata(changelogs_dir)
    notes = google_play_release_notes(changelogs_dir)
    return nil if notes.empty?

    metadata_root = Dir.mktmpdir('torchinlane-supply-metadata')
    notes.each do |note|
      dir = File.join(metadata_root, note[:language], 'changelogs')
      FileUtils.mkdir_p(dir)
      File.write(File.join(dir, 'default.txt'), note[:text])
    end
    metadata_root
  end

  def self.testflight_changelog(changelogs_dir, locale = 'en')
    file = File.join(changelogs_dir, locale, 'release_notes.txt')
    return '' unless File.exist?(file)
    File.read(file).strip[0, 4000]
  end

  def self.app_store_release_notes(changelogs_dir)
    notes = {}
    APP_STORE_LOCALE_MAP.each do |app_locale, store_locale|
      next if store_locale.nil?
      file = File.join(changelogs_dir, app_locale, 'release_notes.txt')
      next unless File.exist?(file)
      text = File.read(file).strip
      next if text.empty?
      notes[store_locale] = text[0, 4000]
    end
    notes
  end
end
''';

const exportOptionsPlistTemplate = '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>teamID</key>
  <string>{{team_id}}</string>
  <key>uploadSymbols</key>
  <true/>
  <key>signingStyle</key>
  <string>automatic</string>
</dict>
</plist>
''';

const buildScriptTemplate = r'''#!/bin/bash
#
# Interactive build & deploy script generated by torchinlane.
# Run from the project root:  sh scripts/build.sh
#
set -o pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Resolve project root (parent of this script's dir) and cd into it.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$ROOT_DIR" || exit 1

SOURCE_LOCALE="{{source_locale}}"
CHANGELOGS_DIR="{{changelogs_dir}}"

printf "${YELLOW}--- {{app_name}} Build Script ---${NC}\n"

ask_yes_no() {
    while true; do
        read -p "$1 (y/n): " yn
        case $yn in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer y or n.";;
        esac
    done
}

# 1. Only-upload mode (skip building).
ONLY_UPLOAD=false
if ask_yes_no "Only upload existing builds (AAB/IPA)? Skips the build step"; then
    ONLY_UPLOAD=true
fi

# 2. Platforms.
BUILD_ANDROID=false
BUILD_IOS=false
if ask_yes_no "Android?"; then BUILD_ANDROID=true; fi
if ask_yes_no "iOS?"; then BUILD_IOS=true; fi
if [ "$BUILD_ANDROID" = false ] && [ "$BUILD_IOS" = false ]; then
    printf "${RED}No platform selected. Exiting.${NC}\n"
    exit 0
fi

# 3. Upload preference + target.
SHOULD_UPLOAD=false
DEPLOY_TARGET="none"
if ask_yes_no "Upload builds to the stores?"; then
    SHOULD_UPLOAD=true
    echo ""
    printf "${YELLOW}Select target:${NC}\n"
    echo "  1) Internal (TestFlight / Play Internal testing)"
    echo "  2) Production (App Store / Play Production)"
    while true; do
        read -p "Choice (1/2): " deploy_choice
        case $deploy_choice in
            1) DEPLOY_TARGET="internal"; break;;
            2) DEPLOY_TARGET="production"; break;;
            *) echo "Enter 1 or 2.";;
        esac
    done
    printf "${GREEN}Target: $DEPLOY_TARGET${NC}\n"
fi

# 4. Release notes (English source only). Previous note is cleared first.
SKIP_RELEASE_NOTES=1
if [ "$SHOULD_UPLOAD" = true ]; then
    echo ""
    printf "${YELLOW}Release notes (source locale: $SOURCE_LOCALE, English).${NC}\n"
    echo "Enter your notes. An empty note is fine. End with an empty line:"
    NOTE=""
    NL="$(printf '\n_')"; NL="${NL%_}"  # newline that survives command substitution
    while IFS= read -r line; do
        [ -z "$line" ] && break
        NOTE="${NOTE}${line}${NL}"
    done

    SOURCE_NOTE_FILE="$CHANGELOGS_DIR/$SOURCE_LOCALE/release_notes.txt"
    # Clear all existing locale notes so a stale note is never shipped.
    if command -v torchinlane >/dev/null 2>&1; then
        torchinlane changelog clear >/dev/null 2>&1
    fi
    mkdir -p "$CHANGELOGS_DIR/$SOURCE_LOCALE"
    printf '%s' "$NOTE" > "$SOURCE_NOTE_FILE"

    if [ -n "$(printf '%s' "$NOTE" | tr -d '[:space:]')" ]; then
        SKIP_RELEASE_NOTES=0
        # Translate to other locales when an API key is available.
        if [ -n "$ANTHROPIC_API_KEY" ] && command -v torchinlane >/dev/null 2>&1; then
            printf "${YELLOW}Translating release notes to other locales...${NC}\n"
            torchinlane changelog translate --overwrite || \
                printf "${YELLOW}WARNING: translation failed; shipping $SOURCE_LOCALE note only.${NC}\n"
        else
            printf "${YELLOW}No ANTHROPIC_API_KEY set; shipping $SOURCE_LOCALE note only.${NC}\n"
        fi
    else
        printf "${YELLOW}Empty release note; stores keep their current note.${NC}\n"
    fi
fi
export FASTLANE_SKIP_RELEASE_NOTES=$SKIP_RELEASE_NOTES

# 5. Version bump (build mode only; only-upload ships the existing binary).
if [ "$ONLY_UPLOAD" = false ]; then
    CURRENT_VERSION=$(grep '^version:' pubspec.yaml | sed 's/version://' | tr -d '[:space:]')
    # Split "x.y.z+n" into components.
    NAME_PART="${CURRENT_VERSION%%+*}"
    BUILD_PART="${CURRENT_VERSION#*+}"
    [ "$BUILD_PART" = "$CURRENT_VERSION" ] && BUILD_PART=0
    MAJOR="${NAME_PART%%.*}"
    REST="${NAME_PART#*.}"
    MINOR="${REST%%.*}"
    PATCH="${REST#*.}"
    NB=$((BUILD_PART + 1))

    echo ""
    printf "${YELLOW}Version bump — current: $CURRENT_VERSION${NC}\n"
    echo "  1) patch  -> $MAJOR.$MINOR.$((PATCH + 1))+$NB   (bug fix; z+1, build+1)"
    echo "  2) minor  -> $MAJOR.$((MINOR + 1)).0+$NB   (new feature; y+1, z=0, build+1)"
    echo "  3) major  -> $((MAJOR + 1)).0.0+$NB   (breaking change; x+1, y=z=0, build+1)"
    echo "  4) build  -> $MAJOR.$MINOR.$PATCH+$NB   (same version, build+1 — re-upload)"
    echo "  5) skip   -> $CURRENT_VERSION   (no change)"
    BUMP_KIND=""
    while true; do
        read -p "Choice (1-5): " bump_choice
        case $bump_choice in
            1) BUMP_KIND="patch"; break;;
            2) BUMP_KIND="minor"; break;;
            3) BUMP_KIND="major"; break;;
            4) BUMP_KIND="build"; break;;
            5) BUMP_KIND=""; break;;
            *) echo "Enter 1-5.";;
        esac
    done

    if [ -n "$BUMP_KIND" ]; then
        if command -v torchinlane >/dev/null 2>&1; then
            torchinlane bump "$BUMP_KIND" || { printf "${RED}ERROR: version bump failed.${NC}\n"; exit 1; }
        else
            printf "${RED}ERROR: torchinlane CLI not found; cannot bump.${NC}\n"; exit 1
        fi
    else
        printf "${YELLOW}Version unchanged.${NC}\n"
    fi
fi

# 6. Deep clean.
DEEP_CLEAN_ANDROID=false
DEEP_CLEAN_IOS=false
if [ "$ONLY_UPLOAD" = false ]; then
    if [ "$BUILD_ANDROID" = true ] && ask_yes_no "Deep clean Android? (.gradle cache)"; then
        DEEP_CLEAN_ANDROID=true
    fi
    if [ "$BUILD_IOS" = true ] && ask_yes_no "Deep clean iOS? (Pods + DerivedData)"; then
        DEEP_CLEAN_IOS=true
    fi
fi

if [ "$DEEP_CLEAN_ANDROID" = true ]; then
    printf "${YELLOW}Deep cleaning Android...${NC}\n"
    rm -rf android/.gradle android/app/build
fi
if [ "$DEEP_CLEAN_IOS" = true ]; then
    printf "${YELLOW}Deep cleaning iOS...${NC}\n"
    rm -rf ios/Pods ios/Podfile.lock
    rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-*
fi

# 7. Flutter clean + deps (build mode only).
if [ "$ONLY_UPLOAD" = false ]; then
    printf "${YELLOW}flutter clean...${NC}\n"
    flutter clean
    printf "${YELLOW}flutter pub get...${NC}\n"
    flutter pub get
    if [ "$BUILD_IOS" = true ]; then
        printf "${YELLOW}pod install...${NC}\n"
        (cd ios && pod install)
    fi
fi

VERSION=$(grep 'version: ' pubspec.yaml | sed 's/version: //' | tr -d '[:space:]')
printf "${GREEN}Version: $VERSION${NC}\n"

# Obfuscation symbol maps -> keep for crash de-obfuscation.
DEBUG_INFO_DIR="build/debug-info"
mkdir -p "$DEBUG_INFO_DIR"

# --- ANDROID ---
if [ "$BUILD_ANDROID" = true ]; then
    if [ "$ONLY_UPLOAD" = false ]; then
        printf "${YELLOW}Building Android AAB (obfuscated)...${NC}\n"
        if ! flutter build appbundle --obfuscate --split-debug-info="$DEBUG_INFO_DIR"; then
            printf "${RED}ERROR: Android build failed.${NC}\n"; exit 1
        fi
        printf "${GREEN}Android build OK.${NC}\n"
    fi
    if [ "$SHOULD_UPLOAD" = true ]; then
        if [ -f "build/app/outputs/bundle/release/app-release.aab" ]; then
            if [ "$DEPLOY_TARGET" = "production" ]; then
                LANE=deploy_production
            else
                LANE=deploy_internal
            fi
            printf "${YELLOW}Uploading Android AAB ($DEPLOY_TARGET) via fastlane $LANE...${NC}\n"
            if ! (cd android && fastlane $LANE); then
                printf "${RED}ERROR: Android upload failed.${NC}\n"; exit 1
            fi
            printf "${GREEN}Android upload OK.${NC}\n"
        else
            printf "${RED}ERROR: Android build file not found.${NC}\n"; exit 1
        fi
    fi
fi

# --- iOS ---
if [ "$BUILD_IOS" = true ]; then
    if [ "$ONLY_UPLOAD" = false ]; then
        printf "${YELLOW}Building iOS IPA (obfuscated, dSYMs on)...${NC}\n"
        if ! flutter build ipa --obfuscate --split-debug-info="$DEBUG_INFO_DIR" \
              --export-options-plist=ios/ExportOptions.plist; then
            printf "${RED}ERROR: iOS build failed.${NC}\n"; exit 1
        fi
        printf "${GREEN}iOS build OK.${NC}\n"
        DSYM_DIR="build/ios/archive/Runner.xcarchive/dSYMs"
        if [ -d "$DSYM_DIR" ] && ls "$DSYM_DIR"/*.dSYM >/dev/null 2>&1; then
            printf "${GREEN}dSYMs generated: $DSYM_DIR${NC}\n"
        else
            printf "${YELLOW}WARNING: no dSYMs found. Crashlytics symbolication may be incomplete.${NC}\n"
        fi
    fi
    if [ "$SHOULD_UPLOAD" = true ]; then
        IPA_PATH=$(ls build/ios/ipa/*.ipa 2>/dev/null | head -n 1)
        if [ -n "$IPA_PATH" ]; then
            if [ "$DEPLOY_TARGET" = "production" ]; then
                LANE=release
            else
                LANE=beta
            fi
            printf "${YELLOW}Uploading iOS IPA ($DEPLOY_TARGET) via fastlane $LANE...${NC}\n"
            if ! (cd ios && fastlane $LANE); then
                printf "${RED}ERROR: iOS upload failed.${NC}\n"; exit 1
            fi
            printf "${GREEN}iOS upload OK.${NC}\n"
        else
            printf "${RED}ERROR: iOS build file not found.${NC}\n"; exit 1
        fi
    fi
fi

# Clear notes after a successful upload so the next run starts clean.
if [ "$SHOULD_UPLOAD" = true ] && [ "$SKIP_RELEASE_NOTES" = "0" ] && command -v torchinlane >/dev/null 2>&1; then
    torchinlane changelog clear >/dev/null 2>&1
fi

printf "${GREEN}--- Done ---${NC}\n"
''';

/// Renders a template, replacing {{key}} placeholders and stripping/keeping
/// {{#flag}}...{{/flag}} blocks based on [flags].
String renderTemplate(String template, Map<String, String> values,
    {Map<String, bool> flags = const {}}) {
  var result = template;

  for (final entry in flags.entries) {
    final openTag = '{{#${entry.key}}}';
    final closeTag = '{{/${entry.key}}}';
    while (true) {
      final openIndex = result.indexOf(openTag);
      if (openIndex == -1) break;
      final closeIndex = result.indexOf(closeTag, openIndex);
      if (closeIndex == -1) break;
      final inner = result.substring(openIndex + openTag.length, closeIndex);
      final replacement = entry.value ? inner : '';
      result = result.replaceRange(
          openIndex, closeIndex + closeTag.length, replacement);
    }
  }

  values.forEach((key, value) {
    result = result.replaceAll('{{$key}}', value);
  });

  return result;
}
