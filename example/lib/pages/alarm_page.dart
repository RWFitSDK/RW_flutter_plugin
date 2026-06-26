import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../widgets/result_tile.dart';

/// 闹钟页：查询/全量设置/删除 演示（全量下发约束）。
class AlarmPage extends StatefulWidget {
  const AlarmPage({super.key});

  @override
  State<AlarmPage> createState() => _AlarmPageState();
}

class _AlarmPageState extends State<AlarmPage> {
  final _ring = RwfitBle.instance;
  final _results = <String>[];
  List<Alarm> _alarms = [];

  void _log(String s) => setState(() => _results.insert(0, s));

  Future<void> _getAlarms() async {
    try {
      final list = await _ring.getAlarm();
      setState(() => _alarms = list);
      _log('获取闹钟 ✓ 共 ${list.length} 个');
      for (final a in list) {
        _log(
          '  #${a.alarmId} ${a.startHour.toString().padLeft(2, '0')}:${a.startMin.toString().padLeft(2, '0')} ${a.isOpen ? "开" : "关"} tag=${a.alarmTag} repeats=${a.repeats}',
        );
      }
    } on RwfitException catch (e) {
      _log('获取闹钟 ✗ [${e.code}] ${e.message}');
    }
  }

  Future<void> _setDemo() async {
    // 示例：下发两个闹钟
    final alarms = [
      const Alarm(
        alarmId: 1,
        startHour: 7,
        startMin: 30,
        isOpen: true,
        alarmTag: '起床',
        repeats: [1, 1, 1, 1, 1, 0, 0], // 周一~周五
      ),
      const Alarm(
        alarmId: 2,
        startHour: 22,
        startMin: 0,
        isOpen: true,
        alarmTag: '睡觉',
        repeats: [1, 1, 1, 1, 1, 1, 1],
      ),
    ];
    try {
      await _ring.setAlarm(alarms);
      _log('设置闹钟 ✓ 下发 ${alarms.length} 个');
    } on RwfitException catch (e) {
      _log('设置闹钟 ✗ [${e.code}] ${e.message}');
    }
  }

  Future<void> _toggleFirst() async {
    if (_alarms.isEmpty) {
      _log('请先获取闹钟');
      return;
    }
    // 切换第一个闹钟的开关，全量下发
    final toggled = _alarms[0].copyWith(isOpen: !_alarms[0].isOpen);
    final newList = [toggled, ..._alarms.skip(1)];
    try {
      await _ring.setAlarm(newList);
      setState(() => _alarms = newList);
      _log('切换闹钟#${toggled.alarmId} → ${toggled.isOpen ? "开" : "关"} ✓');
    } on RwfitException catch (e) {
      _log('切换闹钟 ✗ [${e.code}] ${e.message}');
    }
  }

  Future<void> _deleteAll() async {
    try {
      await _ring.deleteAllAlarm();
      setState(() => _alarms = []);
      _log('删除全部闹钟 ✓');
    } on RwfitException catch (e) {
      _log('删除全部 ✗ [${e.code}] ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('闹钟')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: _getAlarms,
                  child: const Text('获取闹钟'),
                ),
                FilledButton.tonal(
                  onPressed: _setDemo,
                  child: const Text('设置示例闹钟'),
                ),
                FilledButton.tonal(
                  onPressed: _toggleFirst,
                  child: const Text('切换第1个开关'),
                ),
                FilledButton.tonal(
                  onPressed: _deleteAll,
                  child: const Text('删除全部'),
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
