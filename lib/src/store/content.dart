import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../changelog/locale_maps.dart';
import '../project/flutter_project.dart';

const storeFields = {
  'ios': {
    'name': 30,
    'subtitle': 30,
    'description': 4000,
    'keywords': 100,
    'promotional_text': 170,
    'support_url': 0,
    'marketing_url': 0,
    'privacy_url': 0,
    'release_notes': 4000
  },
  'android': {
    'title': 30,
    'short_description': 80,
    'full_description': 4000,
    'video': 0,
    'release_notes': 500
  },
};
const imageGroups = {
  'ios': ['iphone', 'ipad'],
  'android': [
    'phoneScreenshots',
    'sevenInchScreenshots',
    'tenInchScreenshots',
    'tvScreenshots',
    'wearScreenshots',
    'icon',
    'featureGraphic',
    'tvBanner'
  ],
};

int storeFieldLength(String platform, String field, String text) =>
    platform == 'ios' && field == 'keywords'
        ? utf8.encode(text).length
        : text.runes.length;

class StoreContent {
  StoreContent(this.project);
  final FlutterProject project;
  Directory get directory => Directory('${project.root.path}/store');

  void checkLocale(String platform, String locale) {
    if (!storeFields.containsKey(platform) ||
        storeLocale(platform, locale) != locale) {
      throw ArgumentError(
          'Use a supported native $platform store locale: $locale');
    }
  }

  File file(String platform, String locale) {
    checkLocale(platform, locale);
    return safeAsset('$platform/$locale.json');
  }

  Map<String, String> read(String platform, String locale) {
    final target = file(platform, locale);
    if (!target.existsSync()) return {};
    final value = jsonDecode(target.readAsStringSync());
    if (value is! Map || value.values.any((v) => v is! String)) {
      throw FormatException('Expected string fields in ${target.path}');
    }
    return Map<String, String>.from(value);
  }

