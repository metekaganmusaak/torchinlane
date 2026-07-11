import 'package:args/command_runner.dart';

import '../config/torchinlane_config.dart';
import '../project/flutter_project.dart';
import '../scaffold/fastlane_scaffolder.dart';
import '../shell/cli_prompt.dart';
import '../shell/logger.dart';

class InitCommand extends Command<int> {
  InitCommand({Logger logger = const Logger()}) : _logger = logger {
    argParser.addFlag('force', help: 'Overwrite existing fastlane setup.', negatable: false);
  }

  final Logger _logger;

  @override
  String get name => 'init';

  @override
  String get description => 'Scaffold fastlane + torchinlane.yaml for this Flutter project.';

  @override
  Future<int> run() async {
    final project = FlutterProject.findRoot();
    if (project == null) {
      _logger.error('Not inside a Flutter project (need pubspec.yaml + ios/ + android/).');
      return 1;
    }

    final force = argResults!['force'] as bool;
    if (project.torchinlaneConfigFile.existsSync() && !force) {
      _logger.info('torchinlane.yaml already exists. Use --force to overwrite.');
      return 0;
    }

    final defaultAppName = project.readAppName();
    final appName = ask('App name', defaultValue: defaultAppName);

    _logger.info('\n--- iOS ---');
    final bundleId = ask('iOS bundle identifier (e.g. com.company.app)');
    final teamId = ask('Apple Developer Team ID');
    final itcTeamId = ask('App Store Connect Team ID', defaultValue: teamId);
    final appleId = ask('Apple ID email');
    final ascKeyId = ask('App Store Connect API Key ID');
    final ascIssuerId = ask('App Store Connect API Issuer ID');
    final ascKeyPath = ask('Path to App Store Connect .p8 key file', defaultValue: 'ios/api_key.p8');
    final firebaseCrashlytics = askYesNo('Upload dSYMs to Firebase Crashlytics?');

    _logger.info('\n--- Android ---');
    final packageName = ask('Android package name (e.g. com.company.app)');
    final serviceAccountJson = ask(
      'Path to Google Play service account JSON',
      defaultValue: 'android/fastlane/fastlane-service-account.json',
    );

    _logger.info('\n--- Changelogs ---');
    final sourceLocale = ask('Source locale for changelog translation', defaultValue: 'en');

    final ios = IosConfig(
      bundleId: bundleId,
      teamId: teamId,
      itcTeamId: itcTeamId,
      appleId: appleId,
      ascKeyId: ascKeyId,
      ascIssuerId: ascIssuerId,
      ascKeyPath: ascKeyPath,
      firebaseCrashlytics: firebaseCrashlytics,
    );
    final android = AndroidConfig(packageName: packageName, serviceAccountJson: serviceAccountJson);

    final scaffolder = FastlaneScaffolder(project);
    scaffolder.scaffold(appName: appName, ios: ios, android: android, sourceLocale: sourceLocale);

    _logger.success('\nFastlane scaffold created.');
    _logger.info('Next steps:');
    _logger.info('  1. Place your App Store Connect API key at: ${ios.ascKeyPath}');
    _logger.info('  2. Place your Google Play service account JSON at: ${android.serviceAccountJson}');
    _logger.info('  3. Run `torchinlane doctor` to verify your setup.');

    return 0;
  }
}

/// Exposed for testing without going through stdin prompts.
void writeScaffoldNonInteractive({
  required FlutterProject project,
  required String appName,
  required IosConfig ios,
  required AndroidConfig android,
  required String sourceLocale,
}) {
  FastlaneScaffolder(project).scaffold(appName: appName, ios: ios, android: android, sourceLocale: sourceLocale);
}
