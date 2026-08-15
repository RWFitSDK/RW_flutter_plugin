/// RWFIT 戒指插件 —— 枚举与常量
///
/// 底层 SDK 数值（value / key）封进枚举字段，对 App 暴露类型安全的枚举。
/// 数值绝不可改，必须与 RW SDK 对齐（见开发文档 §0 第 1 条）。
library;

/// 实时数据类型（桥接层统一映射；value 对应事件 payload 的 dataType）。
enum HealthType {
  hr(1),
  bloodOxy(3),
  bloodBp(4),
  pressure(8),
  bloodSugar(9),
  muslimCount(10),
  temperature(11),
  hrv(13);

  const HealthType(this.value);
  final int value;

  static HealthType? fromValue(int v) {
    for (final e in values) {
      if (e.value == v) return e;
    }
    return null;
  }
}

/// 实时测量项（key 即透传给 SDK 的字符串常量）。
enum RealtimeMetric {
  hr('JL_HR_DATA_TRANSFER_KEY'),
  bloodOxy('JL_BO_DATA_TRANSFER_KEY'),
  hrv('JL_HRV_DATA_TRANSFER_KEY'),
  pressure('JL_PRESSURE_DATA_TRANSFER_KEY'),
  bloodSugar('JL_BLOODSUGAR_DATA_TRANSFER_KEY'),
  bloodPressure('JL_BP_DATA_TRANSFER_KEY'),
  temperature('JL_TEMP_DATA_TRANSFER_KEY');

  const RealtimeMetric(this.key);
  final String key;
}

/// 关机 / 恢复出厂（SDK 文档 3.2.1.10：1=关机, 2=恢复出厂）。
enum PowerOffType {
  shutdown(1),
  factoryReset(2);

  const PowerOffType(this.value);
  final int value;
}

/// 连接状态（对应 rwfit:connectState 的 state 字符串）。
///
/// 注意：不含 ready —— "就绪可用"是 rwfit:functionMenu 的语义，
/// 从 [RwfitBle.onFunctionMenu] 收，不会从 onConnectState 收到 ready。
enum ConnectState { connecting, connected, disconnected, failed }

/// 多运动控制状态。数值与 Android/iOS 原生 SDK 的 WorkoutControlType 一致。
enum WorkoutControlType {
  start(0x01),
  resume(0x02),
  pause(0x03),
  end(0x04),
  unknown(-1);

  const WorkoutControlType(this.value);
  final int value;

  bool get isRunning => this == start || this == resume || this == pause;

  static WorkoutControlType fromValue(int value) {
    return values.firstWhere(
      (item) => item.value == value,
      orElse: () => WorkoutControlType.unknown,
    );
  }
}

/// 多运动实时数据来源。iOS 用同一个通知名承载这两种数据；
/// Android 的 SportDataPushCallback 对应 [appWorkoutData]。
enum WorkoutDataType {
  appWorkoutData(0x0223),
  enterOrExitWorkout(0x0274),
  unknown(-1);

  const WorkoutDataType(this.value);
  final int value;

  static WorkoutDataType fromValue(int value) {
    return values.firstWhere(
      (item) => item.value == value,
      orElse: () => WorkoutDataType.unknown,
    );
  }
}

/// 触摸 / 物理键 / 拍照 / 音乐动作，全部经 rwfit:touchEvent 上报（无独立 music 事件）。
enum TouchAction {
  cameraTakePicture,
  musicPlay,
  musicPause,
  musicPrev,
  musicNext,
  musicVolumeUp,
  musicVolumeDown,
  singleTap,
  doubleTap,
  tripleTap,
  longPress,
  swing,
  fallDetected,
  unknown;

  static TouchAction parse(String? s) =>
      values.firstWhere((e) => e.name == s, orElse: () => TouchAction.unknown);
}

/// 来电控制动作。当前仅 Android 原生 SDK 暴露此能力。
enum CallControlAction {
  answer(0),
  reject(1);

  const CallControlAction(this.commandValue);
  final int commandValue;

  static CallControlAction? parse(String? value) {
    for (final action in values) {
      if (action.name == value) return action;
    }
    return null;
  }
}

/// 设备健康报警类型。
enum HealthAlertType {
  highHeartRate(0),
  lowBloodOxygen(1),
  lowHeartRate(2),
  unknown(-1);

  const HealthAlertType(this.value);
  final int value;

  static HealthAlertType fromValue(int value) => values.firstWhere(
    (item) => item.value == value,
    orElse: () => HealthAlertType.unknown,
  );
}

/// 传感器原始数据采集组合。绿光与红光不能共存，IR 不能单独启动。
enum SensorRawSelection {
  acc(1),
  ppgGreen(2),
  ppgGreenAndAcc(3),
  ppgRed(4),
  ppgRedAndAcc(5),
  ppgGreenAndIr(10),
  ppgGreenAccAndIr(11),
  ppgRedAndIr(12),
  ppgRedAccAndIr(13);

  const SensorRawSelection(this.value);
  final int value;
}

/// 原始数据包类型。注意：其编号与 [SensorRawSelection] 的控制组合不同。
enum SensorRawDataType {
  timestamp(0),
  ppg(1),
  acc(2),
  ppgRed(3),
  ir(4),
  sleep(5),
  unknown(-1);

  const SensorRawDataType(this.value);
  final int value;

  static SensorRawDataType fromValue(int value) => values.firstWhere(
    (item) => item.value == value,
    orElse: () => SensorRawDataType.unknown,
  );
}
