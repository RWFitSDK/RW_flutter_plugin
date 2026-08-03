import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../widgets/result_tile.dart';
import '../i18n.dart';

/// OTA 升级页：选固件路径 → 升级 → 进度/完成事件监听。
class OtaPage extends StatefulWidget {
  const OtaPage({super.key});

  @override
  State<OtaPage> createState() => _OtaPageState();
}

class _OtaPageState extends State<OtaPage> {
  final _ring = RwfitBle.instance;
  final _subs = <StreamSubscription>[];
  final _results = <String>[];
  final _pathController = TextEditingController();
  double _progress = 0;
  bool _upgrading = false;

  @override
  void initState() {
    super.initState();
    _subs.add(
      _ring.onOtaProgress.listen((p) {
        setState(() => _progress = p);
      }),
    );
    _subs.add(
      _ring.onOtaFinish.listen((r) {
        setState(() => _upgrading = false);
        if (r.success) {
          _log('${demoTr('OTA 升级成功', 'OTA upgrade succeeded')} ✓');
        } else {
          _log('${demoTr('OTA 升级失败', 'OTA upgrade failed')}: code=${r.code}');
        }
      }),
    );
  }

  void _log(String s) => setState(() => _results.insert(0, s));

  Future<void> _startOta() async {
    final path = _pathController.text.trim();
    if (path.isEmpty) {
      _log(demoTr('请输入固件文件路径', 'Enter a firmware file path'));
      return;
    }
    setState(() {
      _upgrading = true;
      _progress = 0;
    });
    try {
      await _ring.ringOta(path);
      _log(demoTr('OTA 指令已发送...', 'OTA command sent...'));
    } on RwfitException catch (e) {
      setState(() => _upgrading = false);
      _log('${demoTr('OTA 失败', 'OTA failed')}: [${e.code}] ${e.message}');
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(demoTr('OTA 升级', 'OTA upgrade'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _pathController,
                  decoration: InputDecoration(
                    labelText: demoTr('固件文件路径', 'Firmware file path'),
                    hintText: '/sdcard/Download/firmware.bin',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 8),
                Text(
                  '${demoTr('进度', 'Progress')}: '
                  '${(_progress * 100).toStringAsFixed(1)}%',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _upgrading ? null : _startOta,
                  child: Text(
                    _upgrading
                        ? demoTr('升级中...', 'Upgrading...')
                        : demoTr('开始 OTA', 'Start OTA'),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(child: ResultList(results: _results)),
        ],
      ),
    );
  }
}
