import 'dart:io';
import 'package:args/command_runner.dart';
import '../project/flutter_project.dart';
import '../studio/server.dart';

class StudioCommand extends Command<int> {
  StudioCommand() {
    argParser
      ..addOption('port',
          defaultsTo: '0', help: 'Loopback port; 0 selects an available port.')
      ..addFlag('open',
          defaultsTo: true, help: 'Open the local panel in your browser.');
  }
  @override
  String get name => 'studio';
  @override
  String get description =>
      'Open a local GUI for setup, translations, store images and deployments.';
  @override
  Future<int> run() async {
    final project = FlutterProject.findRoot();
    if (project == null) {
      throw StateError('Run inside a Flutter project with ios/ and android/.');
    }
    final port = int.tryParse(argResults!['port'] as String);
    if (port == null || port < 0 || port > 65535) {
      throw ArgumentError('Invalid port');
    }
    final server = StudioServer(project);
    final uri = await server.start(port: port);
    stdout.writeln('Torchinlane Studio: $uri');
    stdout.writeln('Keep this terminal open. Ctrl+C stops the local panel.');
    if (argResults!['open'] == true) {
      try {
        if (Platform.isMacOS) {
          await Process.run('open', [uri.toString()]);
        } else if (Platform.isLinux) {
          await Process.run('xdg-open', [uri.toString()]);
        } else if (Platform.isWindows) {
          await Process.run(
              'rundll32', ['url.dll,FileProtocolHandler', uri.toString()]);
        }
      } catch (_) {
        stdout.writeln('Open the URL above in your browser.');
      }
    }
    await serverDone(server);
    return 0;
  }

  Future<void> serverDone(StudioServer server) async {
    if (Platform.isWindows) {
      await Future<void>.delayed(const Duration(days: 365));
      return;
    }
    await ProcessSignal.sigint.watch().first;
    await server.close();
  }
}
