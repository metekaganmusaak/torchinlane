/// Store and credential operations share the same project configuration.
const storeHelperTemplate = r'''
require 'json'
require 'yaml'
require 'pathname'

module StoreHelper
  ROOT = File.expand_path('..', __dir__)
  def self.config
    YAML.safe_load(File.read(File.join(ROOT, 'torchinlane.yaml')))
  end
  def self.path(value)
    File.expand_path(value, ROOT)
  end
  def self.api_key
    ios = config.fetch('ios')
    {
      key_id: ENV['ASC_KEY_ID'] || ios.fetch('asc_key_id'),
      issuer_id: (ENV['ASC_ISSUER_ID'] || ios['asc_issuer_id']).to_s.empty? ? nil : (ENV['ASC_ISSUER_ID'] || ios['asc_issuer_id']),
      key_filepath: path(ENV['ASC_KEY_PATH'] || ios.fetch('asc_key_path', 'ios/fastlane/api_key.p8')),
      duration: 1200, in_house: false
    }
  end
  def self.app_store_notes_allowed?
    app = Spaceship::ConnectAPI::App.find(config.fetch('ios').fetch('bundle_id'))
    raise 'App Store Connect app record not found' unless app
    !app.get_live_app_store_version(platform: 'IOS').nil?
  end
  def self.staging(platform)
    root = ENV.fetch('TORCHINLANE_STORE_STAGING')
    File.join(root, platform)
  end
  # Supply's default changelog uploader replaces the entire release_notes array.
  # Independent content uploads merge only supplied locales and preserve status,
  # version codes, other releases and omitted listing fields/image groups.
  def self.google_upload(metadata_path:, scope:, track_name:, version_code: nil)
    require 'supply'
    Supply.config = FastlaneCore::Configuration.create(Supply::Options.available_options, {
      json_key: ENV['GOOGLE_APPLICATION_CREDENTIALS'] || path(config.fetch('android').fetch('service_account_json')),
      package_name: config.fetch('android').fetch('package_name'),
      metadata_path: metadata_path, sync_image_upload: true
    })
    uploader = Supply::Uploader.new
    client = uploader.send(:client)
    client.begin_edit(package_name: Supply.config[:package_name])
    begin
      locales = Dir.children(metadata_path).select { |l| File.directory?(File.join(metadata_path, l)) && !l.start_with?('.') }
      locales.each do |locale|
        uploader.upload_metadata(locale, client.listing_for_language(locale)) if ['all', 'metadata'].include?(scope)
        if ['all', 'images'].include?(scope)
          uploader.upload_images(locale)
          uploader.upload_screenshots(locale)
        end
      end
      if ['all', 'notes'].include?(scope)
        supplied = {}
        locales.each do |locale|
          file = File.join(metadata_path, locale, 'changelogs', "#{version_code}.txt")
          next unless File.file?(file)
          text = File.read(file, encoding: 'UTF-8').strip
          supplied[locale] = text unless text.empty?
        end
        unless supplied.empty?
          raise 'Existing version code required for note updates' unless version_code
          track = client.tracks(track_name).first
          raise "Track not found: #{track_name}" unless track
          release = (track.releases || []).find { |r| (r.version_codes || []).map(&:to_s).include?(version_code.to_s) }
          raise "Version #{version_code} not found on #{track_name}" unless release
          merged = (release.release_notes || []).to_h { |note| [note.language, note.text] }.merge(supplied)
          release.release_notes = merged.map { |locale, text| ::AndroidPublisher::LocalizedText.new(language: locale, text: text) }
          client.update_track(track_name, track)
        end
      end
      client.commit_current_edit!
    ensure
      client.abort_current_edit if client.current_edit
    end
  end

end
''';

