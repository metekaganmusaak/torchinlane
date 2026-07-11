import 'dart:io';

String ask(String question, {String? defaultValue}) {
  final suffix = defaultValue != null ? ' [$defaultValue]' : '';
  stdout.write('$question$suffix: ');
  final input = stdin.readLineSync()?.trim() ?? '';
  if (input.isEmpty && defaultValue != null) return defaultValue;
  return input;
}

bool askYesNo(String question, {bool defaultValue = false}) {
  final hint = defaultValue ? 'Y/n' : 'y/N';
  while (true) {
    stdout.write('$question ($hint): ');
    final input = stdin.readLineSync()?.trim().toLowerCase() ?? '';
    if (input.isEmpty) return defaultValue;
    if (input == 'y' || input == 'yes') return true;
    if (input == 'n' || input == 'no') return false;
    stdout.writeln('Please answer y or n.');
  }
}

String askChoice(String question, List<String> options) {
  stdout.writeln(question);
  for (var i = 0; i < options.length; i++) {
    stdout.writeln('  ${i + 1}) ${options[i]}');
  }
  while (true) {
    stdout.write('Choice: ');
    final input = stdin.readLineSync()?.trim() ?? '';
    final index = int.tryParse(input);
    if (index != null && index >= 1 && index <= options.length) {
      return options[index - 1];
    }
    stdout.writeln('Invalid choice.');
  }
}
