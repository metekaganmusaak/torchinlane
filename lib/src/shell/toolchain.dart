import 'dart:io';

import 'logger.dart';
import 'process_runner.dart';

/// Ruby gems torchinlane depends on, and how to detect / install them.
///
/// Both `fastlane` and `cocoapods` are Ruby gems, so a single broken or
/// unexported Ruby setup breaks them together — that is why detection,
/// installation and PATH repair all live here instead of in each command.
enum RubyGem {
  fastlane('fastlane', 'fastlane'),
  cocoapods('cocoapods', 'pod');

  const RubyGem(this.gemName, this.binary);

  /// Name passed to `gem install`.
  final String gemName;

  /// Executable the gem puts on PATH.
  final String binary;
}

/// How a gem's binary looks from the current shell.
enum ToolStatus {
  /// Binary resolves on PATH and runs.
  ok,

  /// Gem is installed but its bin dir is not exported on PATH.
  installedNotOnPath,

  /// Gem is on PATH but fails to run (classic "not in valid state" CocoaPods
  /// breakage: a Ruby/gem mismatch after a system Ruby or Xcode upgrade).
  broken,

  /// Not installed at all.
  missing,
}

class ToolReport {
  const ToolReport(this.gem, this.status, {this.version, this.binDir});

  final RubyGem gem;
  final ToolStatus status;

  /// Reported version when the binary runs, else null.
  final String? version;

  /// Directory containing the gem binary, when found off-PATH.
  final String? binDir;

  bool get usable => status == ToolStatus.ok;

  String get summary => switch (status) {
        ToolStatus.ok => '${gem.binary} ${version ?? ''}'.trim(),
        ToolStatus.installedNotOnPath =>
          '${gem.gemName} installed at ${binDir ?? '?'} but not on PATH',
        ToolStatus.broken =>
          '${gem.binary} found on PATH but not in a valid state',
        ToolStatus.missing => '${gem.gemName} not installed',
      };
}

/// Detects, installs and repairs the Ruby gems torchinlane shells out to.
class Toolchain {
  const Toolchain({Logger logger = const Logger()}) : _logger = logger;

  final Logger _logger;

  static const _shellProfiles = ['.zshrc', '.bashrc', '.bash_profile'];
  static const _pathMarker = '# added by torchinlane';

  String get _home =>
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';

  // ---------------------------------------------------------------- detection

  /// Inspects [gem] without modifying anything.
  ToolReport inspect(RubyGem gem) {
    final onPath = _which(gem.binary);
    if (onPath != null) {
      final version = _versionOf(gem.binary);
      if (version != null) {
        return ToolReport(gem, ToolStatus.ok,
            version: version, binDir: File(onPath).parent.path);
      }
      // Resolves but won't run: broken install, not a missing one.
      return ToolReport(gem, ToolStatus.broken,
          binDir: File(onPath).parent.path);
    }

    final strayBin = _findGemBinOffPath(gem.binary);
    if (strayBin != null) {
      return ToolReport(gem, ToolStatus.installedNotOnPath,
          binDir: File(strayBin).parent.path);
    }
    return ToolReport(gem, ToolStatus.missing);
  }

  /// Candidate gem bin directories that commonly are not exported on PATH.
  List<String> gemBinDirs() {
    final dirs = <String>{};

    // `gem environment gemdir` -> the active RubyGems install dir.
    final gemDir = _capture('gem', ['environment', 'gemdir']);
    if (gemDir != null && gemDir.isNotEmpty) dirs.add('$gemDir/bin');

    // User-level gem dir (`gem install --user-install`, the default on macOS
    // system Ruby, which is not writable without sudo).
    final userDir = _capture('gem', ['environment', 'user_gemhome']) ??
        _capture('ruby', [
          '-e',
          'require "rubygems"; print Gem.user_dir',
        ]);
    if (userDir != null && userDir.isNotEmpty) dirs.add('$userDir/bin');

    if (_home.isNotEmpty) {
      dirs.addAll([
        '$_home/.gem/ruby/bin',
        '$_home/.rbenv/shims',
        '$_home/.rvm/bin',
      ]);
    }
    dirs.addAll([
      '/opt/homebrew/bin',
      '/usr/local/bin',
      '/opt/homebrew/lib/ruby/gems/bin',
    ]);

    return dirs.where((d) => Directory(d).existsSync()).toList();
  }

