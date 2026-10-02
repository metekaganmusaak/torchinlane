import 'dart:io';
import 'package:args/command_runner.dart';
import '../changelog/locale_maps.dart';
import '../project/flutter_project.dart';
import '../setup/ci.dart';

class CiCommand extends Command<int> {
  CiCommand() {
    addSubcommand(_Init());
  }
  @override
  String get name => 'ci';
  @override
  String get description =>
      'Generate a GitHub Actions workflow for unattended Flutter releases.';
}

class _Init extends Command<int> {
  _Init() {
    argParser
      ..addOption('platform', defaultsTo: 'ios,android')
      ..addOption('flutter-version',
          defaultsTo: 'stable',
          help:
              'Flutter Git tag/branch; use a version tag for reproducible builds.')
      ..addOption('wif-provider',
          help: 'Google Workload Identity Provider resource ID.')
      ..addOption('service-account',
          help: 'Google service account email for WIF.')
      ..addOption('signing-git-url',
          help: 'Existing fastlane match certificates repository for iOS.')
      ..addFlag('force', negatable: false)
      ..addFlag('dry-run', negatable: false);
  }
  @override
  String get name => 'init';
  @override
  String get description =>
      'Create .github/workflows/torchinlane.yml; preserve existing workflows by default.';
  @override
  Future<int> run() async {
    final project = FlutterProject.findRoot();
    if (project == null) throw StateError('Run inside a Flutter project');
    final value = renderCi(
        platforms: parsePlatforms(argResults!['platform'] as String),
        flutterVersion: argResults!['flutter-version'] as String,
        wifProvider: argResults!['wif-provider'] as String?,
        serviceAccount: argResults!['service-account'] as String?,
        signingGitUrl: argResults!['signing-git-url'] as String?);
    if (argResults!['dry-run'] == true) {
      stdout.write(value);
      return 0;
    }
    final file = File('${project.root.path}/.github/workflows/torchinlane.yml');
    if (file.existsSync() && argResults!['force'] != true) {
      throw StateError('Workflow exists; use --force to replace with a backup');
    }
    if (file.existsSync()) file.copySync('${file.path}.bak');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(value);
    stdout.writeln(
        'Created ${file.path}. Configure signing/credential secrets described in doc/automation.md.');
    return 0;
  }
}
