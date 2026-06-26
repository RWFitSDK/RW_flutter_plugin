import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../widgets/result_tile.dart';

/// 全天检测页：6 项（心率/血氧/HRV/压力/血糖/血压）get/set 演示。
class TimedMonitorPage extends StatefulWidget {
  const TimedMonitorPage({super.key});

  @override
  State<TimedMonitorPage> createState() => _TimedMonitorPageState();
}

class _TimedMonitorPageState extends State<TimedMonitorPage> {
  final _ring = RwfitBle.instance;
  final _results = <String>[];

  void _log(String s) => setState(() => _results.insert(0, s));

  Future<void> _get(String label, Future<TimedConfig> Function() fn) async {
    try {
      final c = await fn();
      _log(
        '$label → open=${c.isOpen} ${c.startHour}:${c.startMin}-${c.endHour}:${c.endMin} 间隔${c.duration}min',
      );
    } on RwfitException catch (e) {
      _log('$label ✗ [${e.code}] ${e.message}');
    } catch (e) {
      _log('$label ✗ $e');
    }
  }

  Future<void> _set(String label, Future<void> Function(TimedConfig) fn) async {
    // 示例：开启，每 30 分钟检测一次，8:00-22:00
    final config = const TimedConfig(
      isOpen: true,
      duration: 30,
      startHour: 8,
      startMin: 0,
      endHour: 22,
      endMin: 0,
    );
    try {
      await fn(config);
      _log('$label 设置成功 ✓');
    } on RwfitException catch (e) {
      _log('$label ✗ [${e.code}] ${e.message}');
    } catch (e) {
      _log('$label ✗ $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('全天检测')),
      body: Column(
        children: [
          Expanded(
            flex: 0,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _row('心率', _ring.getTimedHeartRate, _ring.setTimedHeartRate),
                  _row(
                    '血氧',
                    _ring.getTimedBloodOxygen,
                    _ring.setTimedBloodOxygen,
                  ),
                  _row('HRV', _ring.getTimedHRV, _ring.setTimedHRV),
                  _row('压力', _ring.getTimedStress, _ring.setTimedStress),
                  _row(
                    '血糖',
                    _ring.getTimedBloodSugar,
                    _ring.setTimedBloodSugar,
                  ),
                  _row(
                    '血压',
                    _ring.getTimedBloodPressure,
                    _ring.setTimedBloodPressure,
                  ),
                ],
              ),
            ),
          ),
          const Divider(),
          Expanded(child: ResultList(results: _results)),
        ],
      ),
    );
  }

  Widget _row(
    String label,
    Future<TimedConfig> Function() getter,
    Future<void> Function(TimedConfig) setter,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 48, child: Text(label)),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: () => _get('获取$label', getter),
            child: const Text('获取'),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: () => _set('设置$label', setter),
            child: const Text('设置'),
          ),
        ],
      ),
    );
  }
}
