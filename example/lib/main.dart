import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import 'i18n.dart';
import 'demo_theme.dart';
import 'pages/home_page.dart';

void main() => runApp(const MyApp());

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late DemoLanguage _language = detectSystemLanguage();

  @override
  Widget build(BuildContext context) {
    setDemoLanguage(_language);
    return DemoI18n(
      language: _language,
      onToggleLanguage: () => setState(
        () => _language = _language == DemoLanguage.zh
            ? DemoLanguage.en
            : DemoLanguage.zh,
      ),
      child: MaterialApp(
        title: 'RWFIT BLE Demo',
        locale: Locale(_language.name),
        supportedLocales: const [Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: buildDemoTheme(),
        home: const PermissionGate(),
      ),
    );
  }
}

/// 启动时请求蓝牙权限，通过后进入功能主页（落地页）。
class PermissionGate extends StatefulWidget {
  const PermissionGate({super.key});

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate> {
  _PermissionStatus _status = _PermissionStatus.requesting;
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
        _status = allGranted
            ? _PermissionStatus.granted
            : _PermissionStatus.denied;
      });
    } else {
      // iOS 蓝牙权限在首次使用时系统自动弹窗
      setState(() {
        _granted = true;
        _status = _PermissionStatus.ready;
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
    final statusText = switch (_status) {
      _PermissionStatus.requesting => demoTr(
        '正在请求蓝牙权限...',
        'Requesting Bluetooth permissions...',
      ),
      _PermissionStatus.granted => demoTr('权限已授予', 'Permissions granted'),
      _PermissionStatus.denied => demoTr(
        '部分权限被拒绝，蓝牙功能可能受限',
        'Some permissions were denied; Bluetooth features may be limited',
      ),
      _PermissionStatus.ready => demoTr('权限已就绪', 'Permissions are ready'),
    };
    return Scaffold(
      appBar: AppBar(title: const Text('RWFIT Ble Demo')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(statusText),
            if (!_granted) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _requestPermissions,
                child: Text(demoTr('重新请求权限', 'Request permissions again')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

enum _PermissionStatus { requesting, granted, denied, ready }
