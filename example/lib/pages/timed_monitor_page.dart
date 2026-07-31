import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../support_menu.dart';
import '../widgets/result_tile.dart';

/// 定时监测页：7 项全天健康检测 + PPG 配置 get/set 演示。
class TimedMonitorPage extends StatefulWidget {
  const TimedMonitorPage({super.key, required this.capabilities});

  final DemoCapabilities capabilities;

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

  Future<void> _set(
    String label,
    int duration,
    Future<void> Function(TimedConfig) fn,
  ) async {
    // 协议时间范围固定全天；检测间隔由各功能支持范围决定。
    final config = TimedConfig(
      isOpen: true,
      duration: duration,
      startHour: 0,
      startMin: 0,
      endHour: 23,
      endMin: 59,
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
                  _row(
                    '心率',
                    _ring.getTimedHeartRate,
                    _ring.setTimedHeartRate,
                    duration: 30,
                    enabled: widget.capabilities.has(
                      DemoCapabilityKey.heartRate,
                    ),
                  ),
                  _row(
                    '血氧',
                    _ring.getTimedBloodOxygen,
                    _ring.setTimedBloodOxygen,
                    duration: 60,
                    enabled: widget.capabilities.has(
                      DemoCapabilityKey.bloodOxygen,
                    ),
                  ),
                  _row(
                    'HRV',
                    _ring.getTimedHRV,
                    _ring.setTimedHRV,
                    duration: 60,
                    enabled: widget.capabilities.has(DemoCapabilityKey.hrv),
                  ),
                  _row(
                    '压力',
                    _ring.getTimedStress,
                    _ring.setTimedStress,
                    duration: 60,
                    enabled: widget.capabilities.has(
                      DemoCapabilityKey.pressure,
                    ),
                  ),
                  _row(
                    '血糖',
                    _ring.getTimedBloodSugar,
                    _ring.setTimedBloodSugar,
                    duration: 60,
                    enabled: widget.capabilities.has(
                      DemoCapabilityKey.bloodSugar,
                    ),
                  ),
                  _row(
                    '血压',
                    _ring.getTimedBloodPressure,
                    _ring.setTimedBloodPressure,
                    duration: 60,
                    enabled: widget.capabilities.has(
                      DemoCapabilityKey.bloodPressure,
                    ),
                  ),
                  _row(
                    '体温',
                    _ring.getTimedBodyTemperature,
                    _ring.setTimedBodyTemperature,
                    duration: 30,
                    enabled: widget.capabilities.has(
                      DemoCapabilityKey.temperatureMonitoring,
                    ),
                  ),
                  _row(
                    'PPG',
                    _ring.getTimedPPG,
                    _ring.setTimedPPG,
                    duration: 30,
                    enabled: widget.capabilities.has(
                      DemoCapabilityKey.ppgMonitoring,
                    ),
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
    Future<void> Function(TimedConfig) setter, {
    required int duration,
    required bool enabled,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 48, child: Text(label)),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: enabled ? () => _get('获取$label', getter) : null,
            child: const Text('获取'),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: enabled
                ? () => _set('设置$label', duration, setter)
                : null,
            child: const Text('设置'),
          ),
          if (!enabled) ...[
            const SizedBox(width: 8),
            const Text(
              '不支持',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
