import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../device_store.dart';
import '../i18n.dart';
import '../support_menu.dart';
import 'device_info_page.dart';
import 'timed_monitor_page.dart';
import 'realtime_page.dart';
import 'control_page.dart';
import 'alarm_page.dart';
import 'sync_page.dart';
import 'ota_page.dart';
import 'notify_page.dart';
import 'scan_page.dart';
import 'workout_page.dart';
import 'health_alert_page.dart';
import 'sensor_raw_page.dart';

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
  DemoCapabilities _capabilities = const DemoCapabilities.empty();
  String _conn = 'disconnected';
  BleDevice? _saved;

  @override
  void initState() {
    super.initState();
    _subs.add(
      _ring.onConnectState.listen((e) {
        setState(() => _conn = e.state.name);
        if (e.state == ConnectState.disconnected ||
            e.state == ConnectState.failed) {
          setState(() {
            _ready = false;
            _capabilities = const DemoCapabilities.empty();
          });
        }
      }),
    );
    _subs.add(
      _ring.onFunctionMenu.listen((menu) async {
        setState(() {
          _ready = true;
          _capabilities = DemoCapabilities(
            Map<String, dynamic>.unmodifiable(menu.raw),
          );
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
      _toast(demoTr('设备已连接', 'Device is already connected'));
      return;
    }
    setState(() => _conn = 'connecting');
    try {
      await _ring.reconnect(saved);
      _toast(
        '${demoTr('重连指令已发送', 'Reconnect command sent')}: '
        '${saved.name.isEmpty ? saved.mac : saved.name}',
      );
    } catch (e) {
      _toast('${demoTr('重连失败', 'Reconnect failed')}: $e');
    }
  }

  Future<void> _disconnect() async {
    try {
      await _ring.disconnect();
      // 仅断开，不清除已保存设备（仍可重连）。
      setState(() {
        _conn = 'disconnected';
        _ready = false;
        _capabilities = const DemoCapabilities.empty();
      });
    } catch (e) {
      _toast('${demoTr('断开失败', 'Disconnect failed')}: $e');
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
    final connection = switch (_conn) {
      'connected' => demoTr('已连接', 'Connected'),
      'connecting' => demoTr('连接中', 'Connecting'),
      'failed' => demoTr('连接失败', 'Connection failed'),
      _ => demoTr('未连接', 'Disconnected'),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(demoTr('RWFIT 戒指', 'RWFIT Ring')),
        actions: [
          Tooltip(
            message: context.language == DemoLanguage.zh
                ? 'Switch to English'
                : '切换到中文',
            child: TextButton(
              onPressed: context.toggleLanguage,
              child: Text(
                context.language == DemoLanguage.zh ? 'EN' : '中文',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: _ready ? Colors.green.shade50 : Colors.orange.shade50,
            child: Text(
              '${demoTr('连接状态', 'Connection')}: $connection'
              '${_ready ? demoTr(' (已就绪)', ' (Ready)') : ''}',
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
                  demoTr('设备信息', 'Device info'),
                  demoTr(
                    '电量/固件/用户信息/时间格式',
                    'Battery / firmware / user info / time format',
                  ),
                  Icons.info_outline,
                  () => _push(const DeviceInfoPage()),
                ),
                _tile(
                  demoTr('全天检测', 'All-day monitoring'),
                  demoTr(
                    '心率/血氧/HRV/压力/血糖/血压/体温/PPG',
                    'Heart rate / SpO₂ / HRV / stress / glucose / BP / temperature / PPG',
                  ),
                  Icons.monitor_heart,
                  () => _push(TimedMonitorPage(capabilities: _capabilities)),
                  enabled: _ready && _capabilities.supportsAnyTimedMonitor,
                ),
                _tile(
                  demoTr('实时测量', 'Real-time measurement'),
                  demoTr(
                    '实时心率/血氧/血压等（互斥）',
                    'Real-time heart rate / SpO₂ / BP (mutually exclusive)',
                  ),
                  Icons.favorite,
                  () => _push(RealtimePage(capabilities: _capabilities)),
                  enabled: _ready && _capabilities.supportsAnyRealtime,
                ),
                _tile(
                  demoTr('设备控制', 'Device controls'),
                  demoTr(
                    '找设备/关机/拍照/LED/佩戴/振动',
                    'Find device / power / camera / LED / wearing / vibration',
                  ),
                  Icons.settings_remote,
                  () => _push(ControlPage(capabilities: _capabilities)),
                  enabled:
                      _ready &&
                      (_capabilities.supportsAnyDeviceControl ||
                          Platform.isAndroid),
                ),
                _tile(
                  demoTr('赞念与健康报警', 'Prayer & health alerts'),
                  demoTr(
                    '赞念开关 / 心率和血氧报警 / 实时报警事件',
                    'Prayer count / heart rate and SpO₂ alerts / live events',
                  ),
                  Icons.health_and_safety_outlined,
                  () => _push(HealthAlertPage(capabilities: _capabilities)),
                  enabled: _ready && _capabilities.supportsAnyHealthAlert,
                ),
                _tile(
                  demoTr('传感器原始数据', 'Raw sensor data'),
                  demoTr(
                    'PPG / ACC / Red / IR / 睡眠状态',
                    'PPG / ACC / Red / IR / sleep state',
                  ),
                  Icons.sensors,
                  () => _push(SensorRawPage(capabilities: _capabilities)),
                  enabled: _ready && _capabilities.supportsAnySensorRaw,
                ),
                _tile(
                  demoTr('闹钟', 'Alarms'),
                  demoTr(
                    '查询/设置/删除（全量下发）',
                    'Read / set / delete (full replacement)',
                  ),
                  Icons.alarm,
                  () => _push(AlarmPage(capabilities: _capabilities)),
                  enabled: _ready && _capabilities.has(DemoCapabilityKey.alarm),
                ),
                _tile(
                  demoTr('数据同步', 'Data sync'),
                  demoTr('历史健康数据同步', 'Historical health data sync'),
                  Icons.sync,
                  () => _push(SyncPage(capabilities: _capabilities)),
                  enabled: _ready && _capabilities.supportsAnyHealthData,
                ),
                _tile(
                  demoTr('多运动', 'Workouts'),
                  _capabilities.supportsWorkout
                      ? demoTr(
                          '运动类型选择 / 实时运动控制与数据',
                          'Workout selection / live controls and data',
                        )
                      : demoTr('当前设备不支持多运动', 'Workout mode is not supported'),
                  Icons.directions_run,
                  () => _push(const WorkoutPage()),
                  enabled: _ready && _capabilities.supportsWorkout,
                ),
                _tile(
                  demoTr('OTA 升级', 'OTA upgrade'),
                  demoTr('固件升级', 'Firmware upgrade'),
                  Icons.system_update,
                  () => _push(const OtaPage()),
                ),
                _tile(
                  demoTr('消息/通知', 'Messages / notifications'),
                  demoTr(
                    'Android 推送 / iOS ANCS 开关',
                    'Android messages / iOS ANCS settings',
                  ),
                  Icons.notifications,
                  () => _push(NotifyPage(capabilities: _capabilities)),
                  enabled:
                      _ready &&
                      _capabilities.has(
                        Platform.isAndroid
                            ? DemoCapabilityKey.pushMessage
                            : DemoCapabilityKey.pushMessageSwitch,
                      ),
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
          Text(
            demoTr('连接管理', 'Connection'),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (saved != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${demoTr('已保存设备', 'Saved device')}: '
                '${saved.name.isEmpty ? demoTr('(未命名)', '(Unnamed)') : saved.name}'
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
                label: Text(demoTr('扫描设备', 'Scan devices')),
              ),
              OutlinedButton.icon(
                onPressed: saved == null ? null : _reconnect,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(demoTr('重连设备', 'Reconnect')),
              ),
              OutlinedButton.icon(
                onPressed: _disconnect,
                icon: const Icon(Icons.link_off, size: 18),
                label: Text(demoTr('断开连接', 'Disconnect')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tile(
    String title,
    String sub,
    IconData icon,
    VoidCallback onTap, {
    bool? enabled,
  }) {
    final isEnabled = enabled ?? _ready;
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(sub),
      trailing: const Icon(Icons.chevron_right),
      enabled: isEnabled,
      onTap: isEnabled ? onTap : null,
    );
  }
}
