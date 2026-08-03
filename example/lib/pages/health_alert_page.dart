import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../support_menu.dart';
import '../i18n.dart';
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
      _log(
        '${demoTr('健康报警', 'Health alert')}: '
        '${event.type.name}, value=${event.value}',
      );
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
    return updated.isOpen
        ? demoTr('已开启', 'Enabled')
        : demoTr('已关闭', 'Disabled');
  }

  Future<String> _toggleBloodOxygenAlert() async {
    final current = await _ring.getBloodOxygenAlert();
    final updated = current.copyWith(isOpen: !current.isOpen);
    await _ring.setBloodOxygenAlert(updated);
    return updated.isOpen
        ? demoTr('已开启', 'Enabled')
        : demoTr('已关闭', 'Disabled');
  }

  @override
  void dispose() {
    _alertSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(demoTr('赞念与健康报警', 'Prayer & health alerts'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _button(
                  demoTr('获取赞念开关', 'Get prayer count setting'),
                  () => _run(demoTr('赞念开关', 'Prayer count'), () async {
                    final enabled = await _ring.getMuslimCountEnabled();
                    return enabled
                        ? demoTr('已开启', 'Enabled')
                        : demoTr('已关闭', 'Disabled');
                  }),
                  enabled: widget.capabilities.has(
                    DemoCapabilityKey.muslimSwitch,
                  ),
                ),
                _button(
                  demoTr('开启赞念', 'Enable prayer count'),
                  () => _run(
                    demoTr('开启赞念', 'Enable prayer count'),
                    () => _ring.setMuslimCountEnabled(true),
                  ),
                  enabled: widget.capabilities.has(
                    DemoCapabilityKey.muslimSwitch,
                  ),
                ),
                _button(
                  demoTr('关闭赞念', 'Disable prayer count'),
                  () => _run(
                    demoTr('关闭赞念', 'Disable prayer count'),
                    () => _ring.setMuslimCountEnabled(false),
                  ),
                  enabled: widget.capabilities.has(
                    DemoCapabilityKey.muslimSwitch,
                  ),
                ),
                _button(
                  demoTr('获取心率报警', 'Get heart-rate alert'),
                  () => _run(demoTr('心率报警', 'Heart-rate alert'), () async {
                    final config = await _ring.getHeartRateAlert();
                    return 'open=${config.isOpen}, '
                        'high=${config.highThreshold}, '
                        'low=${config.lowThreshold ?? demoTr('不支持', 'Unsupported')}';
                  }),
                  enabled: widget.capabilities.has(
                    DemoCapabilityKey.heartRateAlert,
                  ),
                ),
                _button(
                  demoTr('切换心率报警', 'Toggle heart-rate alert'),
                  () => _run(
                    demoTr('切换心率报警', 'Toggle heart-rate alert'),
                    _toggleHeartRateAlert,
                  ),
                  enabled: widget.capabilities.has(
                    DemoCapabilityKey.heartRateAlert,
                  ),
                ),
                _button(
                  demoTr('获取血氧报警', 'Get SpO₂ alert'),
                  () => _run(demoTr('血氧报警', 'SpO₂ alert'), () async {
                    final config = await _ring.getBloodOxygenAlert();
                    return 'open=${config.isOpen}, low=${config.lowThreshold}';
                  }),
                  enabled: widget.capabilities.has(
                    DemoCapabilityKey.bloodOxygenAlert,
                  ),
                ),
                _button(
                  demoTr('切换血氧报警', 'Toggle SpO₂ alert'),
                  () => _run(
                    demoTr('切换血氧报警', 'Toggle SpO₂ alert'),
                    _toggleBloodOxygenAlert,
                  ),
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
      enabled ? label : '$label (${demoTr('不支持', 'Unsupported')})',
      style: const TextStyle(fontSize: 12),
    ),
  );
}
