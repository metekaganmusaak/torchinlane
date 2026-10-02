import 'dart:io';
import 'package:path/path.dart' as p;
import '../config/torchinlane_config.dart';
import 'package:args/command_runner.dart';
import '../changelog/locale_maps.dart';
import '../project/flutter_project.dart';
import '../setup/credentials.dart';
import '../store/service.dart';

class CredentialsCommand extends Command<int> {
  CredentialsCommand() {
    addSubcommand(_Import());
    addSubcommand(_Verify());
    addSubcommand(_Google());
  }
  @override
  String get name => 'credentials';
  @override
  String get description =>
      'Import/reuse credentials, verify app access, bootstrap Google Cloud.';
}

class _Import extends Command<int> {
  _Import() {
    argParser
      ..addOption('platform', allowed: ['ios', 'android'], mandatory: true)
      ..addOption('file', mandatory: true)
      ..addOption('profile', help: 'Reusable local credential profile name.');
  }
  @override
  String get name => 'import';
  @override
  String get description =>
      'Import .p8 or Google JSON; protect file permissions and gitignore.';
  @override
  Future<int> run() async {
    final project = FlutterProject.findRoot();
    if (project == null) throw StateError('Not inside a Flutter project');
    final target = Credentials(project).import(
        argResults!['platform'] as String,
        File(argResults!['file'] as String).readAsStringSync(),
        profile: argResults!['profile'] as String?);
    stdout.writeln(
        'Credential imported: ${target.path}. Run credentials verify to check app access.');
    return 0;
  }
}

class _Verify extends Command<int> {
  _Verify() {
    argParser.addOption('platform', defaultsTo: 'ios,android');
  }
  @override
  String get name => 'verify';
  @override
  String get description =>
      'Authenticate and check configured app access without a release upload.';
  @override
  Future<int> run() async {
    final project = FlutterProject.findRoot();
    if (project == null) throw StateError('Not inside a Flutter project');
    return StoreService(project)
        .verify(parsePlatforms(argResults!['platform'] as String));
  }
}

