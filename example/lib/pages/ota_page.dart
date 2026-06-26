import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../widgets/result_tile.dart';

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
          _log('OTA 升级成功 ✓');
        } else {
          _log('OTA 升级失败: code=${r.code}');
        }
      }),
    );
  }

  void _log(String s) => setState(() => _results.insert(0, s));

  Future<void> _startOta() async {
    final path = _pathController.text.trim();
    if (path.isEmpty) {
      _log('请输入固件文件路径');
      return;
    }
    setState(() {
      _upgrading = true;
      _progress = 0;
    });
    try {
      await _ring.ringOta(path);
      _log('OTA 指令已发送...');
    } on RwfitException catch (e) {
      setState(() => _upgrading = false);
      _log('OTA 失败: [${e.code}] ${e.message}');
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
      appBar: AppBar(title: const Text('OTA 升级')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _pathController,
                  decoration: const InputDecoration(
                    labelText: '固件文件路径',
                    hintText: '/sdcard/Download/firmware.bin',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _progress),
                const SizedBox(height: 8),
                Text('进度: ${(_progress * 100).toStringAsFixed(1)}%'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _upgrading ? null : _startOta,
                  child: Text(_upgrading ? '升级中...' : '开始 OTA'),
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