  // ------------------------------------------------------------- installation

  /// Ensures [gem] is installed, on PATH and runnable.
  ///
  /// Installs the latest published version when missing, reinstalls when the
  /// existing install is broken, and appends the gem bin dir to the user's
  /// shell profile when the gem exists but is invisible. Returns the report
  /// after the repair attempt.
  Future<ToolReport> ensure(RubyGem gem, {bool assumeYes = false}) async {
    assumeYes = assumeYes || Platform.environment['CI'] == 'true';
    var report = inspect(gem);
    if (report.usable) return report;

    switch (report.status) {
      case ToolStatus.ok:
        return report;

      case ToolStatus.installedNotOnPath:
        _logger.info('${gem.gemName} is installed but not on PATH.');
        if (report.binDir != null) {
          await _exportPath(report.binDir!, assumeYes: assumeYes);
        }

      case ToolStatus.broken:
        _logger.info(
            '${gem.binary} is installed but not in a valid state — reinstalling ${gem.gemName}.');
        if (!await _installGem(gem, reinstall: true, assumeYes: assumeYes)) {
          return report;
        }

      case ToolStatus.missing:
        _logger.info('${gem.gemName} is not installed.');
        if (!await _installGem(gem, assumeYes: assumeYes)) return report;
    }

    report = inspect(gem);

    // A fresh install very often lands in a gem bin dir the current shell
    // never exported; wire it up rather than telling the user to.
    if (report.status == ToolStatus.installedNotOnPath &&
        report.binDir != null) {
      await _exportPath(report.binDir!, assumeYes: assumeYes);
      report = inspect(gem);
    }
    return report;
  }

  /// Installs [gem] at its latest published version.
  ///
  /// On macOS the system Ruby's gem dir is not user-writable, so a plain
  /// `gem install` fails with EACCES; `--user-install` is used there instead of
  /// silently escalating to sudo.
  Future<bool> _installGem(RubyGem gem,
      {bool reinstall = false, bool assumeYes = false}) async {
    if (_which('gem') == null) {
      _logger.error(
          'Ruby/RubyGems not found. Install Ruby first (macOS: `brew install ruby`), then re-run.');
      return false;
    }

    final userInstall = _needsUserInstall();
    final args = <String>[
      'install',
      gem.gemName,
      '--no-document',
      if (userInstall) '--user-install',
    ];

    _logger.info('\$ gem ${args.join(' ')}');
    if (reinstall) {
      // Best-effort: clears a half-written gem that makes `pod` throw.
      await runStreamed('gem',
          ['uninstall', gem.gemName, '--all', '--executables', '--force']);
    }

    final result = await runStreamed('gem', args);
    if (!result.success) {
      _logger
          .error('Failed to install ${gem.gemName} (exit ${result.exitCode}).');
      _logger.info('Try manually: gem install ${gem.gemName}'
          '${userInstall ? ' --user-install' : ''}');
      return false;
    }

    if (gem == RubyGem.cocoapods) {
      // Without a pod repo the first `pod install` fails on a fresh machine.
      await runStreamed('pod', ['setup']);
    }
    return true;
  }

  /// True when the active gem dir is not writable, i.e. `--user-install` is the
  /// only non-sudo path (macOS system Ruby).
  bool _needsUserInstall() {
    final gemDir = _capture('gem', ['environment', 'gemdir']);
    if (gemDir == null || gemDir.isEmpty) return false;
    if (gemDir.startsWith('/Library/Ruby') ||
        gemDir.startsWith('/System/Library')) {
      return true;
    }
    // Probe writability directly rather than guessing from the path.
    try {
      final probe = File('$gemDir/.torchinlane_write_probe');
      probe.writeAsStringSync('');
      probe.deleteSync();
      return false;
    } catch (_) {
      return true;
    }
  }

  // ---------------------------------------------------------------- PATH wiring

