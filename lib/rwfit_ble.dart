/// RWFIT 智能戒指 BLE Flutter 插件 —— 对外统一入口。
///
/// 用法见 README / example。所有请求-响应方法返回 [Future]（失败抛 [RwfitException]）；
/// 设备主动上报通过 typed [Stream] 暴露。
library;

import 'src/rwfit_channels.dart';
import 'src/rwfit_constants.dart';
import 'src/rwfit_models.dart';

export 'src/rwfit_constants.dart';
export 'src/rwfit_models.dart';
export 'src/rwfit_channels.dart' show RwfitException;

/// RWFIT 戒指插件单例。`RwfitBle.instance` 获取。
class RwfitBle {
  RwfitBle._();
  static final RwfitBle instance = RwfitBle._();

  // ==================== 初始化 ====================

  /// 初始化 SDK（应用启动时调用一次）。
  Future<void> init() => callAsync('initSDK');

  Future<String> getSdkVersion() async =>
      (await callAsync('getSDKVersion'))['version'] as String;

  /// 插件版本（格式 pluginVersion_sdkVersion）。
  Future<String> getPluginVersion() async =>
      (await callAsync('getPluginVersion'))['pluginVersion'] as String;

  // ==================== 扫描 ====================

  Future<void> startScan({bool filter = true}) =>
      callAsync('startScan', {'filter': filter});

  Future<void> stopScan() => callAsync('stopScan');

  Stream<BleDevice> get onScanResult =>
      onEvent(RwfitEvents.scanResult).map(BleDevice.fromMap);

  Stream<void> get onScanFinish => onEvent(RwfitEvents.scanFinish).map((_) {});

  Stream<Map<String, dynamic>> get onScanError =>
      onEvent(RwfitEvents.scanError);

  // ==================== 连接 ====================

  /// 直接传扫描得到的 [BleDevice]（含 iOS uuid），内部 toMap 回传原生。
  Future<void> connect(BleDevice device) =>
      callAsync('connectDevice', device.toMap());

  Future<void> disconnect() => callAsync('disconnect');

  /// [iOS 专用] 设置绑定状态；Android no-op。
  Future<void> iosSetBindedStatus(bool isBinded) =>
      callAsync('iOSSetBindedStatus', {'isBinded': isBinded});

  /// 重连已绑定设备。Android 必传 device(mac)；iOS 可传空走内置重连。
  Future<void> reconnect([BleDevice? device]) =>
      callAsync('reconnectDevice', device?.toMap() ?? const {});

  Future<bool> isConnected() async =>
      (await callAsync('isBleConnected'))['connected'] as bool;

  Stream<ConnectStateEvent> get onConnectState =>
      onEvent(RwfitEvents.connectState).map(ConnectStateEvent.fromMap);

  /// 设备功能表就绪（真正可用信号）；收到后才可发业务指令。
  Stream<FunctionMenu> get onFunctionMenu =>
      onEvent(RwfitEvents.functionMenu).map(FunctionMenu.fromMap);

  // ==================== 设备信息 ====================

  Future<int> getPower() async => (await callAsync('getPower'))['power'] as int;

  Future<FirmwareInfo> getFirmwareVersion() async =>
      FirmwareInfo.fromMap(await callAsync('getFirmwareVersion'));

  Future<void> setUserInfo(UserInfo info) =>
      callAsync('setUserInfo', info.toMap());

  Future<void> setTimeFormat(int format) =>
      callAsync('setTimeFormat', {'format': format});

  /// 设备支持的功能列表（动态结构，保留 Map 逃生舱）。
  Future<Map<String, dynamic>> getFunctionList() =>
      callAsync('getFunctionList');

  Future<void> setRingBtName(String name) =>
      callAsync('setRingBtName', {'name': name});

  // ==================== 全天检测（6 项共用 TimedConfig）====================

  Future<TimedConfig> getTimedHeartRate() async =>
      TimedConfig.fromMap(await callAsync('getTimedHeartRate'));
  Future<void> setTimedHeartRate(TimedConfig c) =>
      callAsync('setTimedHeartRate', c.toMap());

