import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Stock firmware the golden image was built for. Anything else is refused.
const stockFingerprint =
    'Android/A95X_R1_RTL/A95X_R1_RTL:6.0.1/MXC89L/xfwu02222034:userdebug/test-keys';

const remoteDir = '/data/local/tmp/golden';

enum BoxState { idle, running, done, failed }

/// Finds adb and the firmware folder next to the executable.
class Env {
  final String adb;
  final String firmware;
  Env(this.adb, this.firmware);

  static String get exeDir {
    final exe = File(Platform.resolvedExecutable);
    var dir = exe.parent;
    // macOS: .../BoxFlasher.app/Contents/MacOS/box_flasher -> folder holding the .app
    if (Platform.isMacOS) {
      dir = dir.parent.parent.parent;
    }
    return dir.path;
  }

  static Env? detect() {
    final base = exeDir;
    final sep = Platform.pathSeparator;
    final candidatesAdb = <String>[
      if (Platform.isWindows) '$base${sep}adb${sep}adb.exe',
      if (!Platform.isWindows) '$base${sep}adb${sep}adb',
      if (Platform.isMacOS)
        '${Platform.environment['HOME']}/Library/Android/sdk/platform-tools/adb',
    ];
    final adb = candidatesAdb.firstWhere((p) => File(p).existsSync(),
        orElse: () => Platform.isWindows ? 'adb.exe' : 'adb');
    final candidatesFw = <String>[
      '$base${sep}firmware',
      if (Platform.environment['BOX_FIRMWARE'] != null)
        Platform.environment['BOX_FIRMWARE']!,
    ];
    final fw = candidatesFw.firstWhere(
        (p) => File('$p${sep}apply.sh').existsSync(),
        orElse: () => '');
    if (fw.isEmpty) return null;
    return Env(adb, fw);
  }
}

class CmdResult {
  final int code;
  final String out;
  CmdResult(this.code, this.out);
  bool get ok => code == 0;
}

/// Flashes one box at [ip] with the golden firmware.
class Flasher {
  final Env env;
  final String ip;
  final void Function(String) log;
  Flasher(this.env, this.ip, this.log);

  String get serial => ip.contains(':') ? ip : '$ip:5555';

  Future<CmdResult> adb(List<String> args,
      {Duration timeout = const Duration(minutes: 2)}) async {
    try {
      final p = await Process.start(env.adb, args, runInShell: false);
      final out = StringBuffer();
      final f1 = p.stdout.transform(utf8.decoder).forEach(out.write);
      final f2 = p.stderr.transform(utf8.decoder).forEach(out.write);
      final code = await p.exitCode.timeout(timeout, onTimeout: () {
        p.kill();
        return -1;
      });
      await Future.wait([f1, f2]).timeout(const Duration(seconds: 5),
          onTimeout: () => <void>[]);
      return CmdResult(code, out.toString().replaceAll('\r', '').trim());
    } catch (e) {
      return CmdResult(-2, '$e');
    }
  }

  Future<CmdResult> sh(String cmd, {Duration timeout = const Duration(minutes: 2)}) =>
      adb(['-s', serial, 'shell', cmd], timeout: timeout);

  Future<String> prop(String name) async => (await sh('getprop $name')).out.trim();

  Future<bool> connect({int tries = 5}) async {
    for (var i = 0; i < tries; i++) {
      await adb(['disconnect', serial], timeout: const Duration(seconds: 10));
      final r = await adb(['connect', serial], timeout: const Duration(seconds: 15));
      if (r.out.contains('connected to')) {
        final st = await adb(['-s', serial, 'get-state'],
            timeout: const Duration(seconds: 10));
        if (st.out.trim() == 'device') return true;
      }
      await Future.delayed(const Duration(seconds: 3));
    }
    return false;
  }

  Future<bool> waitBoot(Duration limit) async {
    final end = DateTime.now().add(limit);
    while (DateTime.now().isBefore(end)) {
      if (await connect(tries: 1)) {
        if (await prop('sys.boot_completed') == '1') return true;
      }
      await Future.delayed(const Duration(seconds: 5));
    }
    return false;
  }

