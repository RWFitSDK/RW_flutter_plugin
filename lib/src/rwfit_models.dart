/// RWFIT 戒指插件 —— 数据模型
///
/// 建模规则（见开发文档 §0 第 4 条）：稳定多字段 / 列表 item / get→改→set 往返
/// 结构用 model（带 fromMap/toMap，必要时 copyWith）；真正动态的明细保留 Map 逃生舱。
library;

import 'rwfit_constants.dart';

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
}

/// 实时健康数据。`timestampMs` 为毫秒（桥接层已归一化，见开发文档 §3.4 单位陷阱）。
class RealtimeData {
  const RealtimeData({
    this.type,
    required this.value,
    this.diastolic,
    required this.timestampMs,
  });

  final HealthType? type;
  final int value;
  final int? diastolic; // 仅血压
  final int timestampMs;

  factory RealtimeData.fromMap(Map<dynamic, dynamic> m) => RealtimeData(
    type: HealthType.fromValue((m['dataType'] as num).toInt()),
    value: (m['dataValue'] as num).toInt(),
    diastolic: (m['diastolic'] as num?)?.toInt(),
    timestampMs: (m['time'] as num).toInt(),
  );
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

/// 闹钟项（字段对齐原生，含 repeats 周开关）。
class Alarm {
  const Alarm({
    required this.alarmId,
    required this.startHour,
    required this.startMin,
    required this.isOpen,
    this.alarmTag = '',
    this.repeats = const [0, 0, 0, 0, 0, 0, 0],
  });

  final int alarmId;
  final int startHour;
  final int startMin;
  final bool isOpen;
  final String alarmTag;
  final List<int> repeats; // 长度 7：周一~周日

  factory Alarm.fromMap(Map<dynamic, dynamic> m) => Alarm(
    alarmId: (m['alarmId'] as num).toInt(),
    startHour: (m['startHour'] as num).toInt(),
    startMin: (m['startMin'] as num).toInt(),
    isOpen: m['isOpen'] == true,
    alarmTag: (m['alarmTag'] ?? '') as String,
    repeats:
        (m['repeats'] as List?)?.map((e) => (e as num).toInt()).toList() ??
        const [0, 0, 0, 0, 0, 0, 0],
  );

  Map<String, dynamic> toMap() => {
    'alarmId': alarmId,
    'startHour': startHour,
    'startMin': startMin,
    'isOpen': isOpen,
    'alarmTag': alarmTag,
    'repeats': repeats,
  };

  /// 改一条再整批回发的核心：getAlarm → copyWith → setAlarm（全量下发）。
  Alarm copyWith({
    int? alarmId,
    int? startHour,
    int? startMin,
    bool? isOpen,
    String? alarmTag,
    List<int>? repeats,
  }) => Alarm(
    alarmId: alarmId ?? this.alarmId,
    startHour: startHour ?? this.startHour,
    startMin: startMin ?? this.startMin,
    isOpen: isOpen ?? this.isOpen,
    alarmTag: alarmTag ?? this.alarmTag,
    repeats: repeats ?? this.repeats,
  );
}

/// 全天检测配置（6 项共用：心率/血氧/HRV/压力/血糖/血压）。
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
