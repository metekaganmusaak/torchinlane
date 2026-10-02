import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:torchinlane/src/project/flutter_project.dart';
import 'test_project.dart';

void main() {
  late FlutterProject project;
  setUp(() => project = createTestProject());
  tearDown(() => project.root.deleteSync(recursive: true));
  test('generated Fastfiles/helpers and build wrapper have valid syntax',
      () async {
    for (final path in [
      'ios/fastlane/Fastfile',
      'ios/fastlane/Appfile',
      'android/fastlane/Fastfile',
      'android/fastlane/Appfile',
      'fastlane/ChangelogHelper.rb',
      'fastlane/StoreHelper.rb'
    ]) {
      final res =
          await Process.run('ruby', ['-c', '${project.root.path}/$path']);
      expect(res.exitCode, 0, reason: '$path: ${res.stderr}');
    }
    final shell = await Process.run(
        'sh', ['-n', '${project.root.path}/scripts/build.sh']);
    expect(shell.exitCode, 0, reason: shell.stderr.toString());
  }, skip: Platform.isWindows ? 'Requires Ruby and POSIX sh' : false);
  test(
      'Ruby registry skips unsupported Apple locales, uses correct paths and fails on long notes',
      () async {
    void note(String locale, String text) {
      final f =
          File('${project.root.path}/custom-notes/$locale/release_notes.txt');
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(text);
    }

    note('bn', 'Bangla');
    note('tl', 'Filipino');
    note('fa', 'Persian');
    note('en-GB', 'British');
    final result = await Process.run('ruby', [
      '-e',
      r'''require ARGV[0]; puts JSON.generate(ChangelogHelper.app_store_release_notes(ARGV[1]))''',
      '${project.root.path}/fastlane/ChangelogHelper.rb',
      '${project.root.path}/custom-notes'
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(jsonDecode(result.stdout as String),
        {'bn-BD': 'Bangla', 'en-GB': 'British'});
    note('en', 'x' * 501);
    final long = await Process.run('ruby', [
      '-e',
      r'''require ARGV[0]; ChangelogHelper.google_play_release_notes(ARGV[1])''',
      '${project.root.path}/fastlane/ChangelogHelper.rb',
      '${project.root.path}/custom-notes'
    ]);
    expect(long.exitCode, isNot(0));
    expect(long.stderr, contains('exceed 500'));
  }, skip: Platform.isWindows ? 'Requires Ruby' : false);
  test(
      'iOS release uploads notes as metadata; TestFlight waits for localized build info',
      () async {
    final note = File('${project.root.path}/changelogs/en/release_notes.txt')
      ..writeAsStringSync('Fixed a bug');
    final script = File('${project.root.path}/test_lanes.rb')
      ..writeAsStringSync(r'''
require 'json'
$lanes = {}
def default_platform(*); end
def platform(*); yield; end
def desc(*); end
def lane(name, &block); $lanes[name] = block; end
def private_lane(name, &block); $lanes[name] = block; end
def app_store_connect_api_key(options); options; end
def deliver(options); puts JSON.generate({ skip_metadata: options[:skip_metadata], release_notes: options[:release_notes] }); end
def upload_to_testflight(options); puts JSON.generate({ localized: options[:localized_build_info], wait: !options[:skip_waiting_for_build_processing] }); end
load ARGV[0]
def StoreHelper.app_store_notes_allowed?; ENV['TORCHINLANE_TEST_FIRST'] != '1'; end
module UI; def self.important(*); end; end
$lanes[:release].call
$lanes[:beta].call
''');
    final result = await Process.run(
        'ruby', [script.path, '${project.root.path}/ios/fastlane/Fastfile']);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final lines =
        (result.stdout as String).trim().split('\n').map(jsonDecode).toList();
    expect(lines[0]['skip_metadata'], false);
    expect(lines[0]['release_notes'], {'en-US': 'Fixed a bug'});
    expect(lines[1]['localized']['en-US']['whats_new'], 'Fixed a bug');
    expect(lines[1]['wait'], true);
    expect(note.readAsStringSync(), 'Fixed a bug');
    final first = await Process.run(
        'ruby', [script.path, '${project.root.path}/ios/fastlane/Fastfile'],
        environment: {'TORCHINLANE_TEST_FIRST': '1'});
    expect(first.exitCode, 0, reason: first.stderr.toString());
    final firstLines =
        (first.stdout as String).trim().split('\n').map(jsonDecode).toList();
    expect(firstLines.first['skip_metadata'], true);
    expect(firstLines.first['release_notes'], isNull);
    expect(firstLines.last['localized']['en-US']['whats_new'], 'Fixed a bug');
  }, skip: Platform.isWindows ? 'Requires Ruby' : false);
  test('store JSON notes override legacy notes only when explicitly enabled',
      () async {
    File('${project.root.path}/changelogs/en/release_notes.txt')
        .writeAsStringSync('Legacy');
    final file = File('${project.root.path}/store/ios/en-US.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('{"release_notes":"Studio notes"}');
    final script =
        r'''require ARGV[0]; puts JSON.generate(ChangelogHelper.app_store_release_notes(ARGV[1])); puts ChangelogHelper.testflight_changelog(ARGV[1], 'en')''';
    final result = await Process.run('ruby', [
      '-e',
      script,
      '${project.root.path}/fastlane/ChangelogHelper.rb',
      '${project.root.path}/changelogs'
    ], environment: {
      'TORCHINLANE_USE_STORE_NOTES': '1'
    });
    expect(result.exitCode, 0, reason: result.stderr.toString());
    final lines = (result.stdout as String).trim().split('\n');
    expect(jsonDecode(lines.first), {'en-US': 'Studio notes'});
    expect(lines.last, 'Studio notes');
  }, skip: Platform.isWindows ? 'Requires Ruby' : false);
  test(
      'Google note-only helper merges omitted locales and preserves all release properties',
      () async {
    final metadata = Directory('${project.root.path}/staging/en-US/changelogs')
      ..createSync(recursive: true);
    File('${metadata.path}/42.txt').writeAsStringSync('New English');
    final mockDir = Directory('${project.root.path}/mock')..createSync();
    File('${mockDir.path}/supply.rb').writeAsStringSync(r'''
require 'ostruct'
module AndroidPublisher
  class LocalizedText < OpenStruct; end
end
module FastlaneCore
  class Configuration
    def self.create(_, values); values; end
  end
end
module Supply
  class << self; attr_accessor :config; end
  module Options; def self.available_options; []; end; end

  class FakeClient
    attr_accessor :current_edit
    def begin_edit(**); @current_edit = true; end
    def tracks(name)
      @release = OpenStruct.new(version_codes: ['42'], status: 'completed', user_fraction: nil,
        release_notes: [AndroidPublisher::LocalizedText.new(language: 'en-US', text: 'Old'), AndroidPublisher::LocalizedText.new(language: 'tr-TR', text: 'Türkçe')])
      @other = OpenStruct.new(version_codes: ['41'], status: 'completed', release_notes: [])
      [OpenStruct.new(track: name, releases: [@release, @other])]
    end
    def update_track(name, track)
      raise 'lost releases' unless track.releases.length == 2
      raise 'changed status' unless @release.status == 'completed'
      raise 'changed versions' unless @release.version_codes == ['42']
      puts JSON.generate(@release.release_notes.to_h { |n| [n.language, n.text] })
    end
    def commit_current_edit!; @current_edit = nil; end
    def abort_current_edit; @current_edit = nil; end
  end
  class Uploader
    def client; @client ||= FakeClient.new; end
  end
end
''');
    final result = await Process.run('ruby', [
      '-I',
      mockDir.path,
      '-e',
      r'''require ARGV[0]; StoreHelper.google_upload(metadata_path: ARGV[1], scope: 'notes', track_name: 'production', version_code: '42')''',
      '${project.root.path}/fastlane/StoreHelper.rb',
      '${project.root.path}/staging'
    ]);
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(jsonDecode(result.stdout as String),
        {'en-US': 'New English', 'tr-TR': 'Türkçe'});
  }, skip: Platform.isWindows ? 'Requires Ruby' : false);
}
