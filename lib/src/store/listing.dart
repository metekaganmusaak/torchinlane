import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../changelog/locale_maps.dart';
import 'content.dart';

/// Listing field → native store field. URL fields are read from the source
/// language when a language leaves them out.
const listingTargets = {
  'ios': {
    'name': 'name',
    'subtitle': 'subtitle',
    'description': 'description',
    'keywords': 'keywords',
    'promotional_text': 'promotional_text',
    'support_url': 'support_url',
    'marketing_url': 'marketing_url',
    'privacy_url': 'privacy_url',
  },
  'android': {
    'name': 'title',
    'short_description': 'short_description',
    'description': 'full_description',
    'video': 'video',
  },
};
const listingSharedFields = {
  'support_url',
  'marketing_url',
  'privacy_url',
  'video'
};

/// Read by screenshot generators, never uploaded.
const listingGeneratorFields = {'tagline', 'screenshots'};

/// `store/listing/<language>.json`: one text per language, fanned out to every
/// Apple and Google locale of that language by [generate].
class StoreListing {
  StoreListing(this.content);
  final StoreContent content;
  Directory get directory => Directory('${content.directory.path}/listing');

  List<String> languages() => directory.existsSync()
      ? (directory
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .map((f) => p.basenameWithoutExtension(f.path))
          .toList()
        ..sort())
      : [];

  Map<String, dynamic> read(String language) {
    if (!listingLanguages.containsKey(language)) {
      throw ArgumentError(
          'Unknown listing language $language; see `torchinlane store languages`.');
    }
    final file = content.safeAsset('listing/$language.json');
    if (!file.existsSync()) return {};
    final value = jsonDecode(file.readAsStringSync());
    if (value is! Map<String, dynamic>) {
      throw FormatException('Expected a JSON object in ${file.path}');
    }
    for (final e in value.entries) {
      final known = listingTargets.values.any((m) => m.containsKey(e.key)) ||
          listingGeneratorFields.contains(e.key);
      if (!known) {
        throw FormatException('listing/$language: unknown field ${e.key}');
      }
      final ok = e.key == 'screenshots'
          ? e.value is List && (e.value as List).every((s) => s is String)
          : e.value is String;
      if (!ok) {
        throw FormatException('listing/$language: bad type for ${e.key}');
      }
    }
    return value;
  }

  /// Writes native locale files for every language that has a listing file.
  /// With [releaseNotes] (per language, see `listingReleaseNotes`) every locale
  /// gets its language's notes and a language without notes loses stale ones;
  /// without it existing release notes are kept.
  /// Nothing is written when any value breaks a store limit.
  Map<String, int> generate(List<String> platforms,
      {String from = 'en',
      bool dryRun = false,
      Map<String, String>? releaseNotes}) {
    final source = read(from);
    final writes = <(String, String, Map<String, String>)>[];
    final errors = <String>[];
    for (final language in languages()) {
      final listing = read(language);
      for (final platform in platforms) {
        final fields = <String, String>{};
        for (final e in listingTargets[platform]!.entries) {
          final value = (listing[e.key] as String?)?.trim() ?? '';
          final shared = listingSharedFields.contains(e.key)
              ? (source[e.key] as String?)?.trim() ?? ''
              : '';
          final text = value.isNotEmpty ? value : shared;
          if (text.isEmpty) continue;
          final max = storeFields[platform]![e.value]!;
          final length = storeFieldLength(platform, e.value, text);
          if (max > 0 && length > max) {
            errors.add(
                'listing/$language.json ${e.key} ($platform ${e.value}): $length/$max');
          }
          fields[e.value] = text;
        }
        final languageNotes = releaseNotes?[language] ?? '';
        final notes =
            platform == 'ios' ? appleText(languageNotes) : languageNotes;
        if (notes.isNotEmpty) {
          final max = storeFields[platform]!['release_notes']!;
          if (notes.runes.length > max) {
            errors.add(
                'changelogs/$language release notes ($platform): ${notes.runes.length}/$max');
          }
          fields['release_notes'] = notes;
        }
        // URLs alone never create a locale: Apple needs text in each one.
        final hasText = listingTargets[platform]!.keys.any((k) =>
            !listingSharedFields.contains(k) &&
            ((listing[k] as String?)?.trim() ?? '').isNotEmpty);
        if (!hasText) continue;
        for (final locale in listingLanguages[language]![platform]!) {
          writes.add((platform, locale, fields));
        }
      }
    }
    if (errors.isNotEmpty) throw StateError(errors.join('\n'));
    final counts = {for (final platform in platforms) platform: 0};
    for (final (platform, locale, fields) in writes) {
      counts[platform] = counts[platform]! + 1;
      if (dryRun) continue;
      final data = {...content.read(platform, locale), ...fields};
      if (releaseNotes != null && !fields.containsKey('release_notes')) {
        data.remove('release_notes');
      }
      content.write(platform, locale, data);
    }
    return counts;
  }
}