  Future<TimedConfig> getTimedBloodOxygen() async =>
      TimedConfig.fromMap(await callAsync('getTimedBloodOxygen'));
  Future<void> setTimedBloodOxygen(TimedConfig c) =>
      callAsync('setTimedBloodOxygen', c.toMap());

  Future<TimedConfig> getTimedHRV() async =>
      TimedConfig.fromMap(await callAsync('getTimedHRV'));
  Future<void> setTimedHRV(TimedConfig c) =>
      callAsync('setTimedHRV', c.toMap());

  Future<TimedConfig> getTimedStress() async =>
      TimedConfig.fromMap(await callAsync('getTimedStress'));
  Future<void> setTimedStress(TimedConfig c) =>
      callAsync('setTimedStress', c.toMap());

  Future<TimedConfig> getTimedBloodSugar() async =>
      TimedConfig.fromMap(await callAsync('getTimedBloodSugar'));
  Future<void> setTimedBloodSugar(TimedConfig c) =>
      callAsync('setTimedBloodSugar', c.toMap());

  Future<TimedConfig> getTimedBloodPressure() async =>
      TimedConfig.fromMap(await callAsync('getTimedBloodPressure'));
  Future<void> setTimedBloodPressure(TimedConfig c) =>
      callAsync('setTimedBloodPressure', c.toMap());

  // ==================== 实时测量 ====================

  /// 同一时间只能开启一种；切换前先 [stopRealtimeMeasure]。
  Future<void> startRealtimeMeasure(RealtimeMetric m) =>
      callAsync('controlHealthData', {'key': m.key, 'state': 1});

  Future<void> stopRealtimeMeasure(RealtimeMetric m) =>
      callAsync('controlHealthData', {'key': m.key, 'state': 0});

  Stream<RealtimeData> get onRealtimeData =>
      onEvent(RwfitEvents.healthData).map(RealtimeData.fromMap);

  // ==================== 设备控制 ====================

  Future<void> findDevice() => callAsync('controlFindDevice');

  Future<void> powerOff() =>
      callAsync('setPowerOff', {'type': PowerOffType.shutdown.value});

  Future<void> factoryReset() =>
      callAsync('setPowerOff', {'type': PowerOffType.factoryReset.value});

  /// 拍照控制：state=1 进入拍照模式, 0 退出。触发经 [onTouchEvent]（action=cameraTakePicture）。
  Future<void> controlPhoto(int state) =>
      callAsync('controlTakePhoto', {'state': state});

  /// 拍照触发 / 物理键 / 音乐控制统一从这里来（按 action 区分）。
  Stream<TouchEvent> get onTouchEvent =>
      onEvent(RwfitEvents.touchEvent).map(TouchEvent.fromMap);

  // ---- 闹钟（全量下发）----

  Future<List<Alarm>> getAlarm() async {
    final data = (await callAsync('getAlarm'))['data'] as List? ?? const [];
    return data.map((e) => Alarm.fromMap(e as Map)).toList();
  }

  Future<void> setAlarm(List<Alarm> alarms) =>
      callAsync('setAlarm', {'alarms': alarms.map((a) => a.toMap()).toList()});

  Future<void> deleteAllAlarm() => callAsync('deleteAllAlarm');

  // ---- 屏幕 ----

  Future<ScheduleToggle> getRaiseBrightScreen() async =>
      ScheduleToggle.fromMap(await callAsync('getRaiseBrightScreen'));
  Future<void> setRaiseBrightScreen(ScheduleToggle c) =>
      callAsync('setRaiseBrightScreen', c.toMap());

  Future<int> getBrightScreenTime() async =>
      (await callAsync('getBrightScreenTime'))['timeSecond'] as int;
  Future<void> setBrightScreenTime(int timeSecond) =>
      callAsync('setBrightScreenTime', {'timeSecond': timeSecond});

