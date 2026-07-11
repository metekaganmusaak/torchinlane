import 'package:args/command_runner.dart';

import '../project/flutter_project.dart';
import '../shell/logger.dart';

class BumpCommand extends Command<int> {
  BumpCommand({Logger logger = const Logger()}) : _logger = logger;

  final Logger _logger;

  @override
  String get name => 'bump';

  @override
  String get description => 'Bump pubspec.yaml version (build|patch|minor|major).';

  @override
  Future<int> run() async {
    final args = argResults!.rest;
    if (args.isEmpty || !['build', 'patch', 'minor', 'major'].contains(args.first)) {
      _logger.error('Usage: torchinlane bump build|patch|minor|major');
      return 1;
    }
    final kind = args.first;

    final project = FlutterProject.findRoot();
    if (project == null) {
      _logger.error('Not inside a Flutter project.');
      return 1;
    }

    final current = project.readVersion();
    late final ProjectVersion next;
    switch (kind) {
      case 'build':
        next = ProjectVersion(current.major, current.minor, current.patch, current.build + 1);
        break;
      case 'patch':
        next = ProjectVersion(current.major, current.minor, current.patch + 1, current.build + 1);
        break;
      case 'minor':
        next = ProjectVersion(current.major, current.minor + 1, 0, current.build + 1);
        break;
      case 'major':
        next = ProjectVersion(current.major + 1, 0, 0, current.build + 1);
        break;
    }

    final pubspec = project.pubspecFile;
    final content = pubspec.readAsStringSync();
    final updated = content.replaceFirst(
      RegExp(r'^version:\s*.+$', multiLine: true),
      'version: $next',
    );
    pubspec.writeAsStringSync(updated);

    _logger.success('Version bumped: $current -> $next');
    return 0;
  }
}
