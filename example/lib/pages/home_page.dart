import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../device_store.dart';
import 'device_info_page.dart';
import 'timed_monitor_page.dart';
import 'realtime_page.dart';
import 'control_page.dart';
import 'alarm_page.dart';
import 'sync_page.dart';
import 'ota_page.dart';
import 'notify_page.dart';
import 'scan_page.dart';

/// 功能主页 / 落地页（对标 index.vue）：连接管理 + 各功能子页入口。
///
/// 启动即进此页：加载本地保存的设备，提供「扫描设备 / 重连 / 断开」，
/// 收到 `onFunctionMenu`（就绪）后才放行下方功能分区，并持久化当前设备供下次重连。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _ring = RwfitBle.instance;
  final _subs = <StreamSubscription>[];
  bool _ready = false;
  String _conn = '未连接';
  BleDevice? _saved;

  @override
  void initState() {
    super.initState();
    _subs.add(
      _ring.onConnectState.listen((e) {
        setState(() => _conn = e.state.name);
        if (e.state == ConnectState.disconnected ||
            e.state == ConnectState.failed) {
          setState(() => _ready = false);
        }
      }),
    );
    _subs.add(
      _ring.onFunctionMenu.listen((menu) async {
        setState(() {
          _ready = true;
          _conn = 'connected';
        });
        // 连接就绪 → 持久化当前设备供下次重连；iOS 置绑定态以启用内置重连。
        final device = BleDevice(
          name: menu.name,
          mac: menu.mac,
          rssi: 0,
          uuid: menu.uuid,
        );
        await DeviceStore.save(device);
        await _ring.iosSetBindedStatus(true);
        if (mounted) setState(() => _saved = device);
      }),
    );
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final d = await DeviceStore.load();
    if (mounted) setState(() => _saved = d);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _openScan() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScanPage()),
    );
    // 从扫描页返回后刷新已保存设备（可能刚连上新设备）。
    if (mounted) _loadSaved();
  }

  Future<void> _reconnect() async {
    final saved = _saved;
    if (saved == null) return;
    if (await _ring.isConnected()) {
      _toast('设备已连接');
      return;
    }
    setState(() => _conn = 'connecting');
    try {
      await _ring.reconnect(saved);
      _toast('重连指令已发送: ${saved.name.isEmpty ? saved.mac : saved.name}');
    } catch (e) {
      _toast('重连失败: $e');
    }
  }

  Future<void> _disconnect() async {
    try {
      await _ring.disconnect();
      // 仅断开，不清除已保存设备（仍可重连）。
      setState(() {
        _conn = 'disconnected';
        _ready = false;
      });
    } catch (e) {
      _toast('断开失败: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _push(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RWFIT 戒指')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: _ready ? Colors.green.shade50 : Colors.orange.shade50,
            child: Text(
              '连接状态: $_conn${_ready ? ' (已就绪)' : ''}',
              style: TextStyle(
                color: _ready ? Colors.green.shade800 : Colors.orange.shade800,
              ),
            ),
          ),
          _connectionPanel(),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              children: [
                _tile(
                  '设备信息',
                  '电量/固件/用户信息/时间格式',
                  Icons.info_outline,
                  () => _push(const DeviceInfoPage()),
                ),
                _tile(
                  '全天检测',
                  '心率/血氧/HRV/压力/血糖/血压 定时配置',
                  Icons.monitor_heart,
                  () => _push(const TimedMonitorPage()),
                ),
                _tile(
                  '实时测量',
                  '实时心率/血氧/血压等（互斥）',
                  Icons.favorite,
                  () => _push(const RealtimePage()),
                ),
                _tile(
                  '设备控制',
                  '找设备/关机/拍照/LED/佩戴/振动',
                  Icons.settings_remote,
                  () => _push(const ControlPage()),
                ),
                _tile(
                  '闹钟',
                  '查询/设置/删除（全量下发）',
                  Icons.alarm,
                  () => _push(const AlarmPage()),
                ),
                _tile(
                  '数据同步',
                  '历史健康数据同步',
                  Icons.sync,
                  () => _push(const SyncPage()),
                ),
                _tile(
                  'OTA 升级',
                  '固件升级',
                  Icons.system_update,
                  () => _push(const OtaPage()),
                ),
                _tile(
                  '消息/通知',
                  'Android 推送 / iOS ANCS 开关',
                  Icons.notifications,
                  () => _push(const NotifyPage()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _connectionPanel() {
    final saved = _saved;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('连接管理', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (saved != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '已保存设备: ${saved.name.isEmpty ? '(未命名)' : saved.name}'
                ' (${saved.uuid ?? saved.mac})',
                style: TextStyle(fontSize: 13, color: Colors.blueGrey.shade700),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _openScan,
                icon: const Icon(Icons.search, size: 18),
                label: const Text('扫描设备'),
              ),
              OutlinedButton.icon(
                onPressed: saved == null ? null : _reconnect,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('重连设备'),
              ),
              OutlinedButton.icon(
                onPressed: _disconnect,
                icon: const Icon(Icons.link_off, size: 18),
                label: const Text('断开连接'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(String title, String sub, IconData icon, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(sub),
      trailing: const Icon(Icons.chevron_right),
      enabled: _ready,
      onTap: _ready ? onTap : null,
    );
  }
}