const iosStoreLanes = r'''
  desc "Install App Store certificates and profiles using an encrypted match repository"
  lane :sync_signing do
    api_key = app_store_connect_api_key(StoreHelper.api_key)
    setup_ci if ENV['CI'] == 'true'
    match(
      type: 'appstore', api_key: api_key,
      app_identifier: StoreHelper.config.fetch('ios').fetch('bundle_id'),
      team_id: StoreHelper.config.fetch('ios').fetch('team_id'),
      git_url: ENV.fetch('TORCHINLANE_SIGNING_GIT_URL'),
      readonly: ENV.fetch('TORCHINLANE_SIGNING_READONLY', '1') == '1'
    )
    ios = StoreHelper.config.fetch('ios')
    profile = ENV["sigh_#{ios.fetch('bundle_id')}_appstore_profile-name"]
    UI.user_error!('match did not install a provisioning profile for this app') if profile.to_s.empty?
    project_path = StoreHelper.path('ios/Runner.xcodeproj')
    pbx = File.join(project_path, 'project.pbxproj')
    FileUtils.cp(pbx, "#{pbx}.bak") if File.file?(pbx)
    update_code_signing_settings(
      use_automatic_signing: false, path: project_path,
      team_id: ios.fetch('team_id'), code_sign_identity: 'Apple Distribution',
      profile_name: profile, build_configurations: ['Release', 'Profile']
    )
    export = StoreHelper.path('ios/ExportOptions.plist')
    FileUtils.cp(export, "#{export}.bak")
    sh('/usr/bin/plutil', '-replace', 'signingStyle', '-string', 'manual', export)
    sh('/usr/bin/plutil', '-replace', 'provisioningProfiles', '-json', JSON.generate({ ios.fetch('bundle_id') => profile }), export)
  end

  desc "Upload localized store content without a binary or review submission"
  lane :store_push do
    api_key = app_store_connect_api_key(StoreHelper.api_key)
    root = StoreHelper.staging('ios')
    scope = ENV.fetch('TORCHINLANE_STORE_SCOPE', 'all')
    note_files = Dir.glob(File.join(root, 'metadata', '*', 'release_notes.txt'))
    if !note_files.empty? && !StoreHelper.app_store_notes_allowed?
      UI.important("Apple first release has no What's New field; retaining notes locally and skipping their upload")
      note_files.each { |file| File.delete(file) }
      next if scope == 'notes'
    end
    options = {
      api_key: api_key, skip_binary_upload: true,
      metadata_path: File.join(root, 'metadata'),
      screenshots_path: File.join(root, 'screenshots'),
      skip_metadata: scope == 'images',
      skip_screenshots: !['all', 'images'].include?(scope),
      overwrite_screenshots: ENV['TORCHINLANE_REPLACE_IMAGES'] == '1',
      submit_for_review: false, automatic_release: false, force: true
    }
    options[:app_version] = ENV['TORCHINLANE_APP_VERSION'] if ENV['TORCHINLANE_APP_VERSION']
    deliver(options)
  end

  desc "Download store texts into a temporary snapshot"
  lane :store_pull do
    api_key = app_store_connect_api_key(StoreHelper.api_key)
    app = Spaceship::ConnectAPI::App.find(StoreHelper.config.fetch('ios').fetch('bundle_id'))
    UI.user_error!('App not found') unless app
    version = if ENV['TORCHINLANE_APP_VERSION']
      app.get_app_store_versions(filter: { versionString: ENV['TORCHINLANE_APP_VERSION'], platform: 'IOS' }).first
    else
      app.get_edit_app_store_version(platform: 'IOS') || app.get_live_app_store_version(platform: 'IOS')
    end
    data = {}
    if version
      version.get_app_store_version_localizations.each do |localization|
        data[localization.locale] = {
          description: localization.description.to_s, keywords: localization.keywords.to_s,
          promotional_text: localization.promotional_text.to_s, support_url: localization.support_url.to_s,
          marketing_url: localization.marketing_url.to_s, release_notes: localization.whats_new.to_s
        }
      end
    end
    info = app.fetch_edit_app_info || app.fetch_live_app_info
    if info
      info.get_app_info_localizations.each do |localization|
        data[localization.locale] ||= {}
        data[localization.locale].merge!({ name: localization.name.to_s,
          subtitle: localization.subtitle.to_s, privacy_url: localization.privacy_policy_url.to_s })
      end
    end
    FileUtils.mkdir_p(StoreHelper.staging('ios'))
    File.write(File.join(StoreHelper.staging('ios'), 'snapshot.json'), JSON.pretty_generate(data))
  end

  desc "Verify API credentials and access to this app (read only)"
  lane :validate_credentials do
    api_key = app_store_connect_api_key(StoreHelper.api_key)
    app = Spaceship::ConnectAPI::App.find(StoreHelper.config.fetch('ios').fetch('bundle_id'))
    UI.user_error!('API key cannot access the configured app') unless app
    UI.success("App Store Connect access verified: #{app.bundle_id}")
  end
''';

const androidStoreLanes = r'''
  desc "Upload localized store content without a binary"
  lane :store_push do
    StoreHelper.google_upload(
      metadata_path: File.join(StoreHelper.staging('android'), 'metadata'),
      scope: ENV.fetch('TORCHINLANE_STORE_SCOPE', 'all'),
      track_name: ENV.fetch('TORCHINLANE_TRACK', 'internal'),
      version_code: ENV['TORCHINLANE_VERSION_CODE']
    )
  end

  desc "Download store texts into a temporary snapshot"
  lane :store_pull do
    require 'supply'
    Supply.config = FastlaneCore::Configuration.create(Supply::Options.available_options, {
      json_key: ENV['GOOGLE_APPLICATION_CREDENTIALS'] || StoreHelper.path(StoreHelper.config.fetch('android').fetch('service_account_json')),
      package_name: StoreHelper.config.fetch('android').fetch('package_name')
    })
    client = Supply::Client.make_from_config
    client.begin_edit(package_name: Supply.config[:package_name])
    begin
      data = {}
      client.listings.each do |listing|
        data[listing.language] = { title: listing.title.to_s, short_description: listing.short_description.to_s,
          full_description: listing.full_description.to_s, video: listing.video.to_s }
      end
      FileUtils.mkdir_p(StoreHelper.staging('android'))
      File.write(File.join(StoreHelper.staging('android'), 'snapshot.json'), JSON.pretty_generate(data))
    ensure
      client.abort_current_edit
    end
  end

  desc "Verify credentials and app access without committing an edit"
  lane :validate_credentials do
    require 'supply'
    options = FastlaneCore::Configuration.create(Supply::Options.available_options, {
      json_key: ENV['GOOGLE_APPLICATION_CREDENTIALS'] || StoreHelper.path(StoreHelper.config.fetch('android').fetch('service_account_json')),
      package_name: StoreHelper.config.fetch('android').fetch('package_name')
    })
    Supply.config = options
    client = Supply::Client.make_from_config
    client.begin_edit(package_name: options[:package_name])
    begin
      client.listings
      UI.success('Google Play app access verified')
    ensure
      client.abort_current_edit
    end
  end
''';

