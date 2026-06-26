import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../device_store.dart';

/// 扫描 + 连接页（对标 scan.vue），从 home_page「扫描设备」进入。
///
/// 进页即清理已保存设备（防旧设备误重连）；点选设备连接，**就绪后保存设备并返回 home**。
class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final _ring = RwfitBle.instance;
  final _devices = <String, BleDevice>{};
  final _subs = <StreamSubscription>[];
  bool _scanning = false;
  BleDevice? _connecting; // 正在连接的设备（用于就绪后保存）

  @override
  void initState() {
    super.initState();
    // 进扫描页先清理已保存设备 + 解除 iOS 绑定态，避免旧设备触发重连。
    DeviceStore.clear();
    _ring.iosSetBindedStatus(false);

    _subs.add(
      _ring.onScanResult.listen((d) {
        setState(() => _devices[d.uuid ?? d.mac] = d);
      }),
    );
    _subs.add(
      _ring.onScanFinish.listen((_) {
        setState(() => _scanning = false);
      }),
    );
    _subs.add(
      _ring.onFunctionMenu.listen((_) async {
        // 连接就绪 → 保存刚连接的设备并返回 home（home 自身也会刷新已保存设备）。
        final d = _connecting;
        if (d != null) await DeviceStore.save(d);
        if (mounted) Navigator.pop(context);
      }),
    );
    _subs.add(
      _ring.onConnectState.listen((e) {
        if (e.state == ConnectState.failed && mounted) {
          setState(() => _connecting = null);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('连接失败${e.reason != null ? ': ${e.reason}' : ''}'),
            ),
          );
        }
      }),
    );
  }

  Future<void> _toggleScan() async {
    if (_scanning) {
      await _ring.stopScan();
      setState(() => _scanning = false);
    } else {
      setState(() {
        _devices.clear();
        _scanning = true;
      });
      await _ring.startScan();
    }
  }

  Future<void> _connect(BleDevice d) async {
    if (_scanning) await _ring.stopScan();
    setState(() {
      _scanning = false;
      _connecting = d;
    });
    try {
      await _ring.connect(d);
    } catch (e) {
      if (mounted) {
        setState(() => _connecting = null);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('连接失败: $e')));
      }
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    if (_scanning) _ring.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = _devices.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    final connecting = _connecting;
    return Scaffold(
      appBar: AppBar(title: const Text('扫描设备')),
      body: Column(
        children: [
          if (connecting != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: Colors.orange.shade50,
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '连接中: ${connecting.name.isEmpty ? '(未命名)' : connecting.name}...',
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: list.isEmpty
                ? Center(child: Text(_scanning ? '扫描中...' : '点击右下角按钮开始扫描'))
                : ListView.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final d = list[i];
                      return ListTile(
                        title: Text(d.name.isEmpty ? '(未命名)' : d.name),
                        subtitle: Text('${d.uuid ?? d.mac}  rssi=${d.rssi}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: connecting == null ? () => _connect(d) : null,
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _toggleScan,
        icon: Icon(_scanning ? Icons.stop : Icons.search),
        label: Text(_scanning ? '停止' : '扫描'),
      ),
    );
  }
}
