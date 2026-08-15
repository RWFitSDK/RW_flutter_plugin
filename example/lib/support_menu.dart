/// Demo 对设备功能表的统一判断，避免各页面重复拼写 capability key。
class DemoCapabilities {
  const DemoCapabilities(this.raw);

  const DemoCapabilities.empty() : raw = const {};

  final Map<String, dynamic> raw;

  bool has(String key) => raw[key] == true;
}

/// Flutter 桥接公开的 supportMenu key。
abstract final class DemoCapabilityKey {
  static const alarm = 'isAlarm';
  static const brightScreenTime = 'isBrightScreenTime';
  static const brightScreenSleepTime = 'isBrightScreenSleepTime';
  static const workout = 'isSupportWorkout';
  static const muslimSwitch = 'isRememberSwitch';
  static const heartRateAlert = 'isSupportHrReminder';
  static const bloodOxygenAlert = 'isSupportBoReminder';
  static const vibrationLevel = 'isSupportMotoVibrationLevel';
  static const alarmVibrationDuration = 'isSupportAlarmVibrationDuration';
  static const vibrationInterval = 'isSupportVibrationInterval';
  static const step = 'isStep';
  static const sleep = 'isSleep';
  static const heartRate = 'isHr';
  static const bloodOxygen = 'isBloodOxy';
  static const bloodPressure = 'isBloodPress';
  static const bloodSugar = 'isBloodSugar';
  static const hrv = 'isHrv';
  static const pressure = 'isPressure';
  static const muslimCountData = 'isMuslimCountData';
  static const bodyTemperature = 'isBodyTemp';
  static const ppgMonitoring = 'isSupportPPGMonitoring';
  static const temperatureMonitoring = 'isSupportTemperatureMonitoring';
  static const countReminder = 'isSupportCountReminder';
  static const sensorRawPpg = 'isSupportSensorRawPPG';
  static const fallDetect = 'isSupportFallDetect';
  static const findDevice = 'isFindDevice';
  static const takePhoto = 'isTakePhoto';
  static const ledLight = 'isLedLight';
  static const wearDirection = 'isWearDirection';
  static const videoHid = 'isVideoHid';
  static const videoHidBook = 'isVideoHidBook';
  static const videoHidMusic = 'isVideoHidMusic';
  static const raiseBrightScreen = 'isRaiseBrightScreen';
  static const powerOff = 'isPowerOff';
  static const factoryReset = 'isFactoryReset';
  static const pushMessage = 'isPushMessage';
  static const pushMessageSwitch = 'isPushMsgEnableSwitch';
}
