import 'dart:io';

import 'package:path/path.dart' as p;

import '../changelog/locale_maps.dart';
import 'content.dart';

/// `<locale>/<version>.txt`, else the legacy `<locale>/release_notes.txt`;
/// the same lookup as `ChangelogHelper.note_text`.
String releaseNoteText(Directory changelogs, String locale, String version) {
  final versioned = File(p.join(changelogs.path, locale, '$version.txt'));
  final file = versioned.existsSync()
      ? versioned
      : File(p.join(changelogs.path, locale, 'release_notes.txt'));
  return file.existsSync() ? file.readAsStringSync().trim() : '';
}

/// Mirrors `ChangelogHelper.read_notes`, which reads every folder of the
/// changelogs dir. Run before a build so a bad folder cannot fail the upload.
List<String> releaseNoteErrors(
    Directory changelogs, String version, List<String> platforms) {
  if (!changelogs.existsSync()) return [];
  final folders = changelogs
      .listSync()
      .whereType<Directory>()
      .map((d) => p.basename(d.path))
      .toList()
    ..sort();
  final errors = <String>[];
  for (final platform in platforms) {
    final max = storeFields[platform]!['release_notes']!;
    final sources = <String, String>{};
    for (final folder in folders) {
      final text = releaseNoteText(changelogs, folder, version);
      final locale = storeLocale(platform, folder);
      if (text.isEmpty || locale == null) continue;
      if (text.runes.length > max) {
        errors.add(
            'changelogs/$folder: ${text.runes.length}/$max characters for $platform');
      }
      final other = sources[locale];
      if (other != null) {
        errors.add(
            'changelogs/$other and changelogs/$folder both give the $platform $locale notes; remove one folder');
      }
      sources[locale] = folder;
    }
  }
  return errors;
}

/// This version's notes per listing language, read by `store generate`.
/// Null when the source language has no `<version>.txt`: the notes are then
/// not kept in changelogs and store JSON notes stay as they are.
Map<String, String>? listingReleaseNotes(Directory changelogs,
    String sourceLocale, String version, Iterable<String> languages) {
  File note(String language) =>
      File(p.join(changelogs.path, language, '$version.txt'));
  if (!note(sourceLocale).existsSync()) return null;
  return {
    for (final language in languages)
      if (note(language).existsSync())
        language: note(language).readAsStringSync().trim()
  };
}
