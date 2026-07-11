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

    final steps = <_Step>[];

    if (!uploadOnly) {
      if (deepClean) {
        if (buildAndroid) {
          steps.add(_Step('rm', ['-rf', '$root/android/.gradle', '$root/android/app/build']));
        }
        if (buildIos) {
          steps.add(_Step('rm', ['-rf', '$root/ios/Pods', '$root/ios/Podfile.lock']));
        }
      }
      if (!skipClean) {
        steps.add(_Step('flutter', ['clean'], cwd: root));
        steps.add(_Step('flutter', ['pub', 'get'], cwd: root));
      }
      if (buildIos) {
        steps.add(_Step('pod', ['install'], cwd: '$root/ios'));
      }
    }

    if (buildAndroid) {
      if (!uploadOnly) {
        final args = ['build', 'appbundle'];
        if (config.obfuscate) {
          args.addAll(['--obfuscate', '--split-debug-info=${config.splitDebugInfo}']);
        }
        steps.add(_Step('flutter', args, cwd: root));
      }
      final lane = target == 'production' ? 'deploy_production' : 'deploy_internal';
      steps.add(_Step('fastlane', [lane], cwd: '$root/android', env: env));
    }

    if (buildIos) {
      if (!uploadOnly) {
        final args = ['build', 'ipa', '--export-options-plist=ios/ExportOptions.plist'];
        if (config.obfuscate) {
          args.addAll(['--obfuscate', '--split-debug-info=${config.splitDebugInfo}']);
        }
        steps.add(_Step('flutter', args, cwd: root));
      }
      final lane = target == 'production' ? 'release' : 'beta';
      steps.add(_Step('fastlane', [lane], cwd: '$root/ios', env: env));
    }

    for (final step in steps) {
      _logger.info('\$ ${step.executable} ${step.arguments.join(' ')}${step.cwd != null ? '  (in ${step.cwd})' : ''}');
      if (dryRun) continue;

      final result = await runStreamed(step.executable, step.arguments, workingDirectory: step.cwd, environment: {
        ...Platform.environment,
        ...step.env,
      });
      if (!result.success) {
        _logger.error('Step failed: ${step.executable} ${step.arguments.join(' ')} (exit ${result.exitCode})');
        return result.exitCode;
      }
    }

    if (!dryRun) _logger.success('\nDeploy complete.');
    return 0;
  }
}

class _Step {
  _Step(this.executable, this.arguments, {this.cwd, this.env = const {}});
  final String executable;
  final List<String> arguments;
  final String? cwd;
  final Map<String, String> env;
}
