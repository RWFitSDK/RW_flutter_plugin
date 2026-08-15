import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../demo_theme.dart';
import '../i18n.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final _ring = RwfitBle.instance;
  final _devices = <String, BleDevice>{};
  final _subscriptions = <StreamSubscription<dynamic>>[];
  Timer? _countdown;
  Timer? _connectTimeout;
  bool _scanning = false;
  int _remainingSeconds = 10;
  BleDevice? _connecting;
  String? _error;

  @override
  void initState() {
    super.initState();
    _subscriptions.add(
      _ring.onScanResult.listen((device) {
        final key = device.uuid ?? device.mac;
        if (!mounted) return;
        setState(() => _devices[key] = device);
      }),
    );
    _subscriptions.add(
      _ring.onScanFinish.listen((_) {
        if (!mounted) return;
        _stopCountdown();
        setState(() => _scanning = false);
      }),
    );
    _subscriptions.add(
      _ring.onConnectState.listen((event) {
        if (event.state == ConnectState.failed && mounted) {
          _connectTimeout?.cancel();
          _connectTimeout = null;
          setState(() {
            _connecting = null;
            _error = event.reason ?? demoTr('设备连接失败', 'Connection failed');
          });
        }
      }),
    );
    _subscriptions.add(
      _ring.onFunctionMenu.listen((_) async {
        if (_connecting == null) return;
        _connectTimeout?.cancel();
        _connectTimeout = null;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(demoTr('绑定成功', 'Device bound successfully')),
            duration: const Duration(milliseconds: 700),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 650));
        if (mounted) Navigator.pop(context);
      }),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  Future<void> _startScan() async {
    if (_scanning) return;
    setState(() {
      _devices.clear();
      _error = null;
      _scanning = true;
      _remainingSeconds = 10;
    });
    _countdown?.cancel();
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_remainingSeconds <= 1) {
        unawaited(_stopScanAfterCountdown());
        return;
      }
      setState(() => _remainingSeconds--);
    });
    try {
      await _ring.startScan();
    } catch (error) {
      _stopCountdown();
      if (mounted) {
        setState(() {
          _scanning = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _stopScan() async {
    _stopCountdown();
    if (mounted && _scanning) {
      setState(() => _scanning = false);
    }
    await _ring.stopScan();
  }

  Future<void> _stopScanAfterCountdown() async {
    try {
      await _stopScan();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  void _stopCountdown() {
    _countdown?.cancel();
    _countdown = null;
  }

  Future<void> _connect(BleDevice device) async {
    if (_connecting != null) return;
    if (_scanning) await _stopScan();
    setState(() {
      _connecting = device;
      _error = null;
    });
    _connectTimeout?.cancel();
    _connectTimeout = Timer(const Duration(seconds: 20), () async {
      final connecting = _connecting;
      if (!mounted || connecting == null) return;
      if ((connecting.uuid ?? connecting.mac) != (device.uuid ?? device.mac)) {
        return;
      }
      final message = demoTr(
        '设备初始化超时，请靠近设备后重试',
        'Device initialization timed out. Move closer and try again.',
      );
      setState(() {
        _connecting = null;
        _error = message;
      });
      try {
        await _ring.disconnect();
      } catch (_) {}
    });
    try {
      await _ring.connect(device);
    } catch (error) {
      _connectTimeout?.cancel();
      _connectTimeout = null;
      if (mounted) {
        setState(() {
          _connecting = null;
          _error = '$error';
        });
      }
    }
  }

  @override
  void dispose() {
    _stopCountdown();
    _connectTimeout?.cancel();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    if (_scanning) _ring.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devices = _devices.values.toList()
      ..sort((a, b) => b.rssi.compareTo(a.rssi));
    return Scaffold(
      appBar: AppBar(title: Text(demoTr('搜索设备', 'Search devices'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _scanHeader(),
          SectionHeading(
            demoTr('发现的设备', 'Discovered devices'),
            caption: demoTr('${devices.length} 台', '${devices.length} found'),
          ),
          if (devices.isEmpty)
            DemoEmptyCard(
              title: demoTr('暂未发现设备', 'No devices found'),
              message: demoTr(
                '确认戒指未被其他手机连接，然后重新搜索。',
                'Make sure the ring is not connected to another phone and scan again.',
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (var index = 0; index < devices.length; index++) ...[
                    _deviceTile(devices[index]),
                    if (index != devices.length - 1)
                      const Divider(height: 1, indent: 72),
                  ],
                ],
              ),
            ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEEEE),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                _error!,
                style: const TextStyle(color: DemoColors.danger),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _scanHeader() => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _scanning
                      ? demoTr('正在搜索附近设备', 'Searching nearby devices')
                      : demoTr('搜索已暂停', 'Scan paused'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _scanning
                      ? (_remainingSeconds > 0
                            ? demoTr(
                                '$_remainingSeconds 秒后自动暂停',
                                'Pauses in $_remainingSeconds s',
                              )
                            : demoTr('正在结束搜索…', 'Finishing scan…'))
                      : demoTr('请保持戒指靠近手机', 'Keep the ring close to the phone'),
                  style: const TextStyle(
                    color: DemoColors.secondaryText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: _connecting != null
                ? null
                : (_scanning ? _stopScan : _startScan),
            icon: Icon(_scanning ? Icons.stop : Icons.search, size: 18),
            label: Text(
              _scanning ? demoTr('停止', 'Stop') : demoTr('重搜', 'Scan again'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _deviceTile(BleDevice device) {
    final connecting = _connecting;
    final isConnecting =
        connecting != null &&
        (connecting.uuid ?? connecting.mac) == (device.uuid ?? device.mac);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: DemoColors.primary, width: 8),
        ),
      ),
      title: Text(
        device.name.isEmpty ? demoTr('(未命名)', '(Unnamed)') : device.name,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        'MAC: ${device.mac.isEmpty ? '--' : device.mac}\n'
        '${device.uuid == null ? '' : 'deviceId: ${device.uuid}'}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      isThreeLine: device.uuid != null,
      trailing: isConnecting
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _signalIcon(device.rssi),
                  size: 20,
                  color: DemoColors.primary,
                ),
                Text(
                  '${device.rssi} dBm',
                  style: const TextStyle(
                    color: DemoColors.secondaryText,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
      onTap: _connecting == null ? () => _connect(device) : null,
    );
  }

  IconData _signalIcon(int rssi) {
    if (rssi >= -60) return Icons.signal_cellular_alt;
    if (rssi >= -80) return Icons.network_cell;
    return Icons.signal_cellular_alt_1_bar;
  }
}