  /// Appends `export PATH="$dir:$PATH"` to the user's shell profile(s), once.
  ///
  /// The export cannot affect the already-running parent shell, so the current
  /// process's PATH is not updated — the user is told to reload. Child
  /// processes launched by this run still find the binary because callers pass
  /// [augmentedEnvironment].
  Future<bool> _exportPath(String dir, {bool assumeYes = false}) async {
    if (Platform.isWindows) {
      _logger.info('Add this directory to your PATH manually: $dir');
      return false;
    }
    if (_home.isEmpty) return false;

    if (!assumeYes &&
        !_confirm('Add $dir to your PATH in your shell profile?')) {
      _logger.info('Skipped. Add it manually: export PATH="$dir:\$PATH"');
      return false;
    }

    final line = 'export PATH="$dir:\$PATH"  $_pathMarker';
    var wrote = false;

    for (final name in _shellProfiles) {
      final file = File('$_home/$name');
      if (!file.existsSync()) continue;
      final content = file.readAsStringSync();
      if (content.contains(dir)) continue; // already exported
      file.writeAsStringSync(
        '${content.endsWith('\n') ? content : '$content\n'}$line\n',
        mode: FileMode.write,
      );
      _logger.success('Added $dir to PATH in ~/$name');
      wrote = true;
    }

    if (!wrote) {
      // No existing profile: create the one matching the login shell.
      final shell = Platform.environment['SHELL'] ?? '';
      final name = shell.contains('bash') ? '.bashrc' : '.zshrc';
      File('$_home/$name').writeAsStringSync('$line\n', mode: FileMode.append);
      _logger.success('Added $dir to PATH in ~/$name');
      wrote = true;
    }

    _logger
        .info('Run `source ~/.zshrc` (or open a new terminal) to pick it up.');
    return wrote;
  }

  /// Environment for child processes, with every known gem bin dir prepended to
  /// PATH so a freshly installed gem works in this same run without a reload.
  Map<String, String> augmentedEnvironment(
      [Map<String, String> extra = const {}]) {
    final env = Map<String, String>.from(Platform.environment)..addAll(extra);
    final separator = Platform.isWindows ? ';' : ':';
    final current = (env['PATH'] ?? '').split(separator);
    final additions = gemBinDirs().where((d) => !current.contains(d));
    if (additions.isNotEmpty) {
      env['PATH'] = [...additions, ...current].join(separator);
    }
    return env;
  }

  // ------------------------------------------------------------------- helpers

  bool _confirm(String question) {
    stdout.write('$question (Y/n): ');
    final answer = stdin.readLineSync()?.trim().toLowerCase() ?? '';
    return answer.isEmpty || answer == 'y' || answer == 'yes';
  }

  String? _which(String binary) {
    try {
      final result = Process.runSync(
        Platform.isWindows ? 'where' : 'which',
        [binary],
        environment: augmentedEnvironmentWithoutRecursion(),
        includeParentEnvironment: false,
      );
      if (result.exitCode != 0) return null;
      final path = (result.stdout as String).trim().split('\n').first.trim();
      return path.isEmpty ? null : path;
    } catch (_) {
      return null;
    }
  }

  /// PATH lookup env that must not call [gemBinDirs] (which itself shells out),
  /// to avoid infinite recursion.
  Map<String, String> augmentedEnvironmentWithoutRecursion() =>
      Map<String, String>.from(Platform.environment);

  /// Runs `binary --version`; null when it cannot run (broken install).
  String? _versionOf(String binary) {
    try {
      final result = Process.runSync(binary, ['--version'],
          environment: augmentedEnvironment(), includeParentEnvironment: false);
      if (result.exitCode != 0) return null;
      final out = ('${result.stdout}'.trim().isEmpty
              ? '${result.stderr}'
              : '${result.stdout}')
          .trim();
      // `fastlane --version` prints a multi-line banner (deprecation warnings,
      // install path) before the actual version, so pick the first line that
      // contains an X.Y.Z rather than blindly taking line one.
      final semver = RegExp(r'\d+\.\d+(\.\d+)?');
      for (final line in out.split('\n')) {
        final match = semver.firstMatch(line);
        if (match != null) return match.group(0);
      }
      return out.split('\n').first.trim();
    } catch (_) {
      return null;
    }
  }

  /// Looks for [binary] inside known gem bin dirs that are absent from PATH.
  String? _findGemBinOffPath(String binary) {
    for (final dir in gemBinDirs()) {
      final file = File('$dir/$binary');
      if (file.existsSync()) return file.path;
    }
    return null;
  }

  String? _capture(String executable, List<String> args) {
    try {
      final result = Process.runSync(executable, args);
      if (result.exitCode != 0) return null;
      return (result.stdout as String).trim();
    } catch (_) {
      return null;
    }
  }
}
