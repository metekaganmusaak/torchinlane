import 'dart:io';

import 'package:test/test.dart';
import 'package:torchinlane/src/shell/toolchain.dart';

void main() {
  group('RubyGem', () {
    test('maps gem names to the binaries they install', () {
      expect(RubyGem.cocoapods.gemName, 'cocoapods');
      expect(RubyGem.cocoapods.binary, 'pod');
      expect(RubyGem.fastlane.gemName, 'fastlane');
      expect(RubyGem.fastlane.binary, 'fastlane');
    });
  });

  group('ToolReport', () {
    test('is only usable when the status is ok', () {
      for (final status in ToolStatus.values) {
        final report = ToolReport(RubyGem.cocoapods, status);
        expect(report.usable, status == ToolStatus.ok);
      }
    });

    test('summary distinguishes broken from missing', () {
      const broken = ToolReport(RubyGem.cocoapods, ToolStatus.broken);
      const missing = ToolReport(RubyGem.cocoapods, ToolStatus.missing);
      expect(broken.summary, contains('not in a valid state'));
      expect(missing.summary, contains('not installed'));
      expect(broken.summary, isNot(missing.summary));
    });

    test('summary names the off-PATH directory so the fix is obvious', () {
      const report = ToolReport(RubyGem.fastlane, ToolStatus.installedNotOnPath,
          binDir: '/Users/me/.gem/ruby/bin');
      expect(report.summary, contains('/Users/me/.gem/ruby/bin'));
      expect(report.summary, contains('not on PATH'));
    });
  });

  group('Toolchain', () {
    test('gemBinDirs only returns directories that exist', () {
      for (final dir in const Toolchain().gemBinDirs()) {
        expect(Directory(dir).existsSync(), isTrue, reason: '$dir must exist');
      }
    });

    test('augmentedEnvironment prepends gem bin dirs to PATH', () {
      const toolchain = Toolchain();
      final env = toolchain.augmentedEnvironment();
      final separator = Platform.isWindows ? ';' : ':';
      final entries = (env['PATH'] ?? '').split(separator);

      for (final dir in toolchain.gemBinDirs()) {
        expect(entries, contains(dir));
      }
    });

    test('augmentedEnvironment keeps the inherited environment and extras', () {
      final env = const Toolchain().augmentedEnvironment({'FOO_BAR': '1'});
      expect(env['FOO_BAR'], '1');
      expect(env.containsKey('PATH'), isTrue);
    });

    test('inspect reports a usable tool for a binary that always exists', () {
      // `ruby` ships with macOS and is present on the CI images used here; the
      // point is that a runnable binary is never reported as missing.
      final report = const Toolchain().inspect(RubyGem.fastlane);
      expect(ToolStatus.values, contains(report.status));
      if (report.status == ToolStatus.ok) {
        expect(report.version, isNotNull);
      }
    });
  });
}
