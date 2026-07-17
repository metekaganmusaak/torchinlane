import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../version.dart';
import 'logger.dart';

/// Warns (never blocks) when a newer torchinlane is published on pub.dev.
///
/// Designed to be safe on every CLI invocation: the pub.dev lookup is cached
/// for [_cacheTtl] and every failure (offline, timeout, parse error) is
/// swallowed so it can never break a command or a build.
class VersionCheck {
  const VersionCheck({Logger logger = const Logger()}) : _logger = logger;

  final Logger _logger;

  static const _cacheTtl = Duration(hours: 24);
  static const _timeout = Duration(seconds: 3);

  /// Set `TORCHINLANE_SKIP_VERSION_CHECK=1` to disable entirely (CI, tests).
  bool get _disabled =>
      Platform.environment['TORCHINLANE_SKIP_VERSION_CHECK'] == '1';

  File get _cacheFile {
    final home = Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return File('$home/.torchinlane/version_check.json');
  }

  Future<void> run() async {
    if (_disabled) return;
    try {
      final latest = await _latestVersion();
      if (latest == null) return;
      if (_isNewer(latest, packageVersion)) {
        _warn(latest);
      }
    } catch (_) {
      // Never let a version check break the actual command.
    }
  }

  /// Returns the latest published version, from cache when fresh, otherwise
  /// from pub.dev (refreshing the cache). Null on any failure.
  Future<String?> _latestVersion() async {
    final cached = _readCache();
    if (cached != null) return cached;

    final res = await http
        .get(Uri.parse('https://pub.dev/api/packages/torchinlane'))
        .timeout(_timeout);
    if (res.statusCode != 200) return null;

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final latest =
        (body['latest'] as Map<String, dynamic>?)?['version'] as String?;
    if (latest != null) _writeCache(latest);
    return latest;
  }

  String? _readCache() {
    try {
      final file = _cacheFile;
      if (!file.existsSync()) return null;
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final checkedAt = DateTime.tryParse(data['checked_at'] as String? ?? '');
      if (checkedAt == null ||
          DateTime.now().difference(checkedAt) > _cacheTtl) {
        return null; // stale -> force refresh
      }
      return data['latest'] as String?;
    } catch (_) {
      return null;
    }
  }

  void _writeCache(String latest) {
    try {
      final file = _cacheFile;
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode({
        'latest': latest,
        'checked_at': DateTime.now().toIso8601String(),
      }));
    } catch (_) {
      // Cache is best-effort.
    }
  }

  void _warn(String latest) {
    _logger.info(
        'A newer torchinlane is available: $packageVersion -> $latest');
    _logger.info('Upgrade the CLI, then re-sync this project:');
    _logger.info('  dart pub global activate torchinlane');
    _logger.info('  torchinlane update');
    _logger.plain('');
  }

  /// True when [a] is a strictly higher semver than [b]. Ignores pre-release
  /// tags (compares the numeric X.Y.Z core only). Any parse issue -> false.
  static bool _isNewer(String a, String b) {
    final pa = _core(a);
    final pb = _core(b);
    if (pa == null || pb == null) return false;
    for (var i = 0; i < 3; i++) {
      if (pa[i] != pb[i]) return pa[i] > pb[i];
    }
    return false;
  }

  static List<int>? _core(String v) {
    final core = v.split('-').first.split('+').first;
    final parts = core.split('.');
    if (parts.length != 3) return null;
    final nums = parts.map(int.tryParse).toList();
    if (nums.any((n) => n == null)) return null;
    return nums.cast<int>();
  }
}
