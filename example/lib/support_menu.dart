import 'package:rwfit_ble/rwfit_ble.dart';

/// Demo 对设备功能表的统一判断，避免各页面重复拼写 capability key。
class DemoCapabilities {
  const DemoCapabilities(this.raw);

  const DemoCapabilities.empty() : raw = const {};

  final Map<String, dynamic> raw;

  bool has(String key) => raw[key] == true;

  bool any(Iterable<String> keys) => keys.any(has);

  bool all(Iterable<String> keys) => keys.every(has);

  bool get supportsWorkout => has(DemoCapabilityKey.workout);

  bool get supportsAnyTimedMonitor => any(DemoCapabilityKey.timedMonitor);

  bool get supportsAnyRealtime => any(DemoCapabilityKey.realtime);

  bool get supportsAnyHealthAlert => any(DemoCapabilityKey.healthAlert);

  bool get supportsAnySensorRaw => any(DemoCapabilityKey.sensorRaw);

  bool get supportsAnyHealthData => any(DemoCapabilityKey.healthData);

  bool get supportsAnyDeviceControl => any(DemoCapabilityKey.deviceControl);

  bool supportsRealtime(RealtimeMetric metric) => switch (metric) {
    RealtimeMetric.hr => has(DemoCapabilityKey.heartRate),
    RealtimeMetric.bloodOxy => has(DemoCapabilityKey.bloodOxygen),
    RealtimeMetric.hrv => has(DemoCapabilityKey.hrv),
    RealtimeMetric.pressure => has(DemoCapabilityKey.pressure),
    RealtimeMetric.bloodSugar => has(DemoCapabilityKey.bloodSugar),
    RealtimeMetric.bloodPressure => has(DemoCapabilityKey.bloodPressure),
  };

  bool supportsSensorSelection(SensorRawSelection selection) =>
      all(switch (selection) {
        SensorRawSelection.acc => const [DemoCapabilityKey.sensorRawAcc],
        SensorRawSelection.ppgGreen => const [DemoCapabilityKey.sensorRawPpg],
        SensorRawSelection.ppgGreenAndAcc => const [
          DemoCapabilityKey.sensorRawPpg,
          DemoCapabilityKey.sensorRawAcc,
        ],
        SensorRawSelection.ppgRed => const [DemoCapabilityKey.sensorRawPpgRed],
        SensorRawSelection.ppgRedAndAcc => const [
          DemoCapabilityKey.sensorRawPpgRed,
          DemoCapabilityKey.sensorRawAcc,
        ],
        SensorRawSelection.ppgGreenAndIr => const [
          DemoCapabilityKey.sensorRawPpg,
          DemoCapabilityKey.sensorRawIr,
        ],
        SensorRawSelection.ppgGreenAccAndIr => const [
          DemoCapabilityKey.sensorRawPpg,
          DemoCapabilityKey.sensorRawAcc,
          DemoCapabilityKey.sensorRawIr,
        ],
        SensorRawSelection.ppgRedAndIr => const [
          DemoCapabilityKey.sensorRawPpgRed,
          DemoCapabilityKey.sensorRawIr,
        ],
        SensorRawSelection.ppgRedAccAndIr => const [
          DemoCapabilityKey.sensorRawPpgRed,
          DemoCapabilityKey.sensorRawAcc,
          DemoCapabilityKey.sensorRawIr,
        ],
      });
}

/// Flutter 桥接公开的 supportMenu key。
abstract final class DemoCapabilityKey {
  static const alarm = 'isAlarm';
  static const brightScreenTime = 'isBrightScreenTime';
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
  static const sensorRawAcc = 'isSupportSensorRawACC';
  static const sensorRawPpg = 'isSupportSensorRawPPG';
  static const sensorRawPpgRed = 'isSupportSensorRawPPGRed';
  static const sensorRawIr = 'isSupportSensorRawIR';
  static const sensorRawSleep = 'isSupportSensorRawSleep';
  static const fallDetect = 'isSupportFallDetect';
  static const findDevice = 'isFindDevice';
  static const takePhoto = 'isTakePhoto';
  static const ledLight = 'isLedLight';
  static const wearDirection = 'isWearDirection';
  static const videoHid = 'isVideoHid';
  static const raiseBrightScreen = 'isRaiseBrightScreen';
  static const powerOff = 'isPowerOff';
  static const factoryReset = 'isFactoryReset';
  static const pushMessage = 'isPushMessage';
  static const pushMessageSwitch = 'isPushMsgEnableSwitch';

  static const timedMonitor = [
    heartRate,
    bloodOxygen,
    hrv,
    pressure,
    bloodSugar,
    bloodPressure,
    temperatureMonitoring,
    ppgMonitoring,
  ];

  static const realtime = [
    heartRate,
    bloodOxygen,
    hrv,
    pressure,
    bloodSugar,
    bloodPressure,
  ];

  static const healthAlert = [muslimSwitch, heartRateAlert, bloodOxygenAlert];

  static const sensorRaw = [
    sensorRawPpg,
    sensorRawAcc,
    sensorRawPpgRed,
    sensorRawIr,
    sensorRawSleep,
  ];

  static const healthData = [
    step,
    sleep,
    heartRate,
    bloodOxygen,
    bloodPressure,
    bloodSugar,
    hrv,
    pressure,
    muslimCountData,
    bodyTemperature,
  ];

  static const deviceControl = [
    findDevice,
    powerOff,
    factoryReset,
    takePhoto,
    ledLight,
    wearDirection,
    vibrationLevel,
    vibrationInterval,
    fallDetect,
    countReminder,
    raiseBrightScreen,
    brightScreenTime,
    videoHid,
    alarmVibrationDuration,
  ];
}
