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
  bloodPressure('JL_BP_DATA_TRANSFER_KEY');

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

/// 触摸 / 物理键 / 拍照 / 音乐动作，全部经 rwfit:touchEvent 上报（无独立 music 事件）。
enum TouchAction {
  cameraTakePicture,
  musicPlay,
  musicPause,
  musicPrev,
  musicNext,
  musicVolumeUp,
  musicVolumeDown,
  unknown;

  static TouchAction parse(String? s) =>
      values.firstWhere((e) => e.name == s, orElse: () => TouchAction.unknown);
}
