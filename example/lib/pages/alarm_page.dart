import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../support_menu.dart';
import '../i18n.dart';
import '../widgets/result_tile.dart';

/// 闹钟页：查询/全量设置/删除 演示（全量下发约束）。
class AlarmPage extends StatefulWidget {
  const AlarmPage({super.key, required this.capabilities});

  final DemoCapabilities capabilities;

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
      _log(
        '${demoTr('获取闹钟', 'Get alarms')} ✓ '
        '${demoTr('共', 'Total')} ${list.length}',
      );
      for (final a in list) {
        _log(
          '  #${a.alarmId} ${a.startHour.toString().padLeft(2, '0')}:'
          '${a.startMin.toString().padLeft(2, '0')} '
          '${a.isOpen ? demoTr('开', 'On') : demoTr('关', 'Off')} '
          'repeats=${a.repeats}',
        );
      }
    } on RwfitException catch (e) {
      _log('${demoTr('获取闹钟', 'Get alarms')} ✗ [${e.code}] ${e.message}');
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
        repeats: [0, 1, 1, 1, 1, 1, 0], // 周一~周五（index 0=周日）
      ),
      const Alarm(
        alarmId: 2,
        startHour: 22,
        startMin: 0,
        isOpen: true,
        repeats: [1, 1, 1, 1, 1, 1, 1],
      ),
    ];
    try {
      await _ring.setAlarm(alarms);
      _log(
        '${demoTr('设置闹钟', 'Set alarms')} ✓ '
        '${demoTr('下发', 'Sent')} ${alarms.length}',
      );
    } on RwfitException catch (e) {
      _log('${demoTr('设置闹钟', 'Set alarms')} ✗ [${e.code}] ${e.message}');
    }
  }

  Future<void> _toggleFirst() async {
    if (_alarms.isEmpty) {
      _log(demoTr('请先获取闹钟', 'Get alarms first'));
      return;
    }
    // 切换第一个闹钟的开关，全量下发
    final toggled = _alarms[0].copyWith(isOpen: !_alarms[0].isOpen);
    final newList = [toggled, ..._alarms.skip(1)];
    try {
      await _ring.setAlarm(newList);
      setState(() => _alarms = newList);
      _log(
        '${demoTr('切换闹钟', 'Toggle alarm')}#${toggled.alarmId} → '
        '${toggled.isOpen ? demoTr('开', 'On') : demoTr('关', 'Off')} ✓',
      );
    } on RwfitException catch (e) {
      _log('${demoTr('切换闹钟', 'Toggle alarm')} ✗ [${e.code}] ${e.message}');
    }
  }

  Future<void> _deleteAll() async {
    try {
      await _ring.deleteAllAlarm();
      setState(() => _alarms = []);
      _log('${demoTr('删除全部闹钟', 'Delete all alarms')} ✓');
    } on RwfitException catch (e) {
      _log('${demoTr('删除全部', 'Delete all')} ✗ [${e.code}] ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final supported = widget.capabilities.has(DemoCapabilityKey.alarm);
    return Scaffold(
      appBar: AppBar(title: Text(demoTr('闹钟', 'Alarms'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonal(
                  onPressed: supported ? _getAlarms : null,
                  child: Text(
                    supported
                        ? demoTr('获取闹钟', 'Get alarms')
                        : '${demoTr('获取闹钟', 'Get alarms')} '
                              '(${demoTr('不支持', 'Unsupported')})',
                  ),
                ),
                FilledButton.tonal(
                  onPressed: supported ? _setDemo : null,
                  child: Text(demoTr('设置示例闹钟', 'Set sample alarms')),
                ),
                FilledButton.tonal(
                  onPressed: supported ? _toggleFirst : null,
                  child: Text(demoTr('切换第1个开关', 'Toggle first alarm')),
                ),
                FilledButton.tonal(
                  onPressed: supported ? _deleteAll : null,
                  child: Text(demoTr('删除全部', 'Delete all')),
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
