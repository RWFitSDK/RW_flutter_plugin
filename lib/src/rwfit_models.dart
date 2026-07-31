/// RWFIT 戒指插件 —— 数据模型
///
/// 建模规则（见开发文档 §0 第 4 条）：稳定多字段 / 列表 item / get→改→set 往返
/// 结构用 model（带 fromMap/toMap，必要时 copyWith）；真正动态的明细保留 Map 逃生舱。
library;

import 'rwfit_constants.dart';

const Object _notProvided = Object();

/// 蓝牙设备。`uuid` 仅 iOS 有且为设备主标识——连接时必须整条回传。
class BleDevice {
  const BleDevice({
    required this.name,
    required this.mac,
    required this.rssi,
    this.uuid,
  });

  final String name;
  final String mac;
  final int rssi;
  final String? uuid;

  factory BleDevice.fromMap(Map<dynamic, dynamic> m) => BleDevice(
    name: (m['name'] ?? '') as String,
    mac: (m['mac'] ?? '') as String,
    rssi: (m['rssi'] as num?)?.toInt() ?? 0,
    uuid: m['uuid'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'mac': mac,
    'rssi': rssi,
    if (uuid != null) 'uuid': uuid,
  };
}

/// 连接状态事件。`uuid` 仅 iOS；`reason` 仅 failed。
///
/// Android 的 `reason` 是原生错误枚举名；iOS 原生失败回调不含错误参数，
/// 因此固定为 `unknown`。
class ConnectStateEvent {
  const ConnectStateEvent({
    required this.state,
    this.name,
    this.mac,
    this.uuid,
    this.reason,
  });

  final ConnectState state;
  final String? name;
  final String? mac;
  final String? uuid;
  final String? reason;

  factory ConnectStateEvent.fromMap(Map<dynamic, dynamic> m) =>
      ConnectStateEvent(
        state: ConnectState.values.byName(m['state'] as String),
        name: m['name'] as String?,
        mac: m['mac'] as String?,
        uuid: m['uuid'] as String?,
        reason: m['reason'] as String?,
      );
}

/// 设备功能配置表就绪事件。`raw` 是 supportMenu 原始能力表，App 自行读位做灰显/隐藏。
///
class FunctionMenu {
  const FunctionMenu({
    required this.name,
    required this.mac,
    this.uuid,
    required this.raw,
  });

  final String name;
  final String mac;
  final String? uuid;
  final Map<String, dynamic> raw;

  factory FunctionMenu.fromMap(Map<dynamic, dynamic> m) => FunctionMenu(
    name: (m['name'] ?? '') as String,
    mac: (m['mac'] ?? '') as String,
    uuid: m['uuid'] as String?,
    raw: (m['supportMenu'] as Map?)?.cast<String, dynamic>() ?? const {},
  );

  bool get supportsWorkout => raw['isSupportWorkout'] == true;
}

/// 设备当前多运动状态。
class WorkoutState {
  const WorkoutState({required this.sportType, required this.controlType});

  final int sportType;
  final WorkoutControlType controlType;

  bool get isRunning => controlType.isRunning;

  factory WorkoutState.fromMap(Map<dynamic, dynamic> m) => WorkoutState(
    sportType: (m['sportType'] as num?)?.toInt() ?? 0,
    controlType: WorkoutControlType.fromValue(
      (m['controlType'] as num?)?.toInt() ?? -1,
    ),
  );

  Map<String, dynamic> toMap() => {
    'sportType': sportType,
    'controlType': controlType.value,
  };
}

/// 实时健康数据。原生桥接统一传 Unix 秒，对外规范字段为 [timestampSec]。
class RealtimeData {
  /// 兼容旧代码使用毫秒构造；新代码应使用 [RealtimeData.fromSeconds]。
  @Deprecated('Use RealtimeData.fromSeconds instead.')
  const RealtimeData({
    this.type,
    required this.value,
    this.diastolic,
    required int timestampMs,
  }) : timestampSec = timestampMs ~/ 1000;

  const RealtimeData.fromSeconds({
    this.type,
    required this.value,
    this.diastolic,
    required this.timestampSec,
  });

