import 'dart:convert';

import 'package:rwfit_ble/rwfit_ble.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 已连接设备的本地持久化（对标 uni-app 的 `uni.setStorageSync('rwfit_saved_device')`）。
///
/// 仅 Demo 演示用：保存最近连接成功的设备，供 home_page 重连。
class DeviceStore {
  DeviceStore._();

  static const _key = 'rwfit_saved_device';
  static const _capabilitiesKey = 'rwfit_saved_capabilities';
  static const _lastSyncKey = 'rwfit_last_health_sync';

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

  static Future<Map<String, dynamic>> loadCapabilities() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_capabilitiesKey);
    if (raw == null || raw.isEmpty) return const {};
    try {
      return (jsonDecode(raw) as Map).cast<String, dynamic>();
    } catch (_) {
      return const {};
    }
  }

  static Future<void> saveCapabilities(
    Map<String, dynamic> capabilities,
  ) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_capabilitiesKey, jsonEncode(capabilities));
  }

  static Future<DateTime?> loadLastSyncAt() async {
    final sp = await SharedPreferences.getInstance();
    final milliseconds = sp.getInt(_lastSyncKey);
    return milliseconds == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  static Future<void> saveLastSyncAt(DateTime value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setInt(_lastSyncKey, value.millisecondsSinceEpoch);
  }

  static Future<void> clearLastSyncAt() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_lastSyncKey);
  }

  /// 用户明确解除绑定后清除设备和已缓存的功能表。
  static Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_key);
    await sp.remove(_capabilitiesKey);
    await sp.remove(_lastSyncKey);
  }
}
