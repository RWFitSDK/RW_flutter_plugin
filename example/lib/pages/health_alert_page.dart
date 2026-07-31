import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../support_menu.dart';
import '../widgets/result_tile.dart';

/// 赞念开关与心率/血氧报警配置示例。
class HealthAlertPage extends StatefulWidget {
  const HealthAlertPage({super.key, required this.capabilities});

  final DemoCapabilities capabilities;

  @override
  State<HealthAlertPage> createState() => _HealthAlertPageState();
}

class _HealthAlertPageState extends State<HealthAlertPage> {
  final _ring = RwfitBle.instance;
  final _results = <String>[];
  StreamSubscription<HealthAlertEvent>? _alertSub;

  @override
  void initState() {
    super.initState();
    _alertSub = _ring.onHealthAlert.listen((event) {
      _log('健康报警: ${event.type.name}, value=${event.value}');
    });
  }

  void _log(String value) {
    if (!mounted) return;
    setState(() => _results.insert(0, value));
  }

  Future<void> _run(String label, Future<Object?> Function() action) async {
    try {
      final result = await action();
      _log('$label ✓ ${result ?? ''}');
    } on RwfitException catch (e) {
      _log('$label ✗ [${e.code}] ${e.message}');
    } catch (e) {
      _log('$label ✗ $e');
    }
  }

  Future<String> _toggleHeartRateAlert() async {
    final current = await _ring.getHeartRateAlert();
    final updated = current.copyWith(isOpen: !current.isOpen);
    await _ring.setHeartRateAlert(updated);
    return updated.isOpen ? '已开启' : '已关闭';
  }

  Future<String> _toggleBloodOxygenAlert() async {
    final current = await _ring.getBloodOxygenAlert();
    final updated = current.copyWith(isOpen: !current.isOpen);
    await _ring.setBloodOxygenAlert(updated);
    return updated.isOpen ? '已开启' : '已关闭';
  }

  @override
  void dispose() {
    _alertSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('赞念与健康报警')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _button(
                  '获取赞念开关',
                  () => _run('赞念开关', () async {
                    final enabled = await _ring.getMuslimCountEnabled();
                    return enabled ? '已开启' : '已关闭';
                  }),
                  enabled: widget.capabilities.has(
                    DemoCapabilityKey.muslimSwitch,
                  ),
                ),
                _button(
                  '开启赞念',
                  () => _run('开启赞念', () => _ring.setMuslimCountEnabled(true)),
                  enabled: widget.capabilities.has(
                    DemoCapabilityKey.muslimSwitch,
                  ),
                ),
                _button(
                  '关闭赞念',
                  () => _run('关闭赞念', () => _ring.setMuslimCountEnabled(false)),
                  enabled: widget.capabilities.has(
                    DemoCapabilityKey.muslimSwitch,
                  ),
                ),
                _button(
                  '获取心率报警',
                  () => _run('心率报警', () async {
                    final config = await _ring.getHeartRateAlert();
                    return 'open=${config.isOpen}, '
                        'high=${config.highThreshold}, '
                        'low=${config.lowThreshold ?? '不支持'}';
                  }),
                  enabled: widget.capabilities.has(
                    DemoCapabilityKey.heartRateAlert,
                  ),
                ),
                _button(
                  '切换心率报警',
                  () => _run('切换心率报警', _toggleHeartRateAlert),
                  enabled: widget.capabilities.has(
                    DemoCapabilityKey.heartRateAlert,
                  ),
                ),
                _button(
                  '获取血氧报警',
                  () => _run('血氧报警', () async {
                    final config = await _ring.getBloodOxygenAlert();
                    return 'open=${config.isOpen}, low=${config.lowThreshold}';
                  }),
                  enabled: widget.capabilities.has(
                    DemoCapabilityKey.bloodOxygenAlert,
                  ),
                ),
                _button(
                  '切换血氧报警',
                  () => _run('切换血氧报警', _toggleBloodOxygenAlert),
                  enabled: widget.capabilities.has(
                    DemoCapabilityKey.bloodOxygenAlert,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: ResultList(results: _results)),
        ],
      ),
    );
  }

  Widget _button(
    String label,
    VoidCallback onPressed, {
    required bool enabled,
  }) => FilledButton.tonal(
    onPressed: enabled ? onPressed : null,
    child: Text(
      enabled ? label : '$label(不支持)',
      style: const TextStyle(fontSize: 12),
    ),
  );
}
