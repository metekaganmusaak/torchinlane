import 'dart:io';

import 'package:args/command_runner.dart';

import 'package:torchinlane/src/commands/bump_command.dart';
import 'package:torchinlane/src/commands/changelog_command.dart';
import 'package:torchinlane/src/commands/deploy_command.dart';
import 'package:torchinlane/src/commands/doctor_command.dart';
import 'package:torchinlane/src/commands/init_command.dart';
import 'package:torchinlane/src/commands/screenshots_command.dart';
import 'package:torchinlane/src/commands/uninstall_command.dart';
import 'package:torchinlane/src/commands/update_command.dart';

Future<void> main(List<String> arguments) async {
  final runner = CommandRunner<int>(
    'torchinlane',
    'Scaffold fastlane, deploy Flutter apps, translate changelogs, and generate store screenshot prompts.',
  )
    ..addCommand(InitCommand())
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
  }
}