  void write(String platform, String locale, Map<String, String> fields) {
    if (fields.keys.any((k) => !storeFields[platform]!.containsKey(k))) {
      throw ArgumentError('Unknown metadata field for $platform.');
    }
    final target = file(platform, locale);
    target.parent.createSync(recursive: true);
    // Empty fields mean "leave unchanged", never "delete remote content".
    target.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(fields)}\n');
  }

  List<String> locales(String platform) {
    final dir = Directory('${directory.path}/$platform');
    if (!dir.existsSync()) return [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .map((f) => p.basenameWithoutExtension(f.path))
        .toList()
      ..sort();
  }

  void initialize(List<String> platforms, List<String> requested) {
    for (final platform in platforms) {
      final targets = <String>{};
      for (final locale in requested) {
        final target = storeLocale(platform, locale);
        if (target != null) targets.add(target);
      }
      for (final locale in targets) {
        if (!file(platform, locale).existsSync()) {
          write(platform, locale,
              {for (final k in storeFields[platform]!.keys) k: ''});
        }
      }
    }
  }

  Directory images(String platform, String locale, String group) {
    checkLocale(platform, locale);
    if (!imageGroups[platform]!.contains(group)) {
      throw ArgumentError('Unknown image group.');
    }
    return Directory('${directory.path}/$platform/images/$locale/$group');
  }

  List<File> imageFiles(String platform, String locale, String group) {
    final dir = images(platform, locale, group);
    return dir.existsSync()
        ? (dir.listSync().whereType<File>().toList()
          ..sort((a, b) => p.basename(a.path).compareTo(p.basename(b.path))))
        : [];
  }

  // Never allow assets or symlinks to escape store/. Used by GUI and export.
  File safeAsset(String relative) {
    if (p.isAbsolute(relative)) throw ArgumentError('Asset must be relative.');
    final target = p.normalize(p.join(directory.path, relative));
    if (!p.isWithin(directory.path, target)) {
      throw ArgumentError('Invalid asset path.');
    }
    final entity = File(target);
    var parent = entity.parent;
    while (p.isWithin(directory.path, parent.path)) {
      if (FileSystemEntity.isLinkSync(parent.path)) {
        throw ArgumentError('Symlink assets are not supported.');
      }
      parent = parent.parent;
    }
    if (FileSystemEntity.isLinkSync(target) ||
        FileSystemEntity.isLinkSync(directory.path)) {
      throw ArgumentError('Symlink assets are not supported.');
    }
    return entity;
  }

  List<String> validate(List<String> platforms,
      {String scope = 'all', bool skipNotes = false}) {
    final errors = <String>[];
    for (final platform in platforms) {
      final imageDir = Directory('${directory.path}/$platform/images');
      final targets = {
        ...locales(platform),
        if (imageDir.existsSync())
          ...imageDir
              .listSync()
              .whereType<Directory>()
              .map((d) => p.basename(d.path))
      };
      for (final locale in targets) {
        try {
          checkLocale(platform, locale);
          final data =
              scope == 'images' ? <String, String>{} : read(platform, locale);
          for (final field in data.entries) {
            if (skipNotes && field.key == 'release_notes') continue;
            if ((scope == 'notes' && field.key != 'release_notes') ||
                (scope == 'metadata' && field.key == 'release_notes') ||
                scope == 'images') {
              continue;
            }
            final max = storeFields[platform]![field.key];
            if (max == null) {
              errors.add('$platform/$locale: unknown field ${field.key}');
              continue;
            }
            if (max > 0 &&
                storeFieldLength(platform, field.key, field.value) > max) {
              errors.add(
                  '$platform/$locale/${field.key}: ${storeFieldLength(platform, field.key, field.value)}/$max ${platform == 'ios' && field.key == 'keywords' ? 'UTF-8 bytes' : 'characters'}');
            }
            if (field.key == 'name' &&
                field.value.isNotEmpty &&
                field.value.runes.length < 2) {
              errors.add('$platform/$locale/name: minimum 2 characters');
            }
            if (max == 0 && field.value.isNotEmpty) {
              final uri = Uri.tryParse(field.value);
              if (uri == null ||
                  !['http', 'https'].contains(uri.scheme) ||
                  uri.host.isEmpty) {
                errors.add(
                    '$platform/$locale/${field.key}: expected HTTP(S) URL');
              }
            }
          }
          if (scope == 'notes' || scope == 'metadata') continue;
          final base = Directory('${directory.path}/$platform/images/$locale');
          if (base.existsSync()) {
            for (final child in base.listSync()) {
              if (!imageGroups[platform]!.contains(p.basename(child.path))) {
                errors.add(
                    '$platform/$locale: unknown image group ${p.basename(child.path)}');
              }
            }
          }
          for (final group in imageGroups[platform]!) {
            final files = imageFiles(platform, locale, group);
            final singleton =
                ['icon', 'featureGraphic', 'tvBanner'].contains(group);
            final max = singleton ? 1 : (platform == 'ios' ? 10 : 8);
            // Apple has a separate count for each resolution/display class.
            final counts = <String, int>{};
            for (final f in files) {
              safeAsset(p.relative(f.path, from: directory.path));
              final issue = validateImage(f, platform, group);
              if (issue != null) {
                errors.add(
                    '$platform/$locale/$group/${p.basename(f.path)}: $issue');
                continue;
              }
              final decoded = img.decodeImage(f.readAsBytesSync())!;
              final size = platform == 'ios'
                  ? '${decoded.width < decoded.height ? decoded.width : decoded.height}x${decoded.width > decoded.height ? decoded.width : decoded.height}'
                  : group;
              counts[size] = (counts[size] ?? 0) + 1;
            }
            if (counts.values.any((count) => count > max)) {
              errors.add(
                  '$platform/$locale/$group: maximum $max images per display class');
            }
          }
        } catch (e) {
          errors.add('$platform/$locale: $e');
        }
      }
    }
    return errors;
  }

  static String? validateImage(File file, String platform, String group) {
    if (!['.png', '.jpg', '.jpeg']
        .contains(p.extension(file.path).toLowerCase())) {
      return 'PNG or JPEG required';
    }
    if (file.lengthSync() > 20 * 1024 * 1024) return 'Image exceeds 20 MB';
    final image = img.decodeImage(file.readAsBytesSync());
    if (image == null) return 'Invalid image';
    final w = image.width, h = image.height;
    if (platform == 'android') {
      if (group == 'icon') {
        return w == 512 && h == 512 ? null : 'Icon must be 512x512';
      }
      if (group == 'featureGraphic') {
        return w == 1024 && h == 500
            ? _alpha(image)
            : 'Feature graphic must be 1024x500';
      }
      if (group == 'tvBanner') {
        return w == 1280 && h == 720
            ? _alpha(image)
            : 'TV banner must be 1280x720';
      }
      if (w < 320 ||
          h < 320 ||
          w > 3840 ||
          h > 3840 ||
          w > h * 2 ||
          h > w * 2) {
        return 'Screenshots: 320–3840 px; longest side at most twice shortest';
      }
      return _alpha(image);
    }
    final size = '${w < h ? w : h}x${w > h ? w : h}';
    const phone = {
      '1260x2736',
      '1290x2796',
      '1320x2868',
      '1284x2778',
      '1242x2688',
      '1170x2532',
      '1125x2436',
      '1080x2340',
      '1242x2208',
      '750x1334',
      '640x1136',
      '640x960'
    };
    const tablet = {
      '2064x2752',
      '2048x2732',
      '1668x2420',
      '1668x2388',
      '1640x2360',
      '1668x2224',
      '1536x2048',
      '1488x2266'
    };
    if (!(group == 'ipad' ? tablet : phone).contains(size)) {
      return 'Unsupported $group screenshot dimensions $w x $h';
    }
    return _alpha(image);
  }

  static String? _alpha(img.Image image) {
    if (image.hasAlpha &&
        image.any((pixel) => pixel.a != image.maxChannelValue)) {
      return 'Remove transparent pixels before uploading';
    }
    return null;
  }

  /// Fastlane staging contains only supplied nonempty fields, no credential data.
  void exportTo(Directory destination, List<String> platforms,
      {String scope = 'all', String? versionCode, bool skipNotes = false}) {
    final errors = validate(platforms, scope: scope, skipNotes: skipNotes);
    if (errors.isNotEmpty) throw StateError(errors.join('\n'));
    for (final platform in platforms) {
      final root = Directory('${destination.path}/$platform');
      root.createSync(recursive: true);
      Directory('${root.path}/metadata').createSync(recursive: true);
      if (platform == 'ios') {
        Directory('${root.path}/screenshots').createSync(recursive: true);
      }
      for (final locale in locales(platform)) {
        final data = read(platform, locale);
        for (final entry in data.entries) {
          if (entry.value.trim().isEmpty) continue;
          final notes = entry.key == 'release_notes';
          if (skipNotes && notes) continue;
          if (scope == 'images' ||
              (scope == 'notes' && !notes) ||
              (scope == 'metadata' && notes)) {
            continue;
          }
          final key = platform == 'ios' && entry.key == 'privacy_url'
              ? 'privacy_url'
              : entry.key;
          final path = platform == 'android' && notes
              ? '$locale/changelogs/${versionCode ?? 'default'}.txt'
              : '$locale/$key.txt';
          final out = File('${root.path}/metadata/$path');
          out.parent.createSync(recursive: true);
          out.writeAsStringSync(entry.value);
        }
      }
      if (scope == 'notes' || scope == 'metadata') continue;
      final imageRoot = Directory('${directory.path}/$platform/images');
      if (!imageRoot.existsSync()) continue;
      for (final localeDir in imageRoot.listSync().whereType<Directory>()) {
        final locale = p.basename(localeDir.path);
        for (final group in imageGroups[platform]!) {
          final files = imageFiles(platform, locale, group);
          for (var i = 0; i < files.length; i++) {
            final filename =
                '${i.toString().padLeft(3, '0')}_${group}_${p.basename(files[i].path)}';
            final target = platform == 'ios'
                ? '${root.path}/screenshots/$locale/$filename'
                : '${root.path}/metadata/$locale/images/${[
                    'icon',
                    'featureGraphic',
                    'tvBanner'
                  ].contains(group) ? '$group${p.extension(files[i].path)}' : '$group/$filename'}';
            final out = File(target);
            out.parent.createSync(recursive: true);
            files[i].copySync(out.path);
          }
        }
      }
    }
  }
}
