// Console runner for the same flashing logic the app uses.
// Usage: dart run bin/flash_cli.dart <firmware_dir> <adb> <ip> [--force]
import 'dart:io';

import 'package:box_flasher/flasher.dart';

Future<void> main(List<String> args) async {
  if (args.length < 3) {
    stderr.writeln('usage: flash_cli <firmware_dir> <adb> <ip> [--force]');
    exit(2);
  }
  final env = Env(args[1], args[0]);
  final f = Flasher(env, args[2], (m) => stdout.writeln('[${DateTime.now().toIso8601String().substring(11, 19)}] $m'));
  final t = DateTime.now();
  final err = await f.run(force: args.contains('--force'));
  final mins = DateTime.now().difference(t).inSeconds / 60;
  if (err == null) {
    stdout.writeln('OK in ${mins.toStringAsFixed(1)} min');
  } else {
    stdout.writeln('FAIL: $err');
    exit(1);
  }
}
