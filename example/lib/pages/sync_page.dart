import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../widgets/result_tile.dart';

/// 数据同步页：演示 syncAllHealthData + 进度/结果/完成事件监听。
class SyncPage extends StatefulWidget {
  const SyncPage({super.key});

  @override
  State<SyncPage> createState() => _SyncPageState();
}

class _SyncPageState extends State<SyncPage> {
  final _ring = RwfitBle.instance;
  final _subs = <StreamSubscription>[];
  final _results = <String>[];
  double _progress = 0;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _subs.add(
      _ring.onSyncProgress.listen((p) {
        setState(() => _progress = p);
      }),
    );
    _subs.add(
      _ring.onSyncResult.listen((r) {
        _log('数据[${r.type}]: ${r.data.length} 条');
      }),
    );
    _subs.add(
      _ring.onSyncFinish.listen((_) {
        setState(() => _syncing = false);
        _log('同步完成 ✓');
      }),
    );
    _subs.add(
      _ring.onSyncError.listen((e) {
        setState(() => _syncing = false);
        _log('同步错误: code=${e['code']}');
      }),
    );
  }

  void _log(String s) => setState(() => _results.insert(0, s));

  Future<void> _startSync() async {
    setState(() {
      _syncing = true;
      _progress = 0;
    });
    try {
      await _ring.syncAllHealthData();
      _log('同步指令已发送...');
    } on RwfitException catch (e) {
      setState(() => _syncing = false);
      _log('发送同步指令失败: [${e.code}] ${e.message}');
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('数据同步')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                LinearProgressIndicator(value: _progress / 100),
                const SizedBox(height: 8),
                Text('进度: ${_progress.toStringAsFixed(0)}%'),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _syncing ? null : _startSync,
                  child: Text(_syncing ? '同步中...' : '开始同步'),
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
