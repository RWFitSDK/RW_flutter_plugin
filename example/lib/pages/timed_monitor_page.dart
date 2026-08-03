import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../support_menu.dart';
import '../i18n.dart';
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
        '$label → open=${c.isOpen} ${c.startHour}:${c.startMin}-'
        '${c.endHour}:${c.endMin} '
        '${demoTr('间隔', 'interval')}=${c.duration}min',
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
      _log('$label ${demoTr('设置成功', 'set successfully')} ✓');
    } on RwfitException catch (e) {
      _log('$label ✗ [${e.code}] ${e.message}');
    } catch (e) {
      _log('$label ✗ $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(demoTr('全天检测', 'All-day monitoring'))),
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
                    demoTr('心率', 'Heart rate'),
                    _ring.getTimedHeartRate,
                    _ring.setTimedHeartRate,
                    duration: 30,
                    enabled: widget.capabilities.has(
                      DemoCapabilityKey.heartRate,
                    ),
                  ),
                  _row(
                    demoTr('血氧', 'SpO₂'),
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
                    demoTr('压力', 'Stress'),
                    _ring.getTimedStress,
                    _ring.setTimedStress,
                    duration: 60,
                    enabled: widget.capabilities.has(
                      DemoCapabilityKey.pressure,
                    ),
                  ),
                  _row(
                    demoTr('血糖', 'Blood glucose'),
                    _ring.getTimedBloodSugar,
                    _ring.setTimedBloodSugar,
                    duration: 60,
                    enabled: widget.capabilities.has(
                      DemoCapabilityKey.bloodSugar,
                    ),
                  ),
                  _row(
                    demoTr('血压', 'Blood pressure'),
                    _ring.getTimedBloodPressure,
                    _ring.setTimedBloodPressure,
                    duration: 60,
                    enabled: widget.capabilities.has(
                      DemoCapabilityKey.bloodPressure,
                    ),
                  ),
                  _row(
                    demoTr('体温', 'Temperature'),
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
            onPressed: enabled
                ? () => _get('${demoTr('获取', 'Get')} $label', getter)
                : null,
            child: Text(demoTr('获取', 'Get')),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: enabled
                ? () => _set('${demoTr('设置', 'Set')} $label', duration, setter)
                : null,
            child: Text(demoTr('设置', 'Set')),
          ),
          if (!enabled) ...[
            const SizedBox(width: 8),
            Text(
              demoTr('不支持', 'Unsupported'),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