  Future<ScheduleToggle> getBrightScreenSleepTime() async =>
      ScheduleToggle.fromMap(await callAsync('getBrightScreenSleepTime'));
  Future<void> setBrightScreenSleepTime(ScheduleToggle c) =>
      callAsync('setBrightScreenSleepTime', c.toMap());

  Future<LedLevel> getRingLedLevel() async =>
      LedLevel.fromMap(await callAsync('getRingLedLevel'));
  Future<void> setRingLedLevel(LedLevel c) =>
      callAsync('setRingLedLevel', c.toMap());

  // ---- 视频 HID / HID 配对 ----

  Future<int> getVideoHid() async =>
      (await callAsync('getVideoHid'))['hidOpen'] as int;
  Future<void> setVideoHid(int hidOpen) =>
      callAsync('setVideoHid', {'hidOpen': hidOpen});

  /// [Android 专用] 蓝牙 HID 配对/取消（type: 1=配对, 2=取消）；iOS no-op。
  Future<bool> createOrRemoveBond(int type, String mac) async =>
      (await callAsync('createOrRemoveBond', {
            'type': type,
            'mac': mac,
          }))['result']
          as bool? ??
      false;

  // ---- 佩戴方向 ----

  Future<bool> getRingWearDir() async =>
      (await callAsync('getRingWearDir'))['isRight'] as bool;
  Future<void> setRingWearHand(bool isRight) =>
      callAsync('setRingWearHand', {'isRight': isRight});

  // ---- 振动 ----

  Future<VibrationConfig> getVibrationCount() async =>
      VibrationConfig.fromMap(await callAsync('getVibrationCount'));
  Future<void> setVibrationCount(VibrationConfig c) =>
      callAsync('setVibrationCount', c.toMap());

  Future<int> getAlarmVibrationDuration() async =>
      (await callAsync('getAlarmVibrationDuration'))['duration'] as int;
  Future<void> setAlarmVibrationDuration(int duration) =>
      callAsync('setAlarmVibrationDuration', {'duration': duration});

  // ==================== 数据同步 ====================

  Future<void> syncAllHealthData() => callAsync('syncAllHealthData');

  Future<void> removeHealthDataCallback() =>
      callAsync('removeHealthDataCallback');

  Stream<double> get onSyncProgress => onEvent(
    RwfitEvents.syncProgress,
  ).map((m) => (m['progress'] as num).toDouble());

  Stream<SyncResult> get onSyncResult =>
      onEvent(RwfitEvents.syncResult).map(SyncResult.fromMap);

  Stream<void> get onSyncFinish => onEvent(RwfitEvents.syncFinish).map((_) {});

  Stream<Map<String, dynamic>> get onSyncError =>
      onEvent(RwfitEvents.syncError);

  // ==================== OTA ====================

  Future<void> ringOta(String path) => callAsync('ringOta', {'path': path});

  Stream<double> get onOtaProgress => onEvent(
    RwfitEvents.otaProgress,
  ).map((m) => (m['progress'] as num).toDouble());

  Stream<OtaResult> get onOtaFinish =>
      onEvent(RwfitEvents.otaFinish).map(OtaResult.fromMap);

  // ==================== 解绑 ====================

  Future<void> unbind() => callAsync('unbind');

  // ==================== 消息推送 / 通知开关 ====================

  /// [Android 专用] APP 主动推消息到设备；iOS no-op。
  Future<void> pushMessage(Map<String, dynamic> msg) =>
      callAsync('pushMessage', msg);

  /// [iOS 专用] 设置 ANCS 转发开关；Android no-op。
  Future<void> setNotificationSwitch(Map<String, dynamic> switches) =>
      callAsync('setNotificationSwitch', switches);

  /// [iOS 专用] 获取 ANCS 转发开关；Android 返回 {}。
  Future<Map<String, dynamic>> getNotificationSwitch() async =>
      (await callAsync('getNotificationSwitch'))['switches']
          as Map<String, dynamic>? ??
      const {};
}
