import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../widgets/result_tile.dart';

/// 设备控制页：找设备/关机/拍照/LED/佩戴方向/振动/亮屏/HID。
class ControlPage extends StatefulWidget {
  const ControlPage({super.key});

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  final _ring = RwfitBle.instance;
  final _results = <String>[];
  StreamSubscription? _touchSub;

  @override
  void initState() {
    super.initState();
    _touchSub = _ring.onTouchEvent.listen((e) {
      _log('触摸事件: ${e.action.name} (raw=${e.rawAction})');
    });
  }

  void _log(String s) => setState(() => _results.insert(0, s));

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
    _touchSub?.cancel();
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
                _btn('找设备', () => _run('找设备', _ring.findDevice)),
                _btn('关机', () => _run('关机', _ring.powerOff)),
                _btn('恢复出厂', () => _run('恢复出厂', _ring.factoryReset)),
                _btn('进拍照模式', () => _run('进拍照', () => _ring.controlPhoto(1))),
                _btn('退拍照模式', () => _run('退拍照', () => _ring.controlPhoto(0))),
                _btn(
                  '获取LED',
                  () => _run('LED', () async {
                    final l = await _ring.getRingLedLevel();
                    return 'open=${l.isOpen} level=${l.lcdLevel}';
                  }),
                ),
                _btn(
                  'LED开L2',
                  () => _run(
                    '设LED',
                    () => _ring.setRingLedLevel(
                      const LedLevel(isOpen: true, lcdLevel: 2),
                    ),
                  ),
                ),
                _btn(
                  '获取佩戴方向',
                  () => _run('佩戴', () async {
                    final r = await _ring.getRingWearDir();
                    return r ? '右手' : '左手';
                  }),
                ),
                _btn(
                  '设右手',
                  () => _run('设右手', () => _ring.setRingWearHand(true)),
                ),
                _btn(
                  '设左手',
                  () => _run('设左手', () => _ring.setRingWearHand(false)),
                ),
                _btn(
                  '获取振动',
                  () => _run('振动', () async {
                    final v = await _ring.getVibrationCount();
                    return 'count=${v.count} level=${v.level}';
                  }),
                ),
                _btn(
                  '设振动',
                  () => _run(
                    '设振动',
                    () => _ring.setVibrationCount(
                      const VibrationConfig(count: 3, level: 2),
                    ),
                  ),
                ),
                _btn(
                  '获取抬腕亮屏',
                  () => _run('抬腕', () async {
                    final s = await _ring.getRaiseBrightScreen();
                    return 'open=${s.isOpen} ${s.startHour}:${s.startMin}-${s.endHour}:${s.endMin}';
                  }),
                ),
                _btn(
                  '获取亮屏时长',
                  () => _run('亮屏时长', () async {
                    final t = await _ring.getBrightScreenTime();
                    return '${t}s';
                  }),
                ),
                _btn(
                  '设亮屏5s',
                  () => _run('设亮屏', () => _ring.setBrightScreenTime(5)),
                ),
                _btn(
                  '获取HID',
                  () => _run('HID', () async {
                    final h = await _ring.getVideoHid();
                    return 'hidOpen=$h';
                  }),
                ),
                _btn(
                  '闹钟振动时长',
                  () => _run('闹钟振动', () async {
                    final d = await _ring.getAlarmVibrationDuration();
                    return '${d}s';
                  }),
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

  Widget _btn(String label, VoidCallback onTap) => FilledButton.tonal(
    onPressed: onTap,
    child: Text(label, style: const TextStyle(fontSize: 12)),
  );
}
