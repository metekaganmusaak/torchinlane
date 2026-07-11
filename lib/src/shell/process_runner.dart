import 'dart:io';

class ProcessResult2 {
  ProcessResult2(this.exitCode);
  final int exitCode;
  bool get success => exitCode == 0;
}

/// Runs [executable] with [arguments], streaming stdout/stderr live to the
/// console. Returns the process exit code.
Future<ProcessResult2> runStreamed(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    runInShell: true,
  );
  process.stdout.transform(SystemEncoding().decoder).listen(stdout.write);
  process.stderr.transform(SystemEncoding().decoder).listen(stderr.write);
  final code = await process.exitCode;
  return ProcessResult2(code);
}
