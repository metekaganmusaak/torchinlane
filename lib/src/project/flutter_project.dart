import 'dart:io';

class ProjectVersion {
  const ProjectVersion(this.major, this.minor, this.patch, this.build);

  final int major;
  final int minor;
  final int patch;
  final int build;

  static ProjectVersion parse(String versionLine) {
    final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)\+(\d+)$').firstMatch(versionLine.trim());
    if (match == null) {
      throw FormatException('Cannot parse version string: "$versionLine". Expected X.Y.Z+B');
    }
    return ProjectVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
    );
  }

  @override
  String toString() => '$major.$minor.$patch+$build';
}

class FlutterProject {
  FlutterProject(this.root);

  final Directory root;

  File get pubspecFile => File('${root.path}/pubspec.yaml');
  Directory get iosDir => Directory('${root.path}/ios');
  Directory get androidDir => Directory('${root.path}/android');
  Directory get changelogsDir => Directory('${root.path}/changelogs');
  File get torchinlaneConfigFile => File('${root.path}/torchinlane.yaml');

  bool get isFlutterProject => pubspecFile.existsSync() && iosDir.existsSync() && androidDir.existsSync();

  /// Walks up from [start] (default: current directory) looking for a
  /// pubspec.yaml + ios/ + android/ combo.
  static FlutterProject? findRoot([Directory? start]) {
    var dir = start ?? Directory.current;
    while (true) {
      final candidate = FlutterProject(dir);
      if (candidate.isFlutterProject) return candidate;
      final parent = dir.parent;
      if (parent.path == dir.path) return null;
      dir = parent;
    }
  }

  ProjectVersion readVersion() {
    final content = pubspecFile.readAsStringSync();
    final match = RegExp(r'^version:\s*(.+)$', multiLine: true).firstMatch(content);
    if (match == null) {
      throw StateError('No "version:" field found in ${pubspecFile.path}');
    }
    return ProjectVersion.parse(match.group(1)!.trim());
  }

  String readAppName() {
    final content = pubspecFile.readAsStringSync();
    final match = RegExp(r'^name:\s*(.+)$', multiLine: true).firstMatch(content);
    return match?.group(1)?.trim() ?? 'app';
  }
}
