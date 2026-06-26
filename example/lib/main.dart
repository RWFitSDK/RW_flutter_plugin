import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import 'pages/home_page.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'RWFIT Ble Demo',
    theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
    home: const PermissionGate(),
  );
}

/// 启动时请求蓝牙权限，通过后进入功能主页（落地页）。
class PermissionGate extends StatefulWidget {
  const PermissionGate({super.key});

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate> {
  String _status = '正在请求蓝牙权限...';
  bool _granted = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      final results = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
      final allGranted = results.values.every(
        (s) => s.isGranted || s.isLimited,
      );
      setState(() {
        _granted = allGranted;
        _status = allGranted ? '权限已授予' : '部分权限被拒绝，蓝牙功能可能受限';
      });
    } else {
      // iOS 蓝牙权限在首次使用时系统自动弹窗
      setState(() {
        _granted = true;
        _status = '权限已就绪';
      });
    }

    if (_granted && mounted) {
      // 初始化 SDK
      try {
        await RwfitBle.instance.init();
      } catch (_) {}
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RWFIT Ble Demo')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_status),
            if (!_granted) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _requestPermissions,
                child: const Text('重新请求权限'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
