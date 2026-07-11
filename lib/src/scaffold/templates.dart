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
      skip_screenshots: true
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
    notes = ChangelogHelper.google_play_release_notes(changelogs_dir)
    skip_release_notes = ENV['FASTLANE_SKIP_RELEASE_NOTES'] == '1'
    upload_options = {
      track: 'internal',
      aab: '../build/app/outputs/bundle/release/app-release.aab',
      release_status: 'draft'
    }

    upload_options[:release_notes] = notes if !skip_release_notes && !notes.empty?

    upload_to_play_store(upload_options)
  end

  desc "Upload AAB to Google Play Production"
  lane :deploy_production do
    changelogs_dir = File.expand_path('../../changelogs', __dir__)
    notes = ChangelogHelper.google_play_release_notes(changelogs_dir)
    skip_release_notes = ENV['FASTLANE_SKIP_RELEASE_NOTES'] == '1'
    upload_options = {
      track: 'production',
      aab: '../build/app/outputs/bundle/release/app-release.aab',
      release_status: 'draft'
    }

    upload_options[:release_notes] = notes if !skip_release_notes && !notes.empty?

    upload_to_play_store(upload_options)
  end

  desc "Update Google Play release notes only (no binary upload)"
  lane :update_release_notes do
    changelogs_dir = File.expand_path('../../changelogs', __dir__)
    notes = ChangelogHelper.google_play_release_notes(changelogs_dir)

    upload_to_play_store(
      track: 'internal',
      release_notes: notes,
      skip_upload_aab: true,
      skip_upload_apk: true,
      skip_upload_metadata: true,
      skip_upload_images: true,
      skip_upload_screenshots: true,
      validate_only: false
    )
  end
end
''';

const changelogHelperTemplate = r'''
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

/// Renders a template, replacing {{key}} placeholders and stripping/keeping
/// {{#flag}}...{{/flag}} blocks based on [flags].
String renderTemplate(String template, Map<String, String> values, {Map<String, bool> flags = const {}}) {
  var result = template;

  for (final entry in flags.entries) {
    final openTag = '{{#${entry.key}}}';
    final closeTag = '{{/${entry.key}}}';
    final openIndex = result.indexOf(openTag);
    if (openIndex == -1) continue;
    final closeIndex = result.indexOf(closeTag, openIndex);
    if (closeIndex == -1) continue;
    final inner = result.substring(openIndex + openTag.length, closeIndex);
    final replacement = entry.value ? inner : '';
    result = result.replaceRange(openIndex, closeIndex + closeTag.length, replacement);
  }

  values.forEach((key, value) {
    result = result.replaceAll('{{$key}}', value);
  });

  return result;
}
