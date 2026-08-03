import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../widgets/result_tile.dart';
import '../i18n.dart';

/// 设备信息页：电量 / 固件版本 / 设置用户信息 / 时间格式。
class DeviceInfoPage extends StatefulWidget {
  const DeviceInfoPage({super.key});

  @override
  State<DeviceInfoPage> createState() => _DeviceInfoPageState();
}

class _DeviceInfoPageState extends State<DeviceInfoPage> {
  final _ring = RwfitBle.instance;
  final _results = <String>[];

  void _log(String s) => setState(() => _results.insert(0, s));

  Future<void> _run(String name, Future<dynamic> Function() fn) async {
    try {
      final r = await fn();
      _log('$name ✓ ${r ?? ''}');
    } on RwfitException catch (e) {
      _log('$name ✗ [${e.code}] ${e.message}');
    } catch (e) {
      _log('$name ✗ $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(demoTr('设备信息', 'Device info'))),
      body: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _btn(
                demoTr('获取电量', 'Get battery'),
                () => _run(demoTr('电量', 'Battery'), () async {
                  final p = await _ring.getPower();
                  return '$p%';
                }),
              ),
              _btn(
                demoTr('固件版本', 'Firmware version'),
                () => _run(demoTr('固件', 'Firmware'), () async {
                  final f = await _ring.getFirmwareVersion();
                  return '${f.deviceClazz} / ${f.deviceNo} / UI:${f.uiVersion}';
                }),
              ),
              _btn(
                demoTr('SDK版本', 'SDK version'),
                () => _run(
                  demoTr('SDK版本', 'SDK version'),
                  () => _ring.getSdkVersion(),
                ),
              ),
              _btn(
                demoTr('插件版本', 'Plugin version'),
                () => _run(
                  demoTr('插件版本', 'Plugin version'),
                  () => _ring.getPluginVersion(),
                ),
              ),
              _btn(
                demoTr('设置用户信息', 'Set user info'),
                () => _run(
                  demoTr('用户信息', 'User info'),
                  () => _ring.setUserInfo(
                    const UserInfo(gender: 1, age: 25, height: 175, weight: 70),
                  ),
                ),
              ),
              _btn(
                demoTr('设12小时制', 'Use 12-hour time'),
                () => _run(
                  demoTr('时间格式', 'Time format'),
                  () => _ring.setTimeFormat(0),
                ),
              ),
              _btn(
                demoTr('设24小时制', 'Use 24-hour time'),
                () => _run(
                  demoTr('时间格式', 'Time format'),
                  () => _ring.setTimeFormat(1),
                ),
              ),
              _btn(
                demoTr('功能列表', 'Capabilities'),
                () => _run(demoTr('功能列表', 'Capabilities'), () async {
                  final m = await _ring.getFunctionList();
                  return m['supportMenu']?.toString() ?? m.toString();
                }),
              ),
            ],
          ),
          const Divider(),
          Expanded(child: ResultList(results: _results)),
        ],
      ),
    );
  }

  Widget _btn(String label, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(left: 8, top: 8),
    child: FilledButton.tonal(onPressed: onTap, child: Text(label)),
  );
}
