import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../support_menu.dart';
import '../i18n.dart';
import '../widgets/result_tile.dart';

/// 数据同步页：演示 syncAllHealthData + 完成标记/结果/完成事件监听。
class SyncPage extends StatefulWidget {
  const SyncPage({super.key, required this.capabilities});

  final DemoCapabilities capabilities;

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
        _log(
          '${demoTr('数据', 'Data')}[${r.type}]: ${r.data.length} '
          '${demoTr('条', 'items')}',
        );
      }),
    );
    _subs.add(
      _ring.onSyncFinish.listen((_) {
        setState(() => _syncing = false);
        _log('${demoTr('同步完成', 'Sync complete')} ✓');
      }),
    );
    _subs.add(
      _ring.onSyncError.listen((e) {
        setState(() => _syncing = false);
        _log('${demoTr('同步错误', 'Sync error')}: code=${e['code']}');
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
      _log(demoTr('同步指令已发送...', 'Sync command sent...'));
    } on RwfitException catch (e) {
      setState(() => _syncing = false);
      _log(
        '${demoTr('发送同步指令失败', 'Failed to start sync')}: '
        '[${e.code}] ${e.message}',
      );
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
      appBar: AppBar(title: Text(demoTr('数据同步', 'Data sync'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                LinearProgressIndicator(
                  value: _syncing ? null : (_progress == 100 ? 1 : 0),
                ),
                const SizedBox(height: 8),
                Text(
                  _syncing
                      ? demoTr('同步中...', 'Syncing...')
                      : (_progress == 100
                            ? demoTr('同步完成', 'Sync complete')
                            : demoTr('尚未同步', 'Not synced')),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed:
                      _syncing || !widget.capabilities.supportsAnyHealthData
                      ? null
                      : _startSync,
                  child: Text(
                    !widget.capabilities.supportsAnyHealthData
                        ? demoTr('当前设备无可同步数据', 'No supported data to sync')
                        : (_syncing
                              ? demoTr('同步中...', 'Syncing...')
                              : demoTr('开始同步', 'Start sync')),
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
