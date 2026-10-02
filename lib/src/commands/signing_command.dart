import 'dart:io';
import 'package:args/command_runner.dart';
import '../project/flutter_project.dart';
import '../store/service.dart';
import '../setup/android_signing.dart';

class SigningCommand extends Command<int> {
  SigningCommand() {
    addSubcommand(_Sync());
    addSubcommand(_Android());
  }
  @override
  String get name => 'signing';
  @override
  String get description =>
      'Install or create iOS signing certificates/profiles with fastlane match.';
}

class _Sync extends Command<int> {
  _Sync() {
    argParser
      ..addOption('git-url',
          mandatory: true,
          help:
              'Private certificates repository (credentials via MATCH_GIT_BASIC_AUTHORIZATION or SSH).')
      ..addFlag('write',
          negatable: false,
          help: 'Create/renew certificates and profiles; default is read-only.')
      ..addFlag('dry-run', negatable: false);
  }
  @override
  String get name => 'sync';
  @override
  String get description =>
      'Synchronize App Store signing identities; MATCH_PASSWORD encrypts the repository.';
  @override
  Future<int> run() async {
    final project = FlutterProject.findRoot();
    if (project == null) throw StateError('Run inside a Flutter project');
    if (argResults!['dry-run'] == true) {
      stdout.writeln(
          'Would sync iOS app-store signing; read-only=${argResults!['write'] != true}');
      return 0;
    }
    if (!Platform.isMacOS) {
      throw StateError('Installing iOS signing identities requires macOS');
    }
    return StoreService(project).lane('ios', 'sync_signing', env: {
      'TORCHINLANE_SIGNING_GIT_URL': argResults!['git-url'] as String,
      'TORCHINLANE_SIGNING_READONLY': argResults!['write'] == true ? '0' : '1'
    });
  }
}

class _Android extends Command<int> {
  _Android() {
    argParser
      ..addOption('keystore', mandatory: true)
      ..addOption('alias', mandatory: true)
      ..addOption('store-password-env', defaultsTo: 'KEYSTORE_PASSWORD')
      ..addOption('key-password-env', defaultsTo: 'KEY_PASSWORD')
      ..addFlag('dry-run', negatable: false);
  }
  @override
  String get name => 'android';
  @override
  String get description =>
      'Import an existing upload keystore and configure stock Flutter Gradle release signing.';
  @override
  Future<int> run() async {
    final project = FlutterProject.findRoot();
    if (project == null) throw StateError('Run inside a Flutter project');
    final args = argResults!;
    setupAndroidSigning(project,
        keystore: File(args['keystore'] as String),
        alias: args['alias'] as String,
        storePassword:
            Platform.environment[args['store-password-env'] as String] ?? '',
        keyPassword:
            Platform.environment[args['key-password-env'] as String] ?? '',
        dryRun: args['dry-run'] == true);
    stdout.writeln(args['dry-run'] == true
        ? 'Android signing configuration validated.'
        : 'Android signing configured; credential files are gitignored.');
    return 0;
  }
}