  final HealthType? type;
  final double value;
  final int? diastolic; // 仅血压
  final int timestampSec;

  /// 旧版毫秒字段的兼容访问；新代码请使用 [timestampSec]。
  @Deprecated('Use timestampSec instead.')
  int get timestampMs => timestampSec * 1000;

  factory RealtimeData.fromMap(Map<dynamic, dynamic> m) =>
      RealtimeData.fromSeconds(
        type: HealthType.fromValue((m['dataType'] as num).toInt()),
        value: (m['dataValue'] as num).toDouble(),
        diastolic: (m['diastolic'] as num?)?.toInt(),
        timestampSec: (m['time'] as num).toInt(),
      );
}

/// 多运动中的实时统计。
class WorkoutRealtimeData {
  const WorkoutRealtimeData({
    required this.duration,
    required this.steps,
    required this.distance,
    required this.calorie,
    required this.heartRate,
    required this.dataType,
    required this.rawDataType,
  });

  final int duration; // 秒
  final int steps;
  final int distance; // 米
  final int calorie; // 卡
  final int heartRate;
  final WorkoutDataType dataType;
  final int rawDataType;

  factory WorkoutRealtimeData.fromMap(Map<dynamic, dynamic> m) {
    final rawDataType = (m['dataType'] as num?)?.toInt() ?? -1;
    return WorkoutRealtimeData(
      duration: (m['duration'] as num?)?.toInt() ?? 0,
      steps: (m['steps'] as num?)?.toInt() ?? 0,
      distance: (m['distance'] as num?)?.toInt() ?? 0,
      calorie: (m['calorie'] as num?)?.toInt() ?? 0,
      heartRate: (m['heartRate'] as num?)?.toInt() ?? 0,
      dataType: WorkoutDataType.fromValue(rawDataType),
      rawDataType: rawDataType,
    );
  }
}

/// 同步结果。`data` 为动态明细（不逐字段建模），原样给 App。
class SyncResult {
  const SyncResult({required this.type, required this.data});

  final String
  type; // step/sleep/hr/bp/bo/temp/pressure/bloodSugar/hrv/muslimCount
  final List<Map<String, dynamic>> data;

  factory SyncResult.fromMap(Map<dynamic, dynamic> m) => SyncResult(
    type: (m['type'] ?? '') as String,
    data:
        (m['data'] as List?)
            ?.map((e) => (e as Map).cast<String, dynamic>())
            .toList() ??
        const [],
  );
}

/// 多运动历史报告中的通用 index/value 项。
class WorkoutValueItem {
  const WorkoutValueItem({required this.index, required this.value});

  final int index;
  final int value;

