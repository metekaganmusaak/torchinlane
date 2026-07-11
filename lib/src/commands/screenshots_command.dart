import 'dart:io';

import 'package:args/command_runner.dart';

import '../project/flutter_project.dart';
import '../screenshots/capture.dart';
import '../screenshots/prompt_generator.dart';
import '../shell/cli_prompt.dart';
import '../shell/logger.dart';

class ScreenshotsCommand extends Command<int> {
  ScreenshotsCommand({Logger logger = const Logger()}) {
    addSubcommand(_CaptureCommand(logger: logger));
    addSubcommand(_PromptsCommand(logger: logger));
  }

  @override
  String get name => 'screenshots';

  @override
  String get description => 'Capture raw screenshots and generate store-image prompts.';
}

class _CaptureCommand extends Command<int> {
  _CaptureCommand({Logger logger = const Logger()}) : _logger = logger {
    argParser
      ..addOption('platform', allowed: ['ios', 'android'], mandatory: true)
      ..addOption('locale', defaultsTo: 'en');
  }

  final Logger _logger;

  @override
  String get name => 'capture';

  @override
  String get description =>
      'Interactively capture screenshots: run your app on device/simulator, press Enter per screen.';

  @override
  Future<int> run() async {
    final project = FlutterProject.findRoot();
    if (project == null) {
      _logger.error('Not inside a Flutter project.');
      return 1;
    }

    final platform = argResults!['platform'] as String;
    final locale = argResults!['locale'] as String;
    final outputDir = Directory('${project.root.path}/screenshots');
    final capture = ScreenshotCapture(outputDir: outputDir);

    String targetId;
    if (platform == 'ios') {
      final devices = await ScreenshotCapture.listIosSimulators();
      if (devices.isEmpty) {
        _logger.error('No booted iOS simulators found. Boot one first: `open -a Simulator`.');
        return 1;
      }
      targetId = devices.length == 1
          ? devices.first['udid']!
          : _pickDevice(devices);
    } else {
      final devices = await ScreenshotCapture.listAndroidDevices();
      if (devices.isEmpty) {
        _logger.error('No connected Android devices/emulators found (`adb devices`).');
        return 1;
      }
      targetId = devices.length == 1 ? devices.first : askChoice('Select Android device', devices);
    }

    _logger.info('Run your app on this device now (e.g. `flutter run -d $targetId`).');
    _logger.info('For each screen: navigate to it, then come back here and press Enter.\n');

    while (true) {
      final pageName = ask('Page name (blank to finish)');
      if (pageName.isEmpty) break;

      stdout.write('Navigate to "$pageName" now, then press Enter to capture...');
      stdin.readLineSync();

      final entry = platform == 'ios'
          ? await capture.captureIos(simulatorUdid: targetId, locale: locale, pageName: pageName)
          : await capture.captureAndroid(serial: targetId, locale: locale, pageName: pageName);
      capture.appendToManifest(entry);
      _logger.success('Captured: ${entry.path}');
    }

    _logger.success('\nDone. Manifest: ${outputDir.path}/manifest.json');
    return 0;
  }

  String _pickDevice(List<Map<String, String>> devices) {
    final labels = devices.map((d) => '${d['name']} (${d['udid']})').toList();
    final chosen = askChoice('Select iOS simulator', labels);
    final index = labels.indexOf(chosen);
    return devices[index]['udid']!;
  }
}

class _PromptsCommand extends Command<int> {
  _PromptsCommand({Logger logger = const Logger()}) : _logger = logger;

  final Logger _logger;

  @override
  String get name => 'prompts';

  @override
  String get description => 'Analyze the project and generate store-ready image-generation prompts.';

  @override
  Future<int> run() async {
    final project = FlutterProject.findRoot();
    if (project == null) {
      _logger.error('Not inside a Flutter project.');
      return 1;
    }

    final generator = StorePromptGenerator();
    _logger.info('Analyzing project...');
    final summary = generator.buildProjectSummary(project);

    _logger.info('Generating store screenshot prompts via Claude API...');
    try {
      final markdown = await generator.generateMarkdown(summary);
      final outFile = File('${project.root.path}/screenshots/store_prompts.md');
      outFile.createSync(recursive: true);
      outFile.writeAsStringSync(markdown);
      _logger.success('Wrote ${outFile.path}');
      return 0;
    } on StorePromptGenerationException catch (e) {
      _logger.error(e.toString());
      return 1;
    }
  }
}