const newChangelogHelperTemplate = r'''
require 'tmpdir'
require 'fileutils'
require 'json'
require_relative 'StoreHelper'

module ChangelogHelper
  REGISTRY = JSON.parse(File.read(File.join(__dir__, 'locales.json')))
  GOOGLE_PLAY_LOCALE_MAP = REGISTRY.fetch('android').freeze
  APP_STORE_LOCALE_MAP = REGISTRY.fetch('ios').freeze

  def self.read_notes(changelogs_dir, platform, limit)
    notes = {}
    locales = File.directory?(changelogs_dir) ? Dir.children(changelogs_dir).sort : []
    locales.each do |locale|
      text = note_text(changelogs_dir, locale)
      next if text.empty?
      store_locale = REGISTRY.fetch(platform)[locale]
      unless store_locale
        warn "Skipping unsupported #{platform} release notes locale: #{locale}"
        next
      end
      raise "#{platform}/#{locale}: release notes exceed #{limit} characters" if text.length > limit
      raise "Multiple source locales map to #{store_locale}; remove the duplicate" if notes.key?(store_locale)
      notes[store_locale] = text
    end
    if ENV['TORCHINLANE_USE_STORE_NOTES'] == '1'
      Dir.glob(StoreHelper.path("store/#{platform}/*.json")).sort.each do |file|
        locale = File.basename(file, '.json')
        raise "Invalid native store locale #{locale}" unless REGISTRY.fetch(platform)[locale] == locale
        data = JSON.parse(File.read(file, encoding: 'UTF-8'))
        text = data.fetch('release_notes', '').strip
        next if text.empty?
        raise "#{platform}/#{locale}: release notes exceed #{limit} characters" if text.length > limit
        notes[locale] = text
      end
    end
    notes
  end

  def self.pubspec_version
    file = StoreHelper.path('pubspec.yaml')
    File.file?(file) ? File.read(file)[/^version:\s*(\S+)/, 1].to_s : ''
  end

  # <locale>/<pubspec version>.md: lines under the "## <version>" heading up to
  # the next heading or "---" (whole file minus headings if there is none).
  # Falls back to <locale>/release_notes.txt.
  def self.note_text(changelogs_dir, locale)
    version = pubspec_version
    md = File.join(changelogs_dir, locale, "#{version}.md")
    unless !version.empty? && File.file?(md)
      txt = File.join(changelogs_dir, locale, 'release_notes.txt')
      return File.file?(txt) ? File.read(txt, encoding: 'UTF-8').strip : ''
    end
    lines = File.read(md, encoding: 'UTF-8').lines.map(&:rstrip)
    boundary = ->(l) { l.start_with?('#') || l.strip == '---' }
    start = lines.index { |l| l.start_with?('#') && l.sub(/^#+\s*/, '').strip == version }
    body = start ? lines[(start + 1)..].take_while { |l| !boundary.(l) } : lines.reject(&boundary)
    body.join("\n").strip
  end

  def self.google_play_release_notes(dir)
    read_notes(dir, 'android', 500).map { |locale, text| { language: locale, text: text } }
  end

  def self.write_google_play_metadata(dir, version_code = nil)
    notes = google_play_release_notes(dir)
    return nil if notes.empty?
    root = Dir.mktmpdir('torchinlane-supply-metadata')
    notes.each do |note|
      target = File.join(root, note[:language], 'changelogs')
      FileUtils.mkdir_p(target)
      File.write(File.join(target, "#{version_code || 'default'}.txt"), note[:text])
    end
    root
  end

  def self.testflight_changelog(dir, locale = 'en')
    if ENV['TORCHINLANE_USE_STORE_NOTES'] == '1'
      return app_store_release_notes(dir)[REGISTRY.fetch('ios')[locale]].to_s
    end
    text = note_text(dir, locale)
    raise 'TestFlight notes exceed 4000 characters' if text.length > 4000
    text
  end

  def self.app_store_release_notes(dir)
    read_notes(dir, 'ios', 4000)
  end
end
''';
