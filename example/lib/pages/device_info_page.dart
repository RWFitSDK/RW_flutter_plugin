import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../widgets/result_tile.dart';

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
      appBar: AppBar(title: const Text('设备信息')),
      body: Column(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _btn(
                '获取电量',
                () => _run('电量', () async {
                  final p = await _ring.getPower();
                  return '$p%';
                }),
              ),
              _btn(
                '固件版本',
                () => _run('固件', () async {
                  final f = await _ring.getFirmwareVersion();
                  return '${f.deviceClazz} / ${f.deviceNo} / UI:${f.uiVersion}';
                }),
              ),
              _btn('SDK版本', () => _run('SDK版本', () => _ring.getSdkVersion())),
              _btn('插件版本', () => _run('插件版本', () => _ring.getPluginVersion())),
              _btn(
                '设置用户信息',
                () => _run(
                  '用户信息',
                  () => _ring.setUserInfo(
                    const UserInfo(gender: 1, age: 25, height: 175, weight: 70),
                  ),
                ),
              ),
              _btn('设12小时制', () => _run('时间格式', () => _ring.setTimeFormat(0))),
              _btn('设24小时制', () => _run('时间格式', () => _ring.setTimeFormat(1))),
              _btn(
                '功能列表',
                () => _run('功能列表', () async {
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