  factory WorkoutValueItem.fromMap(Map<dynamic, dynamic> m) => WorkoutValueItem(
    index: (m['index'] as num?)?.toInt() ?? 0,
    value: (m['value'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toMap() => {'index': index, 'value': value};
}

/// 已保存的多运动报告。桥接层已统一 Android/iOS 字段名和数值类型。
class WorkoutReport {
  const WorkoutReport({
    required this.startTime,
    required this.endTime,
    required this.date,
    required this.sportType,
    required this.duration,
    required this.step,
    required this.distance,
    required this.calorie,
    required this.height,
    required this.pressure,
    required this.cadence,
    required this.speed,
    required this.pace,
    required this.averageHeartRate,
    required this.maxHeartRate,
    required this.minHeartRate,
    required this.maxCadence,
    required this.minCadence,
    required this.maxPace,
    required this.minPace,
    required this.heartRateCount,
    required this.viewType,
    required this.heartRateItems,
    required this.pacePerKmItems,
  });

  final int startTime; // 秒
  final int endTime; // 秒
  final String date; // yyyyMMdd
  final int sportType;
  final int duration; // 秒
  final int step;
  final int distance; // 米
  final int calorie; // 卡
  final int height;
  final int pressure;
  final int cadence;
  final double speed;
  final int pace;
  final int averageHeartRate;
  final int maxHeartRate;
  final int minHeartRate;
  final int maxCadence;
  final int minCadence;
  final int maxPace;
  final int minPace;
  final int heartRateCount;
  final int viewType;
  final List<WorkoutValueItem> heartRateItems;
  final List<WorkoutValueItem> pacePerKmItems;

  factory WorkoutReport.fromMap(Map<dynamic, dynamic> m) => WorkoutReport(
    startTime: (m['startTime'] as num?)?.toInt() ?? 0,
    endTime: (m['endTime'] as num?)?.toInt() ?? 0,
    date: (m['date'] ?? '') as String,
    sportType: (m['sportType'] as num?)?.toInt() ?? 0,
    duration: (m['duration'] as num?)?.toInt() ?? 0,
    step: (m['step'] as num?)?.toInt() ?? 0,
    distance: (m['distance'] as num?)?.toInt() ?? 0,
    calorie: (m['calorie'] as num?)?.toInt() ?? 0,
    height: (m['height'] as num?)?.toInt() ?? 0,
    pressure: (m['pressure'] as num?)?.toInt() ?? 0,
    cadence: (m['cadence'] as num?)?.toInt() ?? 0,
    speed: (m['speed'] as num?)?.toDouble() ?? 0,
    pace: (m['pace'] as num?)?.toInt() ?? 0,
    averageHeartRate: (m['averageHeartRate'] as num?)?.toInt() ?? 0,
    maxHeartRate: (m['maxHeartRate'] as num?)?.toInt() ?? 0,
    minHeartRate: (m['minHeartRate'] as num?)?.toInt() ?? 0,
    maxCadence: (m['maxCadence'] as num?)?.toInt() ?? 0,
    minCadence: (m['minCadence'] as num?)?.toInt() ?? 0,
    maxPace: (m['maxPace'] as num?)?.toInt() ?? 0,
    minPace: (m['minPace'] as num?)?.toInt() ?? 0,
    heartRateCount: (m['heartRateCount'] as num?)?.toInt() ?? 0,
    viewType: (m['viewType'] as num?)?.toInt() ?? 0,
    heartRateItems:
        (m['heartRateItems'] as List?)
            ?.map((item) => WorkoutValueItem.fromMap(item as Map))
            .toList() ??
        const [],
    pacePerKmItems:
        (m['pacePerKmItems'] as List?)
            ?.map((item) => WorkoutValueItem.fromMap(item as Map))
            .toList() ??
        const [],
  );
}

/// 触摸 / 物理键 / 拍照 / 音乐事件（统一经 rwfit:touchEvent）。
class TouchEvent {
  const TouchEvent({
    required this.action,
    required this.rawAction,
    this.keyType = 0,
    this.touchType = 0,
  });

  final TouchAction action;
  final String rawAction; // 原始字符串，便于将来新增 action 不丢
  final int keyType;
  final int touchType;

  factory TouchEvent.fromMap(Map<dynamic, dynamic> m) => TouchEvent(
    action: TouchAction.parse(m['action'] as String?),
    rawAction: (m['action'] ?? '') as String,
    keyType: (m['keyType'] as num?)?.toInt() ?? 0,
    touchType: (m['touchType'] as num?)?.toInt() ?? 0,
  );
}

/// 设备发起的来电控制事件。
class CallControlEvent {
  const CallControlEvent({required this.action, required this.rawValue});

  final CallControlAction? action;
  final int rawValue;

  factory CallControlEvent.fromMap(Map<dynamic, dynamic> m) => CallControlEvent(
    action: CallControlAction.parse(m['action'] as String?),
    rawValue: (m['rawValue'] as num?)?.toInt() ?? -1,
  );
}

/// 心率报警配置。
class HeartRateAlertConfig {
  const HeartRateAlertConfig({
    required this.isOpen,
    required this.highThreshold,
    this.lowThreshold,
  });

  final bool isOpen;
  final int highThreshold;

  /// 低心率阈值；null 表示设备不支持低心率报警。
  final int? lowThreshold;

  factory HeartRateAlertConfig.fromMap(Map<dynamic, dynamic> m) =>
      HeartRateAlertConfig(
        isOpen: m['isOpen'] as bool? ?? false,
        highThreshold: (m['highThreshold'] as num?)?.toInt() ?? 160,
        lowThreshold: (m['lowThreshold'] as num?)?.toInt(),
      );

  Map<String, dynamic> toMap() => {
    'isOpen': isOpen,
    'highThreshold': highThreshold,
    'lowThreshold': lowThreshold,
  };

  HeartRateAlertConfig copyWith({
    bool? isOpen,
    int? highThreshold,
    Object? lowThreshold = _notProvided,
  }) => HeartRateAlertConfig(
    isOpen: isOpen ?? this.isOpen,
    highThreshold: highThreshold ?? this.highThreshold,
    lowThreshold: identical(lowThreshold, _notProvided)
        ? this.lowThreshold
        : lowThreshold as int?,
  );
}

/// 血氧过低报警配置。
class BloodOxygenAlertConfig {
  const BloodOxygenAlertConfig({
    required this.isOpen,
    required this.lowThreshold,
  });

  final bool isOpen;
  final int lowThreshold;

  factory BloodOxygenAlertConfig.fromMap(Map<dynamic, dynamic> m) =>
      BloodOxygenAlertConfig(
        isOpen: m['isOpen'] as bool? ?? false,
        // 双端协议默认阈值为 94%；Android Bean 的 95 初始值会被设备读取结果覆盖。
        lowThreshold: (m['lowThreshold'] as num?)?.toInt() ?? 94,
      );

  Map<String, dynamic> toMap() => {
    'isOpen': isOpen,
    'lowThreshold': lowThreshold,
  };

  BloodOxygenAlertConfig copyWith({bool? isOpen, int? lowThreshold}) =>
      BloodOxygenAlertConfig(
        isOpen: isOpen ?? this.isOpen,
        lowThreshold: lowThreshold ?? this.lowThreshold,
      );
}

/// 设备主动上报的心率/血氧报警。
class HealthAlertEvent {
  const HealthAlertEvent({
    required this.type,
    required this.rawType,
    required this.value,
  });

  final HealthAlertType type;
  final int rawType;
  final int value;

  factory HealthAlertEvent.fromMap(Map<dynamic, dynamic> m) {
    final rawType = (m['type'] as num?)?.toInt() ?? -1;
    return HealthAlertEvent(
      type: HealthAlertType.fromValue(rawType),
      rawType: rawType,
      value: (m['value'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 心率校正过程事件。设备通常先上报 result=0，再上报非 0 的最终结果。
class HeartRateCalibrationResult {
  const HeartRateCalibrationResult({
    required this.testMode,
    required this.result,
  });

  final int testMode;
  final int result;

  bool get isCalibrating => result == 0;
  bool get isCompleted => result != 0;

  factory HeartRateCalibrationResult.fromMap(Map<dynamic, dynamic> m) =>
      HeartRateCalibrationResult(
        testMode: (m['testMode'] as num?)?.toInt() ?? 0,
        result: (m['result'] as num?)?.toInt() ?? 0,
      );
}

/// ACC 三轴原始采样值。
class AccRawSample {
  const AccRawSample({required this.x, required this.y, required this.z});

  final int x;
  final int y;
  final int z;

  factory AccRawSample.fromMap(Map<dynamic, dynamic> m) => AccRawSample(
    x: (m['x'] as num?)?.toInt() ?? 0,
    y: (m['y'] as num?)?.toInt() ?? 0,
    z: (m['z'] as num?)?.toInt() ?? 0,
  );
}

/// 睡眠状态原始采样值。
class SleepRawSample {
  const SleepRawSample({required this.timestampSec, required this.mode});

  final int timestampSec;
  final int mode;

  factory SleepRawSample.fromMap(Map<dynamic, dynamic> m) => SleepRawSample(
    timestampSec: (m['timestampSec'] as num?)?.toInt() ?? 0,
    mode: (m['mode'] as num?)?.toInt() ?? 0,
  );
}

/// 传感器原始数据包；实时通知与历史同步使用同一结构。
class SensorRawPacket {
  const SensorRawPacket({
    required this.type,
    required this.rawType,
    this.sequence,
    this.timestampSec,
    this.ppg = const [],
    this.acc = const [],
    this.ppgRed = const [],
    this.ir = const [],
    this.sleep = const [],
  });

  final SensorRawDataType type;
  final int rawType;
  final int? sequence;
  final int? timestampSec;
  final List<int> ppg;
  final List<AccRawSample> acc;
  final List<int> ppgRed;
  final List<int> ir;
  final List<SleepRawSample> sleep;

  factory SensorRawPacket.fromMap(Map<dynamic, dynamic> m) {
    final rawType = (m['type'] as num?)?.toInt() ?? -1;
    return SensorRawPacket(
      type: SensorRawDataType.fromValue(rawType),
      rawType: rawType,
      sequence: (m['sequence'] as num?)?.toInt(),
      timestampSec: (m['timestampSec'] as num?)?.toInt(),
      ppg:
          (m['ppg'] as List?)?.map((v) => (v as num).toInt()).toList() ??
          const [],
      acc:
          (m['acc'] as List?)
              ?.map((v) => AccRawSample.fromMap(v as Map))
              .toList() ??
          const [],
      ppgRed:
          (m['ppgRed'] as List?)?.map((v) => (v as num).toInt()).toList() ??
          const [],
      ir:
          (m['ir'] as List?)?.map((v) => (v as num).toInt()).toList() ??
          const [],
      sleep:
          (m['sleep'] as List?)
              ?.map((v) => SleepRawSample.fromMap(v as Map))
              .toList() ??
          const [],
    );
  }
}

/// 设备主动停止传感器采集事件；0 表示原生层未提供具体原因。
class SensorRawStoppedEvent {
  const SensorRawStoppedEvent({required this.reason});

  final int reason;

  factory SensorRawStoppedEvent.fromMap(Map<dynamic, dynamic> m) =>
      SensorRawStoppedEvent(reason: (m['reason'] as num?)?.toInt() ?? 0);
}

/// OTA 结束：成功 payload {}、失败 {code}。
class OtaResult {
  const OtaResult({required this.success, this.code});

  final bool success;
  final int? code; // 仅失败有

  factory OtaResult.fromMap(Map<dynamic, dynamic> m) => OtaResult(
    success: !m.containsKey('code'),
    code: (m['code'] as num?)?.toInt(),
  );
}

/// 固件版本信息。
class FirmwareInfo {
  const FirmwareInfo({
    required this.deviceClazz,
    required this.deviceNo,
    required this.uiVersion,
  });

  final String deviceClazz; // 设备型号
  final String deviceNo; // 固件版本
  final String uiVersion; // UI 版本

  factory FirmwareInfo.fromMap(Map<dynamic, dynamic> m) => FirmwareInfo(
    deviceClazz: (m['deviceClazz'] ?? '') as String,
    deviceNo: (m['deviceNo'] ?? '') as String,
    uiVersion: (m['uiVersion'] ?? '') as String,
  );
}

/// 用户信息。gender: 0=女, 1=男；height/weight 浮点。
class UserInfo {
  const UserInfo({
    required this.gender,
    required this.age,
    required this.height,
    required this.weight,
  });

  final int gender;
  final int age;
  final double height;
  final double weight;

  Map<String, dynamic> toMap() => {
    'gender': gender,
    'age': age,
    'height': height,
    'weight': weight,
  };
}

/// 闹钟项。设备协议仅使用 ID、时间、开关和重复星期。
class Alarm {
  const Alarm({
    required this.alarmId,
    required this.startHour,
    required this.startMin,
    required this.isOpen,
    this.repeats = const [0, 0, 0, 0, 0, 0, 0],
  });

  final int alarmId;
  final int startHour;
  final int startMin;
  final bool isOpen;
  final List<int> repeats; // 长度 7：周日~周六（index 0=周日）

  factory Alarm.fromMap(Map<dynamic, dynamic> m) => Alarm(
    alarmId: (m['alarmId'] as num).toInt(),
    startHour: (m['startHour'] as num).toInt(),
    startMin: (m['startMin'] as num).toInt(),
    isOpen: m['isOpen'] == true,
    repeats:
        (m['repeats'] as List?)?.map((e) => (e as num).toInt()).toList() ??
        const [0, 0, 0, 0, 0, 0, 0],
  );

  Map<String, dynamic> toMap() => {
    'alarmId': alarmId,
    'startHour': startHour,
    'startMin': startMin,
    'isOpen': isOpen,
    'repeats': repeats,
  };

  /// 改一条再整批回发的核心：getAlarm → copyWith → setAlarm（全量下发）。
  Alarm copyWith({
    int? alarmId,
    int? startHour,
    int? startMin,
    bool? isOpen,
    List<int>? repeats,
  }) => Alarm(
    alarmId: alarmId ?? this.alarmId,
    startHour: startHour ?? this.startHour,
    startMin: startMin ?? this.startMin,
    isOpen: isOpen ?? this.isOpen,
    repeats: repeats ?? this.repeats,
  );
}

/// 7 项全天健康检测与 PPG 定时监测共用的配置。
class TimedConfig {
  const TimedConfig({
    required this.isOpen,
    this.duration = 60,
    this.startHour = 0,
    this.startMin = 0,
    this.endHour = 23,
    this.endMin = 59,
  });

  final bool isOpen;
  final int duration;
  final int startHour;
  final int startMin;
  final int endHour;
  final int endMin;

  factory TimedConfig.fromMap(Map<dynamic, dynamic> m) => TimedConfig(
    isOpen: m['isOpen'] == true,
    duration: (m['duration'] as num?)?.toInt() ?? 60,
    startHour: (m['startHour'] as num?)?.toInt() ?? 0,
    startMin: (m['startMin'] as num?)?.toInt() ?? 0,
    endHour: (m['endHour'] as num?)?.toInt() ?? 23,
    endMin: (m['endMin'] as num?)?.toInt() ?? 59,
  );

  Map<String, dynamic> toMap() => {
    'isOpen': isOpen,
    'duration': duration,
    'startHour': startHour,
    'startMin': startMin,
    'endHour': endHour,
    'endMin': endMin,
  };

  TimedConfig copyWith({
    bool? isOpen,
    int? duration,
    int? startHour,
    int? startMin,
    int? endHour,
    int? endMin,
  }) => TimedConfig(
    isOpen: isOpen ?? this.isOpen,
    duration: duration ?? this.duration,
    startHour: startHour ?? this.startHour,
    startMin: startMin ?? this.startMin,
    endHour: endHour ?? this.endHour,
    endMin: endMin ?? this.endMin,
  );
}

/// 时段开关（抬腕亮屏 / 睡眠模式共用 shape）。
class ScheduleToggle {
  const ScheduleToggle({
    required this.isOpen,
    this.startHour = 0,
    this.startMin = 0,
    this.endHour = 23,
    this.endMin = 59,
  });

  final bool isOpen;
  final int startHour;
  final int startMin;
  final int endHour;
  final int endMin;

  factory ScheduleToggle.fromMap(Map<dynamic, dynamic> m) => ScheduleToggle(
    isOpen: m['isOpen'] == true,
    startHour: (m['startHour'] as num?)?.toInt() ?? 0,
    startMin: (m['startMin'] as num?)?.toInt() ?? 0,
    endHour: (m['endHour'] as num?)?.toInt() ?? 23,
    endMin: (m['endMin'] as num?)?.toInt() ?? 59,
  );

  Map<String, dynamic> toMap() => {
    'isOpen': isOpen,
    'startHour': startHour,
    'startMin': startMin,
    'endHour': endHour,
    'endMin': endMin,
  };
}

/// LED 亮屏强度。lcdLevel: 1=微光, 2=柔光, 3=强光。
class LedLevel {
  const LedLevel({required this.isOpen, required this.lcdLevel});

  final bool isOpen;
  final int lcdLevel;

  factory LedLevel.fromMap(Map<dynamic, dynamic> m) => LedLevel(
    isOpen: m['isOpen'] == true,
    lcdLevel: (m['lcdLevel'] as num?)?.toInt() ?? 1,
  );

  Map<String, dynamic> toMap() => {'isOpen': isOpen, 'lcdLevel': lcdLevel};
}

/// 振动次数 / 强度。
class VibrationConfig {
  const VibrationConfig({required this.count, required this.level});

  final int count;
  final int level;

  factory VibrationConfig.fromMap(Map<dynamic, dynamic> m) => VibrationConfig(
    count: (m['count'] as num?)?.toInt() ?? 0,
    level: (m['level'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toMap() => {'count': count, 'level': level};
}
