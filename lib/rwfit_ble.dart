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

  /// 开始扫描支持的设备；两端均在 10 秒后自动结束。
  Future<void> startScan() => callAsync('startScan');

  Future<void> stopScan() => callAsync('stopScan');

  Stream<BleDevice> get onScanResult =>
      onEvent(RwfitEvents.scanResult).map(BleDevice.fromMap);

  Stream<void> get onScanFinish => onEvent(RwfitEvents.scanFinish).map((_) {});

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

  // =============== 7 项全天健康检测 + PPG（共用 TimedConfig）===============

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

  Future<TimedConfig> getTimedBodyTemperature() async =>
      TimedConfig.fromMap(await callAsync('getTimedBodyTemperature'));
  Future<void> setTimedBodyTemperature(TimedConfig c) =>
      callAsync('setTimedBodyTemperature', c.toMap());

  Future<TimedConfig> getTimedPPG() async =>
      TimedConfig.fromMap(await callAsync('getTimedPPG'));
  Future<void> setTimedPPG(TimedConfig c) =>
      callAsync('setTimedPPG', c.toMap());

  // ==================== 实时测量 ====================

  /// 同一时间只能开启一种；切换前先 [stopRealtimeMeasure]。
  Future<void> startRealtimeMeasure(RealtimeMetric m) =>
      callAsync('controlHealthData', {'key': m.key, 'state': 1});

  Future<void> stopRealtimeMeasure(RealtimeMetric m) =>
      callAsync('controlHealthData', {'key': m.key, 'state': 0});

  Stream<RealtimeData> get onRealtimeData =>
      onEvent(RwfitEvents.healthData).map(RealtimeData.fromMap);

  /// 当前单次实时测量完成。应在 [startRealtimeMeasure] 前订阅。
  Stream<void> get onRealtimeMeasureComplete =>
      onEvent(RwfitEvents.realtimeMeasureComplete).map<void>((_) {});

  // ==================== 多运动 ====================

  /// 查询设备当前运动类型和控制状态。开始新运动前应先调用。
  Future<WorkoutState> getWorkoutState() async =>
      WorkoutState.fromMap(await callAsync('getWorkoutState'));

  /// 开始/继续/暂停/结束多运动。两端统一只返回成功或失败。
  Future<void> controlWorkout(int sportType, WorkoutControlType controlType) {
    if (sportType < 7 || sportType > 161) {
      throw RangeError.range(sportType, 7, 161, 'sportType');
    }
    if (controlType == WorkoutControlType.unknown) {
      throw ArgumentError.value(controlType, 'controlType', '不能发送 unknown');
    }
    return callAsync('controlWorkout', {
      'sportType': sportType,
      'controlType': controlType.value,
    });
  }

  /// 开启或关闭设备实时运动数据通知。
  Future<void> setWorkoutRealtimeEnabled(bool enabled) =>
      callAsync('setWorkoutRealtimeEnabled', {'enabled': enabled});

  Stream<WorkoutRealtimeData> get onWorkoutRealtimeData =>
      onEvent(RwfitEvents.workoutRealtimeData).map(WorkoutRealtimeData.fromMap);

  /// 同步设备保存的多运动报告。
  Future<List<WorkoutReport>> getWorkoutReports() async {
    final data =
        (await callAsync('getWorkoutReports'))['data'] as List? ?? const [];
    return data.map((item) => WorkoutReport.fromMap(item as Map)).toList();
  }

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

  /// 来电控制是平台系统能力；当前仅 Android 原生 SDK 支持。
  Future<void> controlPhone(CallControlAction action) =>
      callAsync('controlPhone', {'action': action.commandValue});

  /// 设备发起的接听/拒接动作；当前仅 Android 上报。
  Stream<CallControlEvent> get onCallControl =>
      onEvent(RwfitEvents.callControl).map(CallControlEvent.fromMap);

  Future<bool> getMuslimCountEnabled() async =>
      (await callAsync('getMuslimCountEnabled'))['enabled'] as bool;

  Future<void> setMuslimCountEnabled(bool enabled) =>
      callAsync('setMuslimCountEnabled', {'enabled': enabled});

  Future<HeartRateAlertConfig> getHeartRateAlert() async =>
      HeartRateAlertConfig.fromMap(await callAsync('getHeartRateAlert'));

  Future<void> setHeartRateAlert(HeartRateAlertConfig config) {
    _validateAlertThreshold(config.highThreshold, 'highThreshold');
    if (config.lowThreshold != null) {
      _validateAlertThreshold(config.lowThreshold!, 'lowThreshold');
    }
    return callAsync('setHeartRateAlert', config.toMap());
  }

  Future<BloodOxygenAlertConfig> getBloodOxygenAlert() async =>
      BloodOxygenAlertConfig.fromMap(await callAsync('getBloodOxygenAlert'));

  Future<void> setBloodOxygenAlert(BloodOxygenAlertConfig config) {
    _validateAlertThreshold(config.lowThreshold, 'lowThreshold');
    return callAsync('setBloodOxygenAlert', config.toMap());
  }

  Stream<HealthAlertEvent> get onHealthAlert =>
      onEvent(RwfitEvents.healthAlert).map(HealthAlertEvent.fromMap);

  Future<int> getVibrationInterval() async =>
      (await callAsync('getVibrationInterval'))['intervalMs'] as int;

  Future<void> setVibrationInterval(int intervalMs) {
    if (intervalMs < 100 || intervalMs > 1000) {
      throw RangeError.range(intervalMs, 100, 1000, 'intervalMs');
    }
    return callAsync('setVibrationInterval', {'intervalMs': intervalMs});
  }

  /// 启动心率校正；过程与最终结果从 [onHeartRateCalibration] 接收。
  Future<void> startHeartRateCalibration() =>
      callAsync('startHeartRateCalibration');

  Stream<HeartRateCalibrationResult> get onHeartRateCalibration => onEvent(
    RwfitEvents.heartRateCalibration,
  ).map(HeartRateCalibrationResult.fromMap);

  Future<bool> getFallDetect() async =>
      (await callAsync('getFallDetect'))['enabled'] as bool;

  Future<void> setFallDetect(bool enabled) =>
      callAsync('setFallDetect', {'enabled': enabled});

  Future<int> getCountReminderInterval() async =>
      (await callAsync('getCountReminderInterval'))['intervalMinutes'] as int;

  Future<void> setCountReminderInterval(int intervalMinutes) {
    if (!const [0, 30, 60, 90, 120].contains(intervalMinutes)) {
      throw ArgumentError.value(
        intervalMinutes,
        'intervalMinutes',
        '仅支持 0、30、60、90、120 分钟',
      );
    }
    return callAsync('setCountReminderInterval', {
      'intervalMinutes': intervalMinutes,
    });
  }

  /// 开启或关闭 PPG/ACC/PPG Red/IR 原始数据采集。
  Future<void> controlSensorRaw(bool enabled, SensorRawSelection selection) =>
      callAsync('controlSensorRaw', {
        'enabled': enabled,
        'sensorType': selection.value,
      });

  Future<List<SensorRawPacket>> getSensorRawHistory() async {
    final data =
        (await callAsync('getSensorRawHistory'))['data'] as List? ?? const [];
    return data.map((item) => SensorRawPacket.fromMap(item as Map)).toList();
  }

  Stream<SensorRawPacket> get onSensorRawData =>
      onEvent(RwfitEvents.sensorRawData).map(SensorRawPacket.fromMap);

  Stream<SensorRawStoppedEvent> get onSensorRawStopped =>
      onEvent(RwfitEvents.sensorRawStopped).map(SensorRawStoppedEvent.fromMap);

  void _validateAlertThreshold(int value, String name) {
    if (value < 0 || value > 254) {
      throw RangeError.range(value, 0, 254, name);
    }
  }

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

  /// 设置 HID 模式。hidOpen: 0=关闭, 1=视频, 2=Book, 3=Music。
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

  /// 跨平台同步完成标记，当前仅发出 100；终态以 [onSyncFinish] /
  /// [onSyncError] 为准，不应作为连续百分比进度使用。
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
  Future<Map<String, dynamic>> getNotificationSwitch() async {
    final switches = (await callAsync('getNotificationSwitch'))['switches'];
    return switches is Map ? switches.cast<String, dynamic>() : const {};
  }
}
