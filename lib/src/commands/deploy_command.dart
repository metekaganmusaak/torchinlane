import 'dart:io';

import 'package:args/command_runner.dart';

import '../config/torchinlane_config.dart';
import '../project/flutter_project.dart';
import '../shell/logger.dart';
import '../shell/process_runner.dart';

class DeployCommand extends Command<int> {
  DeployCommand({Logger logger = const Logger()}) : _logger = logger {
    argParser
      ..addOption('platform', help: 'ios, android, or ios,android', defaultsTo: 'ios,android')
      ..addOption('target', allowed: ['internal', 'production'], defaultsTo: 'internal')
      ..addFlag('upload-only', help: 'Skip build, upload existing AAB/IPA.', negatable: false)
      ..addFlag('skip-clean', help: 'Skip flutter clean + pub get.', negatable: false)
      ..addFlag('deep-clean', help: 'Also clear Pods/.gradle caches.', negatable: false)
      ..addFlag('skip-release-notes', help: 'Do not attach changelog to upload.', negatable: false)
      ..addFlag('dry-run', help: 'Print commands without executing them.', negatable: false);
  }

  final Logger _logger;

  @override
  String get name => 'deploy';

  @override
  String get description => 'Build and upload to TestFlight/App Store or Play Store.';

  @override
  Future<int> run() async {
    final project = FlutterProject.findRoot();
    if (project == null) {
      _logger.error('Not inside a Flutter project.');
      return 1;
    }
    if (!project.torchinlaneConfigFile.existsSync()) {
      _logger.error('No torchinlane.yaml found. Run `torchinlane init` first.');
      return 1;
    }

    final config = TorchinlaneConfig.load(project.torchinlaneConfigFile);
    final platforms = (argResults!['platform'] as String).split(',').map((p) => p.trim()).toSet();
    final target = argResults!['target'] as String;
    final uploadOnly = argResults!['upload-only'] as bool;
    final skipClean = argResults!['skip-clean'] as bool;
    final deepClean = argResults!['deep-clean'] as bool;
    final skipReleaseNotes = argResults!['skip-release-notes'] as bool;
    final dryRun = argResults!['dry-run'] as bool;

    final buildIos = platforms.contains('ios');
    final buildAndroid = platforms.contains('android');
    if (!buildIos && !buildAndroid) {
      _logger.error('--platform must include ios and/or android.');
      return 1;
    }

    final root = project.root.path;
    final env = skipReleaseNotes ? {'FASTLANE_SKIP_RELEASE_NOTES': '1'} : <String, String>{};

    final sharedSteps = <_Step>[];
    if (!uploadOnly && !skipClean) {
      sharedSteps.add(_Step('flutter', ['clean'], cwd: root));
      sharedSteps.add(_Step('flutter', ['pub', 'get'], cwd: root));
    }

    final androidSteps = <_Step>[];
    if (buildAndroid) {
      if (!uploadOnly) {
        if (deepClean) {
          androidSteps.add(_Step('rm', ['-rf', '$root/android/.gradle', '$root/android/app/build']));
        }
        final args = ['build', 'appbundle'];
        if (config.obfuscate) {
          args.addAll(['--obfuscate', '--split-debug-info=${config.splitDebugInfo}']);
        }
        androidSteps.add(_Step('flutter', args, cwd: root));
      }
      final lane = target == 'production' ? 'deploy_production' : 'deploy_internal';
      androidSteps.add(_Step('fastlane', [lane], cwd: '$root/android', env: env));
    }

    final iosSteps = <_Step>[];
    if (buildIos) {
      if (!uploadOnly) {
        if (deepClean) {
          iosSteps.add(_Step('rm', ['-rf', '$root/ios/Pods', '$root/ios/Podfile.lock']));
        }
        iosSteps.add(_Step('pod', ['install'], cwd: '$root/ios'));
        final args = ['build', 'ipa', '--export-options-plist=ios/ExportOptions.plist'];
        if (config.obfuscate) {
          args.addAll(['--obfuscate', '--split-debug-info=${config.splitDebugInfo}']);
        }
        iosSteps.add(_Step('flutter', args, cwd: root));
      }
      final lane = target == 'production' ? 'release' : 'beta';
      iosSteps.add(_Step('fastlane', [lane], cwd: '$root/ios', env: env));
    }

    if (sharedSteps.isNotEmpty) {
      final sharedOk = await _runSteps(sharedSteps, dryRun: dryRun);
      if (!sharedOk) {
        _logger.error('\nShared setup failed — aborting before platform builds.');
        return 1;
      }
    }

    final failedPlatforms = <String>[];
    if (buildAndroid) {
      _logger.info('\n--- Android ---');
      if (!await _runSteps(androidSteps, dryRun: dryRun)) failedPlatforms.add('android');
    }
    if (buildIos) {
      _logger.info('\n--- iOS ---');
      if (!await _runSteps(iosSteps, dryRun: dryRun)) failedPlatforms.add('ios');
    }

    if (failedPlatforms.isNotEmpty) {
      _logger.error('\nDeploy failed for: ${failedPlatforms.join(', ')}.');
      return 1;
    }

    if (!dryRun) _logger.success('\nDeploy complete.');
    return 0;
  }

  Future<bool> _runSteps(List<_Step> steps, {required bool dryRun}) async {
    for (final step in steps) {
      _logger.info('\$ ${step.executable} ${step.arguments.join(' ')}${step.cwd != null ? '  (in ${step.cwd})' : ''}');
      if (dryRun) continue;

      final result = await runStreamed(step.executable, step.arguments, workingDirectory: step.cwd, environment: {
        ...Platform.environment,
        ...step.env,
      });
      if (!result.success) {
        _logger.error('Step failed: ${step.executable} ${step.arguments.join(' ')} (exit ${result.exitCode})');
        return false;
      }
    }
    return true;
  }
}

class _Step {
  _Step(this.executable, this.arguments, {this.cwd, this.env = const {}});
  final String executable;
  final List<String> arguments;
  final String? cwd;
  final Map<String, String> env;
}
