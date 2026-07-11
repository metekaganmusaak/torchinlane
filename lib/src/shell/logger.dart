const _green = '\x1B[0;32m';
const _yellow = '\x1B[1;33m';
const _red = '\x1B[0;31m';
const _reset = '\x1B[0m';

class Logger {
  const Logger();

  void info(String message) => print('$_yellow$message$_reset');

  void success(String message) => print('$_green$message$_reset');

  void error(String message) => print('$_red$message$_reset');

  void plain(String message) => print(message);
}
