import 'dart:convert';

import 'package:rwfit_ble/rwfit_ble.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 已连接设备的本地持久化（对标 uni-app 的 `uni.setStorageSync('rwfit_saved_device')`）。
///
/// 仅 Demo 演示用：保存最近连接成功的设备，供 home_page 重连。
class DeviceStore {
  DeviceStore._();

  static const _key = 'rwfit_saved_device';

  /// 读取已保存设备；无则返回 null。
  static Future<BleDevice?> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return BleDevice.fromMap(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  /// 保存设备（连接就绪后调用）。
  static Future<void> save(BleDevice device) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, jsonEncode(device.toMap()));
  }

  /// 清除已保存设备（进扫描页时调用，防止旧设备误重连）。
  static Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_key);
  }
}
