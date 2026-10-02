import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../changelog/locale_maps.dart';
import '../config/torchinlane_config.dart';
import '../project/flutter_project.dart';
import '../scaffold/fastlane_scaffolder.dart';
import '../setup/credentials.dart';
import '../store/content.dart';

/// Local evidence only: finding a key never means its remote permissions work.
class StudioReadiness {
  StudioReadiness(this.project, {Map<String, String>? environment})
      : environment = environment ?? Platform.environment;
  final FlutterProject project;
  final Map<String, String> environment;

  TorchinlaneConfig? get config {
    try {
      return TorchinlaneConfig.load(project.torchinlaneConfigFile);
    } catch (_) {
      return null;
    }
  }

  String credentialPath(String platform) {
    final c = config;
    final path = platform == 'ios'
        ? environment['ASC_KEY_PATH'] ?? c?.ios.ascKeyPath
        : environment['GOOGLE_APPLICATION_CREDENTIALS'] ??
            c?.android.serviceAccountJson;
    return path == null ? '' : p.normalize(p.absolute(project.root.path, path));
  }

  // Private in-memory evidence, never included in an HTTP response or log.
  String verificationIdentity(String platform) {
    final path = credentialPath(platform);
    final file = File(path);
    final c = config;
    final identifiers = platform == 'ios'
        ? [
            c?.ios.bundleId,
            environment['ASC_KEY_ID'] ?? c?.ios.ascKeyId,
            environment['ASC_ISSUER_ID'] ?? c?.ios.ascIssuerId
          ]
        : [c?.android.packageName];
    return jsonEncode([
      identifiers,
      path,
      file.existsSync() ? file.readAsStringSync() : null
    ]);
  }

  Map<String, dynamic> snapshot(
      {Map<String, String> verified = const {},
      Map<String, dynamic> tools = const {}}) {
    final c = config;
    final content = StoreContent(project);
    final scaffold = c == null
        ? <String, String>{}
        : FastlaneScaffolder(project).managedFiles(
            appName: c.appName,
            ios: c.ios,
            android: c.android,
            sourceLocale: c.changelogs.sourceLocale,
            changelogsDir: c.changelogs.dir);
    final platformStates = <String, dynamic>{};
    for (final platform in ['ios', 'android']) {
      final source = storeLocale(platform, c?.changelogs.sourceLocale ?? 'en');
      final configured = c != null &&
          c.appName.trim().isNotEmpty &&
          (platform == 'ios' ? c.ios.bundleId : c.android.packageName)
              .trim()
              .isNotEmpty;
      final managed = scaffold.entries.where(
          (e) => !e.key.startsWith(platform == 'ios' ? 'android/' : 'ios/'));
      final outdated = managed
          .where((e) {
            final file = File('${project.root.path}/${e.key}');
            return !file.existsSync() || file.readAsStringSync() != e.value;
          })
          .map((e) => e.key)
          .toList();
      var credential = 'missing';
      final path = credentialPath(platform);
      if (path.isNotEmpty && File(path).existsSync()) {
        try {
          Credentials.validateContents(platform, File(path).readAsStringSync());
          credential = 'present';
        } catch (_) {
          credential = 'invalid';
        }
      }
      final appleIdReady = platform != 'ios' ||
          ((environment['ASC_KEY_ID'] ?? c?.ios.ascKeyId ?? '')
              .trim()
              .isNotEmpty);
      final connected = configured &&
          credential == 'present' &&
          appleIdReady &&
          verified[platform] != null &&
          verified[platform] == verificationIdentity(platform);
      var sourceFields = <String, String>{};
      final issues = <String>[];
      var targets = <String>[];
      var pending = 0;
      var imageCount = 0;
      try {
        final locales = content.locales(platform);
        if (source != null) sourceFields = content.read(platform, source);
        targets = locales.where((l) => l != source).toList();
        for (final target in targets) {
          final fields = content.read(platform, target);
          pending += sourceFields.entries
              .where((e) =>
                  (storeFields[platform]?[e.key] ?? 0) > 0 &&
                  e.value.trim().isNotEmpty &&
                  (fields[e.key] ?? '').trim().isEmpty)
              .length;
        }
        issues.addAll(content.validate([platform], scope: 'metadata'));
        issues.addAll(content.validate([platform], scope: 'notes'));
        for (final locale in locales) {
          for (final group in imageGroups[platform]!) {
            imageCount += content.imageFiles(platform, locale, group).length;
          }
        }
      } catch (_) {
        issues.add(
            'Bir içerik dosyası okunamıyor. JSON biçimini ve dil kodunu kontrol edin.');
      }
      final sourceReady = sourceFields.entries.any((e) =>
          (storeFields[platform]?[e.key] ?? 0) > 0 &&
          e.value.trim().isNotEmpty);
      platformStates[platform] = {
        'configured': configured,
        'scaffoldReady': c != null && outdated.isEmpty,
        'outdatedFiles': outdated,
        'credential': credential,
        'credentialIdsReady': appleIdReady,
        'verified': connected,
        'sourceLocale': source,
        'sourceReady': sourceReady,
        'targets': targets,
        'pendingFields': pending,
        'textIssues': issues,
        'imageCount': imageCount,
        'signing': platform == 'android'
            ? (File('${project.root.path}/android/key.properties').existsSync()
                ? 'configured'
                : 'unknown')
            : (File('${project.root.path}/ios/ExportOptions.plist').existsSync()
                ? 'export-options'
                : 'unknown'),
      };
    }
    return {
      'configError': project.torchinlaneConfigFile.existsSync() && c == null
          ? 'torchinlane.yaml okunamıyor. Önce yapılandırma dosyasını düzeltin.'
          : null,
      'platforms': platformStates,
      'tools': tools,
    };
  }
}
