import 'dart:io';

import 'package:args/command_runner.dart';

import '../config/torchinlane_config.dart';
import '../project/flutter_project.dart';
import '../shell/logger.dart';
import '../shell/toolchain.dart';

class DoctorCommand extends Command<int> {
  DoctorCommand({Logger logger = const Logger()}) : _logger = logger {
    argParser.addFlag(
      'fix',
      help: 'Install or repair missing tools (fastlane, CocoaPods) and fix PATH.',
      negatable: false,
    );
  }

  final Logger _logger;
  Toolchain get _toolchain => Toolchain(logger: _logger);

  @override
  String get name => 'doctor';

  @override
  String get description => 'Check environment and project configuration.';

  @override
  Future<int> run() async {
    var ok = true;
    final fix = argResults!['fix'] as bool;

    ok &= _checkBinary('flutter');
    ok &= _checkBinary('ruby');
    ok &= await _checkGem(RubyGem.fastlane, fix: fix);
    // CocoaPods is only used for iOS builds, so its absence is not fatal on a
    // machine that never builds iOS (Linux/Windows, Android-only projects).
    ok &= await _checkGem(RubyGem.cocoapods, fix: fix, required: Platform.isMacOS);

    final project = FlutterProject.findRoot();
    if (project == null) {
      _report(false, 'Not inside a Flutter project');
      return 1;
    }
    _report(true, 'Flutter project found at ${project.root.path}');

    final configFile = project.torchinlaneConfigFile;
    if (!configFile.existsSync()) {
      _report(false, 'torchinlane.yaml missing — run `torchinlane init`');
      return 1;
    }
    _report(true, 'torchinlane.yaml found');

    try {
      final config = TorchinlaneConfig.load(configFile);
      _report(true, 'torchinlane.yaml is valid');

      final keyFile = File('${project.root.path}/${config.ios.ascKeyPath}');
      ok &= _report(keyFile.existsSync(), 'App Store Connect key: ${config.ios.ascKeyPath}');

      final serviceAccount = File('${project.root.path}/${config.android.serviceAccountJson}');
      ok &= _report(serviceAccount.existsSync(), 'Play service account: ${config.android.serviceAccountJson}');

      final exportOptions = File('${project.root.path}/ios/ExportOptions.plist');
      ok &= _report(exportOptions.existsSync(), 'ios/ExportOptions.plist');

      ok &= _report(project.changelogsDir.existsSync(), 'changelogs/ directory');
    } catch (e) {
      _report(false, 'torchinlane.yaml is invalid: $e');
      ok = false;
    }

    final hasAnthropicKey = Platform.environment.containsKey('ANTHROPIC_API_KEY');
    _report(hasAnthropicKey, 'ANTHROPIC_API_KEY set (needed for `changelog translate` / `screenshots prompts`)');

    ok &= _checkBinary('xcrun', required: false);
    ok &= _checkBinary('adb', required: false);

    if (ok) {
      _logger.success('\nAll checks passed.');
    } else {
      _logger.error('\nSome checks failed. See above.');
    }
    return ok ? 0 : 1;
  }

  /// Reports on a Ruby gem, repairing it in place when [fix] is set.
  Future<bool> _checkGem(RubyGem gem,
      {required bool fix, bool required = true}) async {
    var report = _toolchain.inspect(gem);

    if (!report.usable && fix) {
      report = await _toolchain.ensure(gem, assumeYes: true);
    }

    final passed = _report(report.usable, report.summary, required: required);
    if (!report.usable && !fix) {
      _logger.info('  -> run `torchinlane doctor --fix` to install/repair it');
    }
    return passed;
  }

  bool _checkBinary(String name, {bool required = true}) {
    final found = Process.runSync(
      Platform.isWindows ? 'where' : 'which',
      [name],
    ).exitCode == 0;
    return _report(found, '$name on PATH', required: required);
  }

  bool _report(bool passed, String label, {bool required = true}) {
    final mark = passed ? '✓' : (required ? '✗' : '~');
    if (passed) {
      _logger.success('$mark $label');
    } else if (required) {
      _logger.error('$mark $label');
    } else {
      _logger.info('$mark $label (optional)');
    }
    return passed || !required;
  }
}
