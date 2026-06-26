/// RWFIT 戒指插件 —— 通道基础设施（内部）
///
/// 这一层以 Map 工作（native 边界契约）；类型化只发生在 facade（rwfit_ble.dart）。
library;

import 'package:flutter/services.dart';

const MethodChannel _methodChannel = MethodChannel('rwfit_ble/methods');
const EventChannel _eventChannel = EventChannel('rwfit_ble/events');

/// 调用失败时抛出。`code != 0` 即视为失败。
class RwfitException implements Exception {
  RwfitException(this.code, this.message);

  final int code;
  final String message;

  @override
  String toString() => 'RwfitException($code): $message';
}

/// 请求-响应类调用：成功返回整个 Map，失败抛 [RwfitException]。
Future<Map<String, dynamic>> callAsync(
  String method, [
  Map<String, dynamic>? args,
]) async {
  final raw = await _methodChannel.invokeMethod<Map>(method, args ?? const {});
  final result = (raw ?? const {}).cast<String, dynamic>();
  final code = (result['code'] as num?)?.toInt() ?? -1;
  if (code == 0) return result;
  throw RwfitException(code, (result['msg'] as String?) ?? '未知错误');
}

/// 单 EventChannel 广播流（懒初始化、全局共享）。
Stream<Map<String, dynamic>>? _broadcast;
Stream<Map<String, dynamic>> rwfitEventStream() {
  return _broadcast ??= _eventChannel
      .receiveBroadcastStream()
      .map((e) => (e as Map).cast<String, dynamic>())
      .asBroadcastStream();
}

/// 按 payload 里的 `event` 字段过滤出某一类事件流。
Stream<Map<String, dynamic>> onEvent(String eventName) =>
    rwfitEventStream().where((e) => e['event'] == eventName);

/// 事件名常量（与 uni-app 桥接层一致；值即原生 fireEvent 的 eventName）。
abstract final class RwfitEvents {
  static const scanResult = 'rwfit:scanResult';
  static const scanFinish = 'rwfit:scanFinish';
  static const scanError = 'rwfit:scanError';
  static const connectState = 'rwfit:connectState';
  static const functionMenu = 'rwfit:functionMenu';
  static const healthData = 'rwfit:healthData';
  static const syncProgress = 'rwfit:syncProgress';
  static const syncResult = 'rwfit:syncResult';
  static const syncFinish = 'rwfit:syncFinish';
  static const syncError = 'rwfit:syncError';
  static const otaProgress = 'rwfit:otaProgress';
  static const otaFinish = 'rwfit:otaFinish';
  static const touchEvent = 'rwfit:touchEvent';
}