  /// Returns null on success, or an error message.
  Future<String?> run({bool force = false}) async {
    log('Подключение к $serial…');
    if (!await connect()) return 'Нет связи по ADB (порт 5555). Приставка включена и в сети?';

    final model = await prop('ro.product.model');
    final fp = await prop('ro.build.fingerprint');
    log('Модель: $model');
    if (fp != stockFingerprint) {
      return 'Другая прошивка, не трогаю:\n$fp';
    }
    if (await prop('ro.box.golden') == '1' && !force) {
      return 'Уже прошита (ro.box.golden=1). Включите «Перепрошить», если нужно заново.';
    }
    final su = await sh('su -c id');
    if (!su.out.contains('uid=0')) return 'Нет root (su): ${su.out}';

    log('Копирование прошивки на приставку…');
    await sh('rm -rf $remoteDir');
    final push = await adb(['-s', serial, 'push', env.firmware, remoteDir],
        timeout: const Duration(minutes: 30));
    if (!push.ok) return 'Ошибка копирования: ${push.out}';
    log(push.out.split('\n').last);

    log('Запись системы…');
    final apply = await sh('su -c "sh $remoteDir/apply.sh"',
        timeout: const Duration(minutes: 15));
    for (final l in apply.out.split('\n')) {
      if (l.trim().isNotEmpty) log('  $l');
    }
    if (!apply.out.contains('DONE')) return 'Скрипт apply.sh не завершился';

    log('Сброс до заводских и перезагрузка…');
    await sh('su -c "mkdir -p /cache/recovery; '
        'echo --wipe_data > /cache/recovery/command; '
        'echo --locale=ru_RU >> /cache/recovery/command; sync; reboot recovery"',
        timeout: const Duration(seconds: 30));
    await adb(['disconnect', serial], timeout: const Duration(seconds: 10));
    await Future.delayed(const Duration(seconds: 60));

    log('Ожидание загрузки (до 10 минут)…');
    if (!await waitBoot(const Duration(minutes: 10))) {
      return 'Приставка не загрузилась за 10 минут. Проверьте экран; IP мог смениться.';
    }
    await Future.delayed(const Duration(seconds: 15));

    log('Проверка…');
    if (await prop('ro.box.golden') != '1') return 'После загрузки нет отметки прошивки';
    final focus = await sh('dumpsys activity activities | grep -m1 mFocusedActivity');
    final crashes = await sh('logcat -d | grep -c "FATAL EXCEPTION"');
    log('Экран: ${focus.out.contains('com.box.launcher') ? 'BoxLauncher' : focus.out}');
    log('Падений после загрузки: ${crashes.out}');
    if (!focus.out.contains('com.box.launcher')) {
      return 'Загрузилась, но на экране не BoxLauncher';
    }
    return null;
  }
}

/// Scans the local /24 networks for hosts with ADB port 5555 open.
Future<List<String>> scanNetwork(void Function(String) log) async {
  final prefixes = <String>{};
  for (final ni in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
    for (final a in ni.addresses) {
      if (a.isLoopback) continue;
      final p = a.address.split('.');
      if (p.length == 4 && !a.address.startsWith('169.254')) {
        prefixes.add('${p[0]}.${p[1]}.${p[2]}');
      }
    }
  }
  final found = <String>[];
  for (final pre in prefixes) {
    log('Поиск в сети $pre.0/24…');
    final futures = <Future>[];
    for (var i = 1; i < 255; i++) {
      final ip = '$pre.$i';
      futures.add(Socket.connect(ip, 5555, timeout: const Duration(milliseconds: 800))
          .then((s) {
        s.destroy();
        found.add(ip);
      }).catchError((_) {}));
    }
    await Future.wait(futures);
  }
  found.sort((a, b) => int.parse(a.split('.').last).compareTo(int.parse(b.split('.').last)));
  return found;
}