class _Google extends Command<int> {
  _Google() {
    argParser
      ..addOption('project-id', mandatory: true)
      ..addOption('account', defaultsTo: 'torchinlane')
      ..addOption('repository',
          help:
              'GitHub owner/repo. Creates WIF for this repository instead of a private key.')
      ..addFlag('create-key',
          negatable: false,
          help:
              'Create a service account JSON key (unless organization policy forbids it).')
      ..addFlag('dry-run', negatable: false);
  }
  @override
  String get name => 'bootstrap-google';
  @override
  String get description =>
      'Use an existing gcloud login to enable Play API and create a service account/WIF.';
  @override
  Future<int> run() async {
    final args = argResults!,
        id = args['project-id'] as String,
        account = args['account'] as String;
    final repo = args['repository'] as String?;
    if (!RegExp(r'^[a-z][a-z0-9-]{4,61}[a-z0-9]$').hasMatch(id) ||
        !RegExp(r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$').hasMatch(account)) {
      throw ArgumentError('Invalid project/account ID');
    }
    if (repo != null &&
        !RegExp(r'^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$').hasMatch(repo)) {
      throw ArgumentError('Use repository owner/name');
    }
    if (repo != null && args['create-key'] == true) {
      throw ArgumentError('Choose WIF or --create-key, not both');
    }
    if (args['create-key'] == true) {
      final project = FlutterProject.findRoot();
      if (project == null || !project.torchinlaneConfigFile.existsSync()) {
        throw StateError(
            'Initialize the Flutter project before creating/importing a key.');
      }
      final config = TorchinlaneConfig.load(project.torchinlaneConfigFile);
      if (File(p.absolute(project.root.path, config.android.serviceAccountJson))
          .existsSync()) {
        throw StateError(
            'A Google credential already exists. Reuse it or choose a new configured path before creating another key.');
      }
    }
    final email = '$account@$id.iam.gserviceaccount.com',
        dry = args['dry-run'] as bool;
    Future<ProcessResult?> run(List<String> command,
        {bool probe = false}) async {
      if (!probe) stdout.writeln('gcloud ${command.join(' ')}');
      if (dry) return null;
      final result = await Process.run('gcloud', command);
      if (result.exitCode != 0 && !probe) {
        throw StateError('gcloud failed: ${result.stderr}');
      }
      return result;
    }

    await run([
      'services',
      'enable',
      'androidpublisher.googleapis.com',
      'iam.googleapis.com',
      'iamcredentials.googleapis.com',
      '--project=$id',
      '--quiet'
    ]);
    final existing = await run(
        ['iam', 'service-accounts', 'describe', email, '--project=$id'],
        probe: true);
    if (dry || existing?.exitCode != 0) {
      await run([
        'iam',
        'service-accounts',
        'create',
        account,
        '--project=$id',
        '--quiet'
      ]);
    }
    if (repo != null) {
      final result = await run(
          ['projects', 'describe', id, '--format=value(projectNumber)'],
          probe: true);
      final number = dry ? 'PROJECT_NUMBER' : result!.stdout.toString().trim();
      const pool = 'torchinlane-github';
      var hash = 2166136261;
      for (final byte in repo.codeUnits) {
        hash = ((hash ^ byte) * 16777619) & 0xffffffff;
      }
      final provider = 'github-${hash.toRadixString(16)}';
      final poolExists = await run([
        'iam',
        'workload-identity-pools',
        'describe',
        pool,
        '--location=global',
        '--project=$id'
      ], probe: true);
      if (dry || poolExists?.exitCode != 0) {
        await run([
          'iam',
          'workload-identity-pools',
          'create',
          pool,
          '--location=global',
          '--project=$id',
          '--quiet'
        ]);
      }
      final providerExists = await run([
        'iam',
        'workload-identity-pools',
        'providers',
        'describe',
        provider,
        '--workload-identity-pool=$pool',
        '--location=global',
        '--project=$id'
      ], probe: true);
      if (dry || providerExists?.exitCode != 0) {
        await run([
          'iam',
          'workload-identity-pools',
          'providers',
          'create-oidc',
          provider,
          '--workload-identity-pool=$pool',
          '--location=global',
          '--project=$id',
          '--issuer-uri=https://token.actions.githubusercontent.com',
          '--attribute-mapping=google.subject=assertion.sub,attribute.repository=assertion.repository',
          "--attribute-condition=assertion.repository=='$repo'",
          '--quiet'
        ]);
      }
      await run([
        'iam',
        'service-accounts',
        'add-iam-policy-binding',
        email,
        '--project=$id',
        '--role=roles/iam.workloadIdentityUser',
        '--member=principalSet://iam.googleapis.com/projects/$number/locations/global/workloadIdentityPools/$pool/attribute.repository/$repo',
        '--quiet'
      ]);
      stdout.writeln(
          'WIF provider: projects/$number/locations/global/workloadIdentityPools/$pool/providers/$provider');
    }
    if (args['create-key'] == true) {
      final project = FlutterProject.findRoot();
      if (project == null) {
        throw StateError('Run inside a Flutter project to import a key');
      }
      if (!dry) {
        final temp =
            Directory.systemTemp.createTempSync('torchinlane-credential-');
        try {
          final file = File('${temp.path}/google.json');
          await run([
            'iam',
            'service-accounts',
            'keys',
            'create',
            file.path,
            '--iam-account=$email',
            '--project=$id',
            '--quiet'
          ]);
          Credentials(project).import('android', file.readAsStringSync());
        } finally {
          temp.deleteSync(recursive: true);
        }
      } else {
        stdout.writeln(
            'Would create and import a JSON key into the configured credential path.');
      }
    }
    stdout.writeln('Service account: $email');
    stdout.writeln(
        'One-time Play Console step: Users and permissions → invite this email and grant app/release access.');
    stdout.writeln('https://play.google.com/console');
    return 0;
  }
}
