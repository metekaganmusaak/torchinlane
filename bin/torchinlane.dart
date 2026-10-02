import 'dart:io';

import 'package:args/command_runner.dart';

import 'package:torchinlane/src/commands/bump_command.dart';
import 'package:torchinlane/src/commands/store_command.dart';
import 'package:torchinlane/src/commands/credentials_command.dart';
import 'package:torchinlane/src/commands/studio_command.dart';
import 'package:torchinlane/src/commands/ci_command.dart';
import 'package:torchinlane/src/commands/signing_command.dart';
import 'package:torchinlane/src/commands/changelog_command.dart';
import 'package:torchinlane/src/commands/deploy_command.dart';
import 'package:torchinlane/src/commands/doctor_command.dart';
import 'package:torchinlane/src/commands/init_command.dart';
import 'package:torchinlane/src/commands/screenshots_command.dart';
import 'package:torchinlane/src/commands/uninstall_command.dart';
import 'package:torchinlane/src/commands/update_command.dart';
import 'package:torchinlane/src/shell/version_check.dart';

Future<void> main(List<String> arguments) async {
  await const VersionCheck().run();

  final runner = CommandRunner<int>(
    'torchinlane',
    'Automate Flutter releases, localized store content, credentials and signing with CLI or Studio.',
  )
    ..addCommand(InitCommand())
    ..addCommand(StoreCommand())
    ..addCommand(CredentialsCommand())
    ..addCommand(StudioCommand())
    ..addCommand(CiCommand())
    ..addCommand(SigningCommand())
    ..addCommand(DeployCommand())
    ..addCommand(BumpCommand())
    ..addCommand(DoctorCommand())
    ..addCommand(ChangelogCommand())
    ..addCommand(ScreenshotsCommand())
    ..addCommand(UpdateCommand())
    ..addCommand(UninstallCommand());

  try {
    final code = await runner.run(arguments);
    exit(code ?? 0);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exit(64);
  } catch (e) {
    stderr.writeln('torchinlane: $e');
    exit(1);
  }
}
