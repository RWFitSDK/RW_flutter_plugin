import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../support_menu.dart';
import '../i18n.dart';
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
          '${demoTr('触摸/音乐事件', 'Touch/music event')}: ${e.action.name} '
          '(key=${e.keyType}, touch=${e.touchType})',
        );
      }),
    );
    _subs.add(
      _ring.onCallControl.listen((e) {
        _log(
          '${demoTr('来电控制事件', 'Call control event')}: '
          '${e.action?.name ?? 'unknown'} (raw=${e.rawValue})',
        );
      }),
    );
    _subs.add(
      _ring.onHeartRateCalibration.listen((e) {
        _log(
          '${demoTr('心率校正', 'Heart-rate calibration')}: '
          'mode=0x${e.testMode.toRadixString(16)} result=${e.result} '
          '${e.isCalibrating ? demoTr('校正中', 'Calibrating') : demoTr('已完成', 'Complete')}',
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
      appBar: AppBar(title: Text(demoTr('设备控制', 'Device controls'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _btn(
                  demoTr('找设备', 'Find device'),
                  () => _run(demoTr('找设备', 'Find device'), _ring.findDevice),
                  enabled: _supports(DemoCapabilityKey.findDevice),
                ),
                _btn(
                  demoTr('关机', 'Power off'),
                  () => _run(demoTr('关机', 'Power off'), _ring.powerOff),
                  enabled: _supports(DemoCapabilityKey.powerOff),
                ),
                _btn(
                  demoTr('恢复出厂', 'Factory reset'),
                  () =>
                      _run(demoTr('恢复出厂', 'Factory reset'), _ring.factoryReset),
                  enabled: _supports(DemoCapabilityKey.factoryReset),
                ),
                _btn(
                  demoTr('进拍照模式', 'Enter camera mode'),
                  () => _run(
                    demoTr('进拍照', 'Enter camera mode'),
                    () => _ring.controlPhoto(1),
                  ),
                  enabled: _supports(DemoCapabilityKey.takePhoto),
                ),
                _btn(
                  demoTr('退拍照模式', 'Exit camera mode'),
                  () => _run(
                    demoTr('退拍照', 'Exit camera mode'),
                    () => _ring.controlPhoto(0),
                  ),
                  enabled: _supports(DemoCapabilityKey.takePhoto),
                ),
                _btn(
                  demoTr('来电接听(Android)', 'Answer call (Android)'),
                  () => _run(
                    demoTr('来电接听', 'Answer call'),
                    () => _ring.controlPhone(CallControlAction.answer),
                  ),
                  enabled: Platform.isAndroid,
                ),
                _btn(
                  demoTr('来电拒接(Android)', 'Reject call (Android)'),
                  () => _run(
                    demoTr('来电拒接', 'Reject call'),
                    () => _ring.controlPhone(CallControlAction.reject),
                  ),
                  enabled: Platform.isAndroid,
                ),
                _btn(
                  demoTr('获取LED', 'Get LED'),
                  () => _run('LED', () async {
                    final l = await _ring.getRingLedLevel();
                    return 'open=${l.isOpen} level=${l.lcdLevel}';
                  }),
                  enabled: _supports(DemoCapabilityKey.ledLight),
                ),
                _btn(
                  demoTr('LED开L2', 'Enable LED L2'),
                  () => _run(
                    demoTr('设LED', 'Set LED'),
                    () => _ring.setRingLedLevel(
                      const LedLevel(isOpen: true, lcdLevel: 2),
                    ),
                  ),
                  enabled: _supports(DemoCapabilityKey.ledLight),
                ),
                _btn(
                  demoTr('获取佩戴方向', 'Get wearing hand'),
                  () => _run(demoTr('佩戴', 'Wearing hand'), () async {
                    final r = await _ring.getRingWearDir();
                    return r
                        ? demoTr('右手', 'Right hand')
                        : demoTr('左手', 'Left hand');
                  }),
                  enabled: _supports(DemoCapabilityKey.wearDirection),
                ),
                _btn(
                  demoTr('设右手', 'Set right hand'),
                  () => _run(
                    demoTr('设右手', 'Set right hand'),
                    () => _ring.setRingWearHand(true),
                  ),
                  enabled: _supports(DemoCapabilityKey.wearDirection),
                ),
                _btn(
                  demoTr('设左手', 'Set left hand'),
                  () => _run(
                    demoTr('设左手', 'Set left hand'),
                    () => _ring.setRingWearHand(false),
                  ),
                  enabled: _supports(DemoCapabilityKey.wearDirection),
                ),
                _btn(
                  demoTr('获取振动', 'Get vibration'),
                  () => _run(demoTr('振动', 'Vibration'), () async {
                    final v = await _ring.getVibrationCount();
                    return 'count=${v.count} level=${v.level}';
                  }),
                  enabled: _supports(DemoCapabilityKey.vibrationLevel),
                ),
                _btn(
                  demoTr('设振动', 'Set vibration'),
                  () => _run(
                    demoTr('设振动', 'Set vibration'),
                    () => _ring.setVibrationCount(
                      const VibrationConfig(count: 3, level: 2),
                    ),
                  ),
                  enabled: _supports(DemoCapabilityKey.vibrationLevel),
                ),
                _btn(
                  demoTr('获取振动间隔', 'Get vibration interval'),
                  () => _run(demoTr('振动间隔', 'Vibration interval'), () async {
                    final interval = await _ring.getVibrationInterval();
                    return '${interval}ms';
                  }),
                  enabled: _supports(DemoCapabilityKey.vibrationInterval),
                ),
                _btn(
                  demoTr('设振动间隔500ms', 'Set vibration interval to 500ms'),
                  () => _run(
                    demoTr('设振动间隔', 'Set vibration interval'),
                    () => _ring.setVibrationInterval(500),
                  ),
                  enabled: _supports(DemoCapabilityKey.vibrationInterval),
                ),
                _btn(
                  demoTr(
                    '启动心率校正（原生无能力位）',
                    'Start HR calibration (no native capability flag)',
                  ),
                  () => _run(
                    demoTr('启动心率校正', 'Start HR calibration'),
                    _ring.startHeartRateCalibration,
                  ),
                ),
                _btn(
                  demoTr('获取跌落提醒', 'Get fall detection'),
                  () => _run(demoTr('跌落提醒', 'Fall detection'), () async {
                    final enabled = await _ring.getFallDetect();
                    return enabled
                        ? demoTr('已开启', 'Enabled')
                        : demoTr('已关闭', 'Disabled');
                  }),
                  enabled: _supports(DemoCapabilityKey.fallDetect),
                ),
                _btn(
                  demoTr('开启跌落提醒', 'Enable fall detection'),
                  () => _run(
                    demoTr('开启跌落提醒', 'Enable fall detection'),
                    () => _ring.setFallDetect(true),
                  ),
                  enabled: _supports(DemoCapabilityKey.fallDetect),
                ),
                _btn(
                  demoTr('关闭跌落提醒', 'Disable fall detection'),
                  () => _run(
                    demoTr('关闭跌落提醒', 'Disable fall detection'),
                    () => _ring.setFallDetect(false),
                  ),
                  enabled: _supports(DemoCapabilityKey.fallDetect),
                ),
                _btn(
                  demoTr('获取计数提醒', 'Get count reminder'),
                  () => _run(demoTr('计数提醒', 'Count reminder'), () async {
                    final minutes = await _ring.getCountReminderInterval();
                    return '$minutes ${demoTr('分钟', 'min')}';
                  }),
                  enabled: _supports(DemoCapabilityKey.countReminder),
                ),
                _btn(
                  demoTr('计数提醒60分钟', 'Set reminder to 60 min'),
                  () => _run(
                    demoTr('设置计数提醒', 'Set count reminder'),
                    () => _ring.setCountReminderInterval(60),
                  ),
                  enabled: _supports(DemoCapabilityKey.countReminder),
                ),
                _btn(
                  demoTr('关闭计数提醒', 'Disable count reminder'),
                  () => _run(
                    demoTr('关闭计数提醒', 'Disable count reminder'),
                    () => _ring.setCountReminderInterval(0),
                  ),
                  enabled: _supports(DemoCapabilityKey.countReminder),
                ),
                _btn(
                  demoTr('获取抬腕亮屏', 'Get raise-to-wake'),
                  () => _run(demoTr('抬腕', 'Raise-to-wake'), () async {
                    final s = await _ring.getRaiseBrightScreen();
                    return 'open=${s.isOpen} ${s.startHour}:${s.startMin}-${s.endHour}:${s.endMin}';
                  }),
                  enabled: _supports(DemoCapabilityKey.raiseBrightScreen),
                ),
                _btn(
                  demoTr('获取亮屏时长', 'Get screen duration'),
                  () => _run(demoTr('亮屏时长', 'Screen duration'), () async {
                    final t = await _ring.getBrightScreenTime();
                    return '${t}s';
                  }),
                  enabled: _supports(DemoCapabilityKey.brightScreenTime),
                ),
                _btn(
                  demoTr('设亮屏5s', 'Set screen to 5s'),
                  () => _run(
                    demoTr('设亮屏', 'Set screen duration'),
                    () => _ring.setBrightScreenTime(5),
                  ),
                  enabled: _supports(DemoCapabilityKey.brightScreenTime),
                ),
                _btn(
                  demoTr('获取HID', 'Get HID'),
                  () => _run('HID', () async {
                    final h = await _ring.getVideoHid();
                    return 'hidOpen=$h';
                  }),
                  enabled: _supports(DemoCapabilityKey.videoHid),
                ),
                _btn(
                  demoTr('闹钟振动时长', 'Alarm vibration count'),
                  () => _run(demoTr('闹钟振动', 'Alarm vibration'), () async {
                    final d = await _ring.getAlarmVibrationDuration();
                    return '$d ${demoTr('次', 'times')}';
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
          enabled ? label : '$label (${demoTr('不支持', 'Unsupported')})',
          style: const TextStyle(fontSize: 12),
        ),
      );
}
