import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../support_menu.dart';
import '../widgets/result_tile.dart';

/// 设备控制页：找设备/关机/拍照/LED/佩戴方向/振动/亮屏/HID。
class ControlPage extends StatefulWidget {
  const ControlPage({super.key, required this.capabilities});

  final DemoCapabilities capabilities;

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  final _ring = RwfitBle.instance;
  final _results = <String>[];
  final _subs = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    _subs.add(
      _ring.onTouchEvent.listen((e) {
        _log(
          '触摸/音乐事件: ${e.action.name} '
          '(key=${e.keyType}, touch=${e.touchType})',
        );
      }),
    );
    _subs.add(
      _ring.onCallControl.listen((e) {
        _log('来电控制事件: ${e.action?.name ?? 'unknown'} (raw=${e.rawValue})');
      }),
    );
    _subs.add(
      _ring.onHeartRateCalibration.listen((e) {
        _log(
          '心率校正: mode=0x${e.testMode.toRadixString(16)} '
          'result=${e.result} ${e.isCalibrating ? '校正中' : '已完成'}',
        );
      }),
    );
  }

  void _log(String s) => setState(() => _results.insert(0, s));

  bool _supports(String key) => widget.capabilities.has(key);

  Future<void> _run(String label, Future<dynamic> Function() fn) async {
    try {
      final r = await fn();
      _log('$label ✓ ${r ?? ''}');
    } on RwfitException catch (e) {
      _log('$label ✗ [${e.code}] ${e.message}');
    } catch (e) {
      _log('$label ✗ $e');
    }
  }

  @override
  void dispose() {
    for (final sub in _subs) {
      sub.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设备控制')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _btn(
                  '找设备',
                  () => _run('找设备', _ring.findDevice),
                  enabled: _supports(DemoCapabilityKey.findDevice),
                ),
                _btn(
                  '关机',
                  () => _run('关机', _ring.powerOff),
                  enabled: _supports(DemoCapabilityKey.powerOff),
                ),
                _btn(
                  '恢复出厂',
                  () => _run('恢复出厂', _ring.factoryReset),
                  enabled: _supports(DemoCapabilityKey.factoryReset),
                ),
                _btn(
                  '进拍照模式',
                  () => _run('进拍照', () => _ring.controlPhoto(1)),
                  enabled: _supports(DemoCapabilityKey.takePhoto),
                ),
                _btn(
                  '退拍照模式',
                  () => _run('退拍照', () => _ring.controlPhoto(0)),
                  enabled: _supports(DemoCapabilityKey.takePhoto),
                ),
                _btn(
                  '来电接听(Android)',
                  () => _run(
                    '来电接听',
                    () => _ring.controlPhone(CallControlAction.answer),
                  ),
                  enabled: Platform.isAndroid,
                ),
                _btn(
                  '来电拒接(Android)',
                  () => _run(
                    '来电拒接',
                    () => _ring.controlPhone(CallControlAction.reject),
                  ),
                  enabled: Platform.isAndroid,
                ),
                _btn(
                  '获取LED',
                  () => _run('LED', () async {
                    final l = await _ring.getRingLedLevel();
                    return 'open=${l.isOpen} level=${l.lcdLevel}';
                  }),
                  enabled: _supports(DemoCapabilityKey.ledLight),
                ),
                _btn(
                  'LED开L2',
                  () => _run(
                    '设LED',
                    () => _ring.setRingLedLevel(
                      const LedLevel(isOpen: true, lcdLevel: 2),
                    ),
                  ),
                  enabled: _supports(DemoCapabilityKey.ledLight),
                ),
                _btn(
                  '获取佩戴方向',
                  () => _run('佩戴', () async {
                    final r = await _ring.getRingWearDir();
                    return r ? '右手' : '左手';
                  }),
                  enabled: _supports(DemoCapabilityKey.wearDirection),
                ),
                _btn(
                  '设右手',
                  () => _run('设右手', () => _ring.setRingWearHand(true)),
                  enabled: _supports(DemoCapabilityKey.wearDirection),
                ),
                _btn(
                  '设左手',
                  () => _run('设左手', () => _ring.setRingWearHand(false)),
                  enabled: _supports(DemoCapabilityKey.wearDirection),
                ),
                _btn(
                  '获取振动',
                  () => _run('振动', () async {
                    final v = await _ring.getVibrationCount();
                    return 'count=${v.count} level=${v.level}';
                  }),
                  enabled: _supports(DemoCapabilityKey.vibrationLevel),
                ),
                _btn(
                  '设振动',
                  () => _run(
                    '设振动',
                    () => _ring.setVibrationCount(
                      const VibrationConfig(count: 3, level: 2),
                    ),
                  ),
                  enabled: _supports(DemoCapabilityKey.vibrationLevel),
                ),
                _btn(
                  '获取振动间隔',
                  () => _run('振动间隔', () async {
                    final interval = await _ring.getVibrationInterval();
                    return '${interval}ms';
                  }),
                  enabled: _supports(DemoCapabilityKey.vibrationInterval),
                ),
                _btn(
                  '设振动间隔500ms',
                  () => _run('设振动间隔', () => _ring.setVibrationInterval(500)),
                  enabled: _supports(DemoCapabilityKey.vibrationInterval),
                ),
                _btn(
                  '启动心率校正（原生无能力位）',
                  () => _run('启动心率校正', _ring.startHeartRateCalibration),
                ),
                _btn(
                  '获取跌落提醒',
                  () => _run('跌落提醒', () async {
                    final enabled = await _ring.getFallDetect();
                    return enabled ? '已开启' : '已关闭';
                  }),
                  enabled: _supports(DemoCapabilityKey.fallDetect),
                ),
                _btn(
                  '开启跌落提醒',
                  () => _run('开启跌落提醒', () => _ring.setFallDetect(true)),
                  enabled: _supports(DemoCapabilityKey.fallDetect),
                ),
                _btn(
                  '关闭跌落提醒',
                  () => _run('关闭跌落提醒', () => _ring.setFallDetect(false)),
                  enabled: _supports(DemoCapabilityKey.fallDetect),
                ),
                _btn(
                  '获取计数提醒',
                  () => _run('计数提醒', () async {
                    final minutes = await _ring.getCountReminderInterval();
                    return '$minutes分钟';
                  }),
                  enabled: _supports(DemoCapabilityKey.countReminder),
                ),
                _btn(
                  '计数提醒60分钟',
                  () =>
                      _run('设置计数提醒', () => _ring.setCountReminderInterval(60)),
                  enabled: _supports(DemoCapabilityKey.countReminder),
                ),
                _btn(
                  '关闭计数提醒',
                  () => _run('关闭计数提醒', () => _ring.setCountReminderInterval(0)),
                  enabled: _supports(DemoCapabilityKey.countReminder),
                ),
                _btn(
                  '获取抬腕亮屏',
                  () => _run('抬腕', () async {
                    final s = await _ring.getRaiseBrightScreen();
                    return 'open=${s.isOpen} ${s.startHour}:${s.startMin}-${s.endHour}:${s.endMin}';
                  }),
                  enabled: _supports(DemoCapabilityKey.raiseBrightScreen),
                ),
                _btn(
                  '获取亮屏时长',
                  () => _run('亮屏时长', () async {
                    final t = await _ring.getBrightScreenTime();
                    return '${t}s';
                  }),
                  enabled: _supports(DemoCapabilityKey.brightScreenTime),
                ),
                _btn(
                  '设亮屏5s',
                  () => _run('设亮屏', () => _ring.setBrightScreenTime(5)),
                  enabled: _supports(DemoCapabilityKey.brightScreenTime),
                ),
                _btn(
                  '获取HID',
                  () => _run('HID', () async {
                    final h = await _ring.getVideoHid();
                    return 'hidOpen=$h';
                  }),
                  enabled: _supports(DemoCapabilityKey.videoHid),
                ),
                _btn(
                  '闹钟振动时长',
                  () => _run('闹钟振动', () async {
                    final d = await _ring.getAlarmVibrationDuration();
                    return '$d次';
                  }),
                  enabled: _supports(DemoCapabilityKey.alarmVibrationDuration),
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

  Widget _btn(String label, VoidCallback onTap, {bool enabled = true}) =>
      FilledButton.tonal(
        onPressed: enabled ? onTap : null,
        child: Text(
          enabled ? label : '$label(不支持)',
          style: const TextStyle(fontSize: 12),
        ),
      );
}
