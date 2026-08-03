import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../support_menu.dart';
import '../i18n.dart';
import '../widgets/result_tile.dart';

/// 原始传感器采集、历史同步及睡眠实时状态示例。
class SensorRawPage extends StatefulWidget {
  const SensorRawPage({super.key, required this.capabilities});

  final DemoCapabilities capabilities;

  @override
  State<SensorRawPage> createState() => _SensorRawPageState();
}

class _SensorRawPageState extends State<SensorRawPage> {
  final _ring = RwfitBle.instance;
  final _results = <String>[];
  final _subs = <StreamSubscription>[];

  SensorRawSelection? _selection;
  SensorRawPacket? _latestPacket;
  int _packetCount = 0;
  bool _collecting = false;

  @override
  void initState() {
    super.initState();
    final supportedSelections = SensorRawSelection.values
        .where(widget.capabilities.supportsSensorSelection)
        .toList();
    _selection = supportedSelections.firstOrNull;
    _subs.add(
      _ring.onSensorRawData.listen((packet) {
        _packetCount++;
        _latestPacket = packet;
        if (packet.type == SensorRawDataType.sleep || _packetCount % 10 == 0) {
          if (mounted) setState(() {});
        }
      }),
    );
    _subs.add(
      _ring.onSensorRawStopped.listen((event) {
        _collecting = false;
        _log(
          '${demoTr('设备停止采集', 'Device stopped collection')}: '
          'reason=${event.reason}',
        );
      }),
    );
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

  Future<void> _start() async {
    final selection = _selection;
    if (selection == null) {
      throw StateError(
        demoTr('当前设备没有支持的原始传感器采集组合', 'No supported raw-sensor combination'),
      );
    }
    await _ring.controlSensorRaw(true, selection);
    if (mounted) setState(() => _collecting = true);
  }

  Future<void> _stop() async {
    final selection = _selection;
    if (selection == null) return;
    await _ring.controlSensorRaw(false, selection);
    if (mounted) setState(() => _collecting = false);
  }

  Future<String> _history() async {
    final packets = await _ring.getSensorRawHistory();
    final counts = <SensorRawDataType, int>{};
    for (final packet in packets) {
      counts.update(packet.type, (value) => value + 1, ifAbsent: () => 1);
    }
    return '${packets.length} ${demoTr('包', 'packets')} $counts';
  }

  String _packetSummary(SensorRawPacket? packet) {
    if (packet == null) {
      return demoTr('尚未收到数据', 'No data received yet');
    }
    return 'type=${packet.type.name}, seq=${packet.sequence ?? '-'}, '
        'ppg=${packet.ppg.length}, acc=${packet.acc.length}, '
        'red=${packet.ppgRed.length}, ir=${packet.ir.length}, '
        'sleep=${packet.sleep.length}';
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    final selection = _selection;
    if (_collecting && selection != null) {
      _ring.controlSensorRaw(false, selection);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final supportedSelections = SensorRawSelection.values
        .where(widget.capabilities.supportsSensorSelection)
        .toList();
    final supportsHistory = widget.capabilities.has(
      DemoCapabilityKey.sensorRawPpg,
    );
    final supportsSleep = widget.capabilities.has(
      DemoCapabilityKey.sensorRawSleep,
    );
    return Scaffold(
      appBar: AppBar(title: Text(demoTr('传感器原始数据', 'Raw sensor data'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<SensorRawSelection>(
                  initialValue: _selection,
                  decoration: InputDecoration(
                    labelText: demoTr('采集组合', 'Sensor combination'),
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    for (final value in supportedSelections)
                      DropdownMenuItem(
                        value: value,
                        child: Text('${value.name} (${value.value})'),
                      ),
                  ],
                  onChanged: _collecting
                      ? null
                      : (value) {
                          if (value != null) {
                            setState(() => _selection = value);
                          }
                        },
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: _collecting || _selection == null
                          ? null
                          : () => _run(
                              demoTr('开始采集', 'Start collection'),
                              _start,
                            ),
                      child: Text(
                        _selection == null
                            ? '${demoTr('开始采集', 'Start collection')} '
                                  '(${demoTr('不支持', 'Unsupported')})'
                            : demoTr('开始采集', 'Start collection'),
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: _collecting
                          ? () => _run(demoTr('停止采集', 'Stop collection'), _stop)
                          : null,
                      child: Text(demoTr('停止采集', 'Stop collection')),
                    ),
                    FilledButton.tonal(
                      onPressed: supportsHistory
                          ? () => _run(
                              demoTr('历史原始数据', 'Raw data history'),
                              _history,
                            )
                          : null,
                      child: Text(
                        supportsHistory
                            ? demoTr('同步历史数据', 'Sync history')
                            : '${demoTr('同步历史数据', 'Sync history')} '
                                  '(${demoTr('不支持', 'Unsupported')})',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('${demoTr('实时包数', 'Live packets')}: $_packetCount'),
                Text(_packetSummary(_latestPacket)),
                Text(
                  supportsSleep
                      ? demoTr(
                          '睡眠状态由设备自动推送，无需启动采集。',
                          'Sleep state is pushed automatically; collection is not required.',
                        )
                      : demoTr(
                          '当前设备不支持睡眠原始数据。',
                          'Raw sleep data is not supported.',
                        ),
                  style: const TextStyle(color: Colors.blueGrey),
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
}
