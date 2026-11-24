import 'dart:io';

import 'package:flutter/material.dart';

import 'flasher.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BoxFlasher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0A84C6), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const Home(),
    );
  }
}

class Box {
  final String ip;
  String info = '';
  BoxState state = BoxState.idle;
  String status = 'Ожидает';
  bool selected = true;
  final List<String> log = [];
  Box(this.ip);
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final env = Env.detect();
  final ipCtl = TextEditingController();
  final boxes = <Box>[];
  Box? shown;
  bool scanning = false;
  bool force = false;
  final scanLog = <String>[];

  void addIp(String raw) {
    final ip = raw.trim();
    final ok = RegExp(r'^\d{1,3}(\.\d{1,3}){3}(:\d+)?$').hasMatch(ip);
    if (!ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Введите IP, например 192.168.1.50')));
      return;
    }
    if (boxes.any((b) => b.ip == ip)) return;
    setState(() {
      final b = Box(ip);
      boxes.add(b);
      shown = b;
    });
    ipCtl.clear();
  }

  Future<void> scan() async {
    if (env == null) return;
    setState(() {
      scanning = true;
      scanLog.clear();
    });
    final ips = await scanNetwork((m) => setState(() => scanLog.add(m)));
    for (final ip in ips) {
      if (boxes.any((b) => b.ip == ip)) continue;
      final b = Box(ip);
      final f = Flasher(env!, ip, (_) {});
      if (await f.connect(tries: 1)) {
        final model = await f.prop('ro.product.model');
        final golden = await f.prop('ro.box.golden') == '1';
        final fp = await f.prop('ro.build.fingerprint');
        b.info = model;
        if (golden) {
          b.status = 'Уже прошита';
          b.selected = false;
        } else if (fp != stockFingerprint) {
          b.status = 'Другая прошивка';
          b.selected = false;
          b.log.add('Сборка: $fp');
        } else {
          b.status = 'Можно прошивать';
        }
      } else {
        b.info = 'нет ответа ADB';
        b.status = 'Нет ADB';
        b.selected = false;
      }
      setState(() => boxes.add(b));
    }
    setState(() {
      scanning = false;
      scanLog.add('Найдено: ${ips.length}');
    });
  }

  Future<void> flash(Box b) async {
    if (env == null || b.state == BoxState.running) return;
    setState(() {
      b.state = BoxState.running;
      b.status = 'Прошивается…';
      b.log.clear();
    });
    final started = DateTime.now();
    final f = Flasher(env!, b.ip, (m) => setState(() => b.log.add(m)));
    String? err;
    try {
      err = await f.run(force: force);
    } catch (e) {
      err = 'Ошибка: $e';
    }
    final mins = DateTime.now().difference(started).inSeconds / 60;
    setState(() {
      if (err == null) {
        b.state = BoxState.done;
        b.status = 'Готово';
        b.log.add('✔ Готово за ${mins.toStringAsFixed(1)} мин');
      } else {
        b.state = BoxState.failed;
        b.status = 'Ошибка';
        b.log.add('✖ $err');
      }
    });
    _writeCsv(b, err, started);
  }

  void _writeCsv(Box b, String? err, DateTime started) {
    try {
      final f = File('${Env.exeDir}${Platform.pathSeparator}flash_log.csv');
      if (!f.existsSync()) f.writeAsStringSync('time;ip;model;result;error\n');
      final e = (err ?? '').replaceAll('\n', ' ').replaceAll(';', ',');
      f.writeAsStringSync(
          '${started.toIso8601String()};${b.ip};${b.info};${err == null ? 'OK' : 'FAIL'};$e\n',
          mode: FileMode.append);
    } catch (_) {}
  }

  Future<void> flashSelected() async {
    final list = boxes.where((b) => b.selected && b.state != BoxState.running).toList();
    await Future.wait(list.map(flash));
  }

  Color stateColor(BoxState s) => switch (s) {
        BoxState.idle => Colors.grey,
        BoxState.running => Colors.amber,
        BoxState.done => Colors.green,
        BoxState.failed => Colors.redAccent,
      };

  @override
  Widget build(BuildContext context) {
    if (env == null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'Не найдена папка «firmware» рядом с программой.\n\n'
              'Положите папку firmware (с файлом apply.sh) рядом с BoxFlasher '
              'и запустите программу снова.\n\nПапка программы: ${Env.exeDir}',
              style: const TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    final running = boxes.any((b) => b.state == BoxState.running);
    return Scaffold(
      appBar: AppBar(
        title: const Text('BoxFlasher · A95X R1'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
                child: Text('ADB: ${env!.adb}', style: const TextStyle(fontSize: 12))),
          ),
        ],
      ),
      body: Row(
        children: [
          SizedBox(
            width: 460,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: ipCtl,
                        decoration: const InputDecoration(
                          labelText: 'IP приставки',
                          hintText: '192.168.1.50',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: addIp,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                        onPressed: () => addIp(ipCtl.text), child: const Text('Добавить')),
                  ]),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: scanning ? null : scan,
                    icon: scanning
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.wifi_find),
                    label: Text(scanning ? 'Поиск…' : 'Найти приставки в сети'),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Card(
                      child: boxes.isEmpty
                          ? const Center(child: Text('Добавьте IP или найдите приставки'))
                          : ListView(
                              children: [
                                for (final b in boxes)
                                  ListTile(
                                    selected: shown == b,
                                    onTap: () => setState(() => shown = b),
                                    leading: Checkbox(
                                      value: b.selected,
                                      onChanged: (v) => setState(() => b.selected = v ?? false),
                                    ),
                                    title: Text(b.ip),
                                    subtitle: Text(b.info),
                                    trailing: Chip(
                                      label: Text(b.status),
                                      backgroundColor: stateColor(b.state).withValues(alpha: 0.25),
                                      side: BorderSide(color: stateColor(b.state)),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: force,
                    onChanged: (v) => setState(() => force = v ?? false),
                    title: const Text('Перепрошить, даже если уже прошита'),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                    onPressed: boxes.any((b) => b.selected) ? flashSelected : null,
                    icon: const Icon(Icons.system_update_alt),
                    label: Text(running ? 'Идёт прошивка…' : 'Прошить отмеченные'),
                  ),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shown == null ? 'Журнал' : 'Журнал: ${shown!.ip}',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black26,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        reverse: true,
                        child: SelectableText(
                          (shown?.log ?? scanLog).join('\n'),
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Прошивка: ${env!.firmware}', style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
