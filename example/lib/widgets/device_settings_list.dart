import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../demo_controller.dart';
import '../demo_theme.dart';
import '../i18n.dart';
import '../support_menu.dart';

class DeviceSettingsList extends StatefulWidget {
  const DeviceSettingsList({super.key, required this.controller});

  final DemoController controller;

  @override
  State<DeviceSettingsList> createState() => _DeviceSettingsListState();
}

class _DeviceSettingsListState extends State<DeviceSettingsList> {
  final Map<String, String> _values = {};
  final Set<String> _busyIds = {};
  StreamSubscription<SensorRawStoppedEvent>? _sensorStoppedSubscription;
  StreamSubscription<HeartRateCalibrationResult>? _calibrationSubscription;

  RwfitBle get _ring => widget.controller.ring;

  @override
  void initState() {
    super.initState();
    _sensorStoppedSubscription = _ring.onSensorRawStopped.listen((_) {
      if (!mounted) return;
      setState(() {
        _values[_FeatureId.sensorRawPpg] = demoTr(
          '采集完成',
          'Collection complete',
        );
      });
    });
    _calibrationSubscription = _ring.onHeartRateCalibration.listen((event) {
      if (!mounted) return;
      final value = event.isCalibrating
          ? demoTr('校准中', 'Calibrating')
          : demoTr(
              '完成 · 结果 ${event.result}',
              'Complete · result ${event.result}',
            );
      setState(() => _values[_FeatureId.heartRateCalibration] = value);
    });
  }

  @override
  void dispose() {
    _sensorStoppedSubscription?.cancel();
    _calibrationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _supportedSettings(widget.controller.capabilities);
    if (settings.isEmpty) {
      return DemoEmptyCard(
        title: demoTr('暂无可配置功能', 'No configurable features'),
        message: demoTr(
          '设备功能表未声明可配置项，重新连接后可再次获取。',
          'Reconnect to refresh the device capability table.',
        ),
      );
    }
    return Card(
      child: Column(
        children: [
          for (var index = 0; index < settings.length; index++) ...[
            _settingTile(settings[index]),
            if (index != settings.length - 1)
              const Divider(height: 1, indent: 66),
          ],
        ],
      ),
    );
  }

  Widget _settingTile(_FeatureSpec setting) {
    final busy = _busyIds.contains(setting.id);
    final value =
        _values[setting.id] ??
        (setting.immediate
            ? demoTr('立即执行', 'Run now')
            : setting.readable
            ? demoTr('读取或设置', 'Read or set')
            : demoTr('点击设置', 'Tap to set'));
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFFEAF5F0),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          setting.symbol,
          style: const TextStyle(
            color: DemoColors.primary,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
      title: Text(setting.title),
      subtitle: Text(setting.subtitle),
      trailing: busy
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 95),
                  child: Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: DemoColors.primary,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 3),
                const Icon(Icons.chevron_right),
              ],
            ),
      onTap: busy ? null : () => _tapSetting(setting),
    );
  }

  Future<void> _tapSetting(_FeatureSpec setting) async {
    if (!widget.controller.connected) {
      _toast(demoTr('请先连接设备', 'Connect the device first'));
      return;
    }
    setState(() => _busyIds.add(setting.id));
    try {
      await switch (setting.id) {
        _FeatureId.alarm => _manageAlarm(),
        _FeatureId.userInfo => _setDemoUserInfo(),
        _FeatureId.timeFormat => _configureTimeFormat(),
        _FeatureId.screenSleep => _configureScreenSleep(),
        _FeatureId.brightDuration => _configureBrightDuration(),
        _FeatureId.raiseToWake => _configureRaiseToWake(),
        _FeatureId.ledLevel => _configureLed(),
        _FeatureId.wearHand => _configureWearHand(),
        _FeatureId.findDevice => _findDevice(),
        _FeatureId.takePhoto => _configureCamera(),
        _FeatureId.videoHid => _manageVideoHid(),
        _FeatureId.heartRateCalibration => _startHeartRateCalibration(),
        _FeatureId.heartRateMonitoring ||
        _FeatureId.bloodOxygenMonitoring ||
        _FeatureId.hrvMonitoring ||
        _FeatureId.stressMonitoring ||
        _FeatureId.bloodPressureMonitoring ||
        _FeatureId.bloodSugarMonitoring ||
        _FeatureId.temperatureMonitoring ||
        _FeatureId.ppgMonitoring => _configureMonitoring(setting.id),
        _FeatureId.sensorRawPpg => _manageSensorRawPpg(),
        _FeatureId.heartRateAlert => _configureHeartRateAlert(),
        _FeatureId.bloodOxygenAlert => _configureBloodOxygenAlert(),
        _FeatureId.vibrationCount => _configureVibrationCount(),
        _FeatureId.alarmVibration => _configureAlarmVibration(),
        _FeatureId.vibrationInterval => _configureVibrationInterval(),
        _FeatureId.countReminder => _configureCountReminder(),
        _FeatureId.fallDetect => _configureFallDetection(),
        _FeatureId.rememberSwitch => _configureRememberSwitch(),
        _FeatureId.messageNotification => _manageMessageNotification(),
        _FeatureId.powerOff => _runPowerAction(),
        _ => Future<void>.value(),
      };
    } on RwfitException catch (error) {
      _toast('[${error.code}] ${error.message}');
    } catch (error) {
      _toast('$error');
    } finally {
      if (mounted) setState(() => _busyIds.remove(setting.id));
    }
  }

  Future<void> _findDevice() async {
    await _ring.findDevice();
    _setValue(_FeatureId.findDevice, demoTr('已发送', 'Sent'));
    _toast(demoTr('查找指令已发送', 'Find-device command sent'));
  }

  Future<void> _setDemoUserInfo() async {
    await _ring.setUserInfo(
      const UserInfo(gender: 1, age: 20, height: 170.5, weight: 80),
    );
    _saved(
      _FeatureId.userInfo,
      demoTr('男 · 20 岁 · 170.5 cm · 80 kg', 'Male · 20 · 170.5 cm · 80 kg'),
    );
  }

  Future<void> _configureTimeFormat() async {
    final labels = [demoTr('24 小时制', '24-hour'), demoTr('12 小时制', '12-hour')];
    final index = await _choose(labels);
    if (index == null) return;
    await _ring.setTimeFormat(index);
    _saved(_FeatureId.timeFormat, labels[index]);
  }

  Future<void> _manageVideoHid() async {
    final capabilities = widget.controller.capabilities;
    final actions = <({String label, int? mode, int? bondType})>[
      (
        label: demoTr('读取当前模式', 'Read current mode'),
        mode: null,
        bondType: null,
      ),
      (label: demoTr('关闭 HID', 'Turn HID off'), mode: 0, bondType: null),
      if (capabilities.has(DemoCapabilityKey.videoHid))
        (label: demoTr('视频模式', 'Video mode'), mode: 1, bondType: null),
      if (capabilities.has(DemoCapabilityKey.videoHidBook))
        (label: demoTr('翻页模式', 'Book mode'), mode: 2, bondType: null),
      if (capabilities.has(DemoCapabilityKey.videoHidMusic))
        (label: demoTr('音乐模式', 'Music mode'), mode: 3, bondType: null),
      if (Platform.isAndroid)
        (label: demoTr('发起系统配对', 'Pair system HID'), mode: null, bondType: 1),
      if (Platform.isAndroid)
        (label: demoTr('解除系统配对', 'Unpair system HID'), mode: null, bondType: 2),
    ];
    final index = await _choose(actions.map((action) => action.label).toList());
    if (index == null) return;
    final action = actions[index];
    if (action.bondType != null) {
      final mac = widget.controller.device?.mac ?? '';
      if (mac.isEmpty) {
        throw StateError(
          demoTr('当前设备没有可用 MAC 地址', 'No device MAC is available'),
        );
      }
      final started = await _ring.createOrRemoveBond(action.bondType!, mac);
      _setValue(
        _FeatureId.videoHid,
        started ? action.label : demoTr('操作未发起', 'Not started'),
      );
      _toast(
        started
            ? demoTr('系统配对操作已发起', 'System pairing action started')
            : demoTr('系统配对操作未发起', 'System pairing action was not started'),
      );
      return;
    }
    if (action.mode == null) {
      final mode = await _ring.getVideoHid();
      _setValue(_FeatureId.videoHid, _videoHidText(mode));
      _toast(demoTr('当前设置已读取', 'Current setting loaded'));
      return;
    }
    await _ring.setVideoHid(action.mode!);
    _saved(_FeatureId.videoHid, _videoHidText(action.mode!));
  }

  String _videoHidText(int mode) => switch (mode) {
    0 => demoTr('已关闭', 'Off'),
    1 => demoTr('视频模式', 'Video'),
    2 => demoTr('翻页模式', 'Book'),
    3 => demoTr('音乐模式', 'Music'),
    _ => demoTr('未知模式 $mode', 'Unknown mode $mode'),
  };

  Future<void> _startHeartRateCalibration() async {
    final confirmed = await _confirm(
      demoTr('启动心率校准', 'Start heart-rate calibration'),
      demoTr(
        '这是工厂测试功能，确定向设备发送校准指令吗？',
        'This is a factory-test function. Send the calibration command?',
      ),
      confirmText: demoTr('启动', 'Start'),
    );
    if (!confirmed) return;
    await _ring.startHeartRateCalibration();
    _setValue(_FeatureId.heartRateCalibration, demoTr('已启动', 'Started'));
    _toast(demoTr('校准指令已发送', 'Calibration command sent'));
  }

  Future<void> _manageMessageNotification() async {
    if (Platform.isAndroid) {
      await _ring.pushMessage({
        'appId': 'com.rwfit.demo',
        'title': demoTr('测试标题', 'Test title'),
        'content': demoTr('这是一条测试消息', 'This is a test message'),
        'msgType': 1,
      });
      _setValue(_FeatureId.messageNotification, demoTr('已发送', 'Sent'));
      _toast(demoTr('测试消息已发送', 'Test message sent'));
      return;
    }
    final labels = [
      demoTr('读取当前设置', 'Read current settings'),
      demoTr('开启常用通知', 'Enable common notifications'),
      demoTr('关闭全部通知', 'Disable all notifications'),
    ];
    final index = await _choose(labels);
    if (index == null) return;
    if (index == 0) {
      final switches = await _ring.getNotificationSwitch();
      final enabledCount = switches.values
          .where((value) => value == true)
          .length;
      _setValue(
        _FeatureId.messageNotification,
        demoTr('$enabledCount 项开启', '$enabledCount enabled'),
      );
      _toast(demoTr('通知设置已读取', 'Notification settings loaded'));
      return;
    }
    final enabled = index == 1;
    await _ring.setNotificationSwitch({
      'isCall': enabled,
      'isSMS': enabled,
      'isQQ': enabled,
      'isWechat': enabled,
      'isWhatsapp': false,
      'isFacebook': false,
    });
    _saved(
      _FeatureId.messageNotification,
      enabled
          ? demoTr('常用通知已开启', 'Common enabled')
          : demoTr('已全部关闭', 'All off'),
    );
  }

  Future<void> _configureMonitoring(String id) async {
    final index = await _choose([
      demoTr('读取当前设置', 'Read current setting'),
      demoTr('关闭', 'Off'),
      demoTr('每 30 分钟', 'Every 30 minutes'),
      demoTr('每 60 分钟', 'Every 60 minutes'),
    ]);
    if (index == null) return;
    final Future<TimedConfig> Function() getter = switch (id) {
      _FeatureId.heartRateMonitoring => () => _ring.getTimedHeartRate(),
      _FeatureId.bloodOxygenMonitoring => () => _ring.getTimedBloodOxygen(),
      _FeatureId.hrvMonitoring => () => _ring.getTimedHRV(),
      _FeatureId.stressMonitoring => () => _ring.getTimedStress(),
      _FeatureId.bloodPressureMonitoring => () => _ring.getTimedBloodPressure(),
      _FeatureId.bloodSugarMonitoring => () => _ring.getTimedBloodSugar(),
      _FeatureId.temperatureMonitoring => () => _ring.getTimedBodyTemperature(),
      _FeatureId.ppgMonitoring => () => _ring.getTimedPPG(),
      _ => throw StateError('Unsupported monitoring type: $id'),
    };
    if (index == 0) {
      _loaded(id, _timedConfigText(await getter()));
      return;
    }
    final interval = const [0, 30, 60][index - 1];
    final config = TimedConfig(
      isOpen: interval > 0,
      duration: interval == 0 ? 60 : interval,
      startHour: 0,
      startMin: 0,
      endHour: 23,
      endMin: 59,
    );
    final setter = switch (id) {
      _FeatureId.heartRateMonitoring => _ring.setTimedHeartRate,
      _FeatureId.bloodOxygenMonitoring => _ring.setTimedBloodOxygen,
      _FeatureId.hrvMonitoring => _ring.setTimedHRV,
      _FeatureId.stressMonitoring => _ring.setTimedStress,
      _FeatureId.bloodPressureMonitoring => _ring.setTimedBloodPressure,
      _FeatureId.bloodSugarMonitoring => _ring.setTimedBloodSugar,
      _FeatureId.temperatureMonitoring => _ring.setTimedBodyTemperature,
      _FeatureId.ppgMonitoring => _ring.setTimedPPG,
      _ => throw StateError('Unsupported monitoring type: $id'),
    };
    await setter(config);
    _setValue(
      id,
      interval == 0
          ? demoTr('已关闭', 'Off')
          : demoTr('$interval 分钟', '$interval min'),
    );
    _toast(demoTr('设置成功', 'Setting saved'));
  }

  Future<void> _configureScreenSleep() async {
    final labels = [
      demoTr('读取当前设置', 'Read current setting'),
      demoTr('关闭', 'Off'),
      '22:00–08:00',
      demoTr('全天开启', 'All day'),
    ];
    final index = await _choose(labels);
    if (index == null) return;
    if (index == 0) {
      _loaded(
        _FeatureId.screenSleep,
        _scheduleText(await _ring.getBrightScreenSleepTime()),
      );
      return;
    }
    final values = const [
      ScheduleToggle(isOpen: false, startHour: 22, endHour: 8),
      ScheduleToggle(isOpen: true, startHour: 22, endHour: 8),
      ScheduleToggle(isOpen: true),
    ];
    await _ring.setBrightScreenSleepTime(values[index - 1]);
    _saved(_FeatureId.screenSleep, labels[index]);
  }

  Future<void> _configureBrightDuration() async {
    final values = [5, 10, 15, 20, 30];
    final labels = [
      demoTr('读取当前设置', 'Read current setting'),
      ...values.map((value) => '$value ${demoTr('秒', 's')}'),
    ];
    final index = await _choose(labels);
    if (index == null) return;
    if (index == 0) {
      final seconds = await _ring.getBrightScreenTime();
      _loaded(_FeatureId.brightDuration, '$seconds ${demoTr('秒', 's')}');
      return;
    }
    await _ring.setBrightScreenTime(values[index - 1]);
    _saved(_FeatureId.brightDuration, labels[index]);
  }

  Future<void> _configureRaiseToWake() async {
    final labels = [
      demoTr('读取当前设置', 'Read current setting'),
      demoTr('关闭', 'Off'),
      '08:00–22:00',
      demoTr('全天开启', 'All day'),
    ];
    final index = await _choose(labels);
    if (index == null) return;
    if (index == 0) {
      _loaded(
        _FeatureId.raiseToWake,
        _scheduleText(await _ring.getRaiseBrightScreen()),
      );
      return;
    }
    final values = const [
      ScheduleToggle(isOpen: false, startHour: 8, endHour: 22),
      ScheduleToggle(isOpen: true, startHour: 8, endHour: 22),
      ScheduleToggle(isOpen: true),
    ];
    await _ring.setRaiseBrightScreen(values[index - 1]);
    _saved(_FeatureId.raiseToWake, labels[index]);
  }

  Future<void> _configureLed() async {
    final labels = [
      demoTr('读取当前设置', 'Read current setting'),
      demoTr('关闭', 'Off'),
      demoTr('亮度 1', 'Level 1'),
      demoTr('亮度 2', 'Level 2'),
      demoTr('亮度 3', 'Level 3'),
    ];
    final index = await _choose(labels);
    if (index == null) return;
    if (index == 0) {
      final level = await _ring.getRingLedLevel();
      _loaded(
        _FeatureId.ledLevel,
        level.isOpen
            ? demoTr('亮度 ${level.lcdLevel}', 'Level ${level.lcdLevel}')
            : demoTr('已关闭', 'Off'),
      );
      return;
    }
    final level = index - 1;
    await _ring.setRingLedLevel(LedLevel(isOpen: level > 0, lcdLevel: level));
    _saved(_FeatureId.ledLevel, labels[index]);
  }

  Future<void> _configureWearHand() async {
    final labels = [
      demoTr('读取当前设置', 'Read current setting'),
      demoTr('左手', 'Left hand'),
      demoTr('右手', 'Right hand'),
    ];
    final index = await _choose(labels);
    if (index == null) return;
    if (index == 0) {
      final isRight = await _ring.getRingWearDir();
      _loaded(
        _FeatureId.wearHand,
        isRight ? demoTr('右手', 'Right hand') : demoTr('左手', 'Left hand'),
      );
      return;
    }
    await _ring.setRingWearHand(index == 2);
    _saved(_FeatureId.wearHand, labels[index]);
  }

  Future<void> _configureCamera() async {
    final labels = [
      demoTr('进入遥控拍照', 'Enter camera remote'),
      demoTr('退出遥控拍照', 'Exit camera remote'),
    ];
    final index = await _choose(labels);
    if (index == null) return;
    await _ring.controlPhoto(index == 0 ? 1 : 0);
    _saved(_FeatureId.takePhoto, labels[index]);
  }

  Future<void> _configureHeartRateAlert() async {
    final labels = [
      demoTr('读取当前设置', 'Read current setting'),
      demoTr('关闭', 'Off'),
      demoTr('上限 120 bpm', 'Upper limit 120 bpm'),
      demoTr('上限 140 bpm', 'Upper limit 140 bpm'),
      demoTr('上限 160 bpm', 'Upper limit 160 bpm'),
    ];
    final index = await _choose(labels);
    if (index == null) return;
    final current = await _ring.getHeartRateAlert();
    if (index == 0) {
      _loaded(
        _FeatureId.heartRateAlert,
        current.isOpen
            ? demoTr(
                '上限 ${current.highThreshold} bpm',
                'High ${current.highThreshold} bpm',
              )
            : demoTr('已关闭', 'Off'),
      );
      return;
    }
    final threshold = const [0, 120, 140, 160][index - 1];
    await _ring.setHeartRateAlert(
      current.copyWith(
        isOpen: threshold > 0,
        highThreshold: threshold == 0 ? 140 : threshold,
      ),
    );
    _saved(_FeatureId.heartRateAlert, labels[index]);
  }

  Future<void> _configureBloodOxygenAlert() async {
    final labels = [
      demoTr('读取当前设置', 'Read current setting'),
      demoTr('关闭', 'Off'),
      demoTr('下限 90%', 'Lower limit 90%'),
      demoTr('下限 92%', 'Lower limit 92%'),
      demoTr('下限 94%', 'Lower limit 94%'),
    ];
    final index = await _choose(labels);
    if (index == null) return;
    final current = await _ring.getBloodOxygenAlert();
    if (index == 0) {
      _loaded(
        _FeatureId.bloodOxygenAlert,
        current.isOpen
            ? demoTr(
                '下限 ${current.lowThreshold}%',
                'Low ${current.lowThreshold}%',
              )
            : demoTr('已关闭', 'Off'),
      );
      return;
    }
    final threshold = const [0, 90, 92, 94][index - 1];
    await _ring.setBloodOxygenAlert(
      current.copyWith(
        isOpen: threshold > 0,
        lowThreshold: threshold == 0 ? 94 : threshold,
      ),
    );
    _saved(_FeatureId.bloodOxygenAlert, labels[index]);
  }

  Future<void> _configureVibrationCount() async {
    final labels = [
      demoTr('读取当前设置', 'Read current setting'),
      demoTr('关闭', 'Off'),
      demoTr('低强度 · 1 次', 'Low · 1 time'),
      demoTr('中强度 · 2 次', 'Medium · 2 times'),
      demoTr('高强度 · 3 次', 'High · 3 times'),
    ];
    final index = await _choose(labels);
    if (index == null) return;
    if (index == 0) {
      final vibration = await _ring.getVibrationCount();
      _loaded(_FeatureId.vibrationCount, _vibrationText(vibration));
      return;
    }
    final values = const [
      VibrationConfig(count: 0, level: 0),
      VibrationConfig(count: 1, level: 1),
      VibrationConfig(count: 2, level: 2),
      VibrationConfig(count: 3, level: 3),
    ];
    await _ring.setVibrationCount(values[index - 1]);
    _saved(_FeatureId.vibrationCount, labels[index]);
  }

  Future<void> _configureAlarmVibration() async {
    final values = [0, 1, 2, 3, 4, 5, 6];
    final labels = [
      demoTr('读取当前设置', 'Read current setting'),
      ...values.map(
        (value) => value == 0
            ? demoTr('不震动', 'No vibration')
            : demoTr('$value 次', '$value times'),
      ),
    ];
    final index = await _choose(labels);
    if (index == null) return;
    if (index == 0) {
      final count = await _ring.getAlarmVibrationDuration();
      _loaded(
        _FeatureId.alarmVibration,
        count == 0
            ? demoTr('不震动', 'No vibration')
            : demoTr('$count 次', '$count times'),
      );
      return;
    }
    await _ring.setAlarmVibrationDuration(values[index - 1]);
    _saved(_FeatureId.alarmVibration, labels[index]);
  }

  Future<void> _configureVibrationInterval() async {
    final values = [100, 200, 300, 500, 1000];
    final labels = [
      demoTr('读取当前设置', 'Read current setting'),
      ...values.map((value) => '$value ms'),
    ];
    final index = await _choose(labels);
    if (index == null) return;
    if (index == 0) {
      final interval = await _ring.getVibrationInterval();
      _loaded(_FeatureId.vibrationInterval, '$interval ms');
      return;
    }
    await _ring.setVibrationInterval(values[index - 1]);
    _saved(_FeatureId.vibrationInterval, labels[index]);
  }

  Future<void> _configureCountReminder() async {
    final values = [0, 30, 60, 90, 120];
    final labels = [
      demoTr('读取当前设置', 'Read current setting'),
      demoTr('关闭', 'Off'),
      ...values.skip(1).map((value) => demoTr('$value 分钟', '$value min')),
    ];
    final index = await _choose(labels);
    if (index == null) return;
    if (index == 0) {
      final minutes = await _ring.getCountReminderInterval();
      _loaded(
        _FeatureId.countReminder,
        minutes == 0
            ? demoTr('已关闭', 'Off')
            : demoTr('$minutes 分钟', '$minutes min'),
      );
      return;
    }
    await _ring.setCountReminderInterval(values[index - 1]);
    _saved(_FeatureId.countReminder, labels[index]);
  }

  Future<void> _configureFallDetection() async {
    final labels = [
      demoTr('读取当前设置', 'Read current setting'),
      demoTr('关闭', 'Off'),
      demoTr('开启', 'On'),
    ];
    final index = await _choose(labels);
    if (index == null) return;
    if (index == 0) {
      _loaded(_FeatureId.fallDetect, _switchText(await _ring.getFallDetect()));
      return;
    }
    await _ring.setFallDetect(index == 2);
    _saved(_FeatureId.fallDetect, labels[index]);
  }

  Future<void> _configureRememberSwitch() async {
    final labels = [
      demoTr('读取当前设置', 'Read current setting'),
      demoTr('关闭', 'Off'),
      demoTr('开启', 'On'),
    ];
    final index = await _choose(labels);
    if (index == null) return;
    if (index == 0) {
      _loaded(
        _FeatureId.rememberSwitch,
        _switchText(await _ring.getMuslimCountEnabled()),
      );
      return;
    }
    await _ring.setMuslimCountEnabled(index == 2);
    _saved(_FeatureId.rememberSwitch, labels[index]);
  }

  Future<void> _manageSensorRawPpg() async {
    final labels = [
      demoTr('启动 PPG', 'Start PPG'),
      demoTr('停止 PPG', 'Stop PPG'),
      demoTr('获取 PPG 历史', 'Get PPG history'),
    ];
    final index = await _choose(labels);
    if (index == null) return;
    if (index < 2) {
      final start = index == 0;
      if (!start) _setValue(_FeatureId.sensorRawPpg, demoTr('停止中', 'Stopping'));
      await _ring.controlSensorRaw(start, SensorRawSelection.ppgGreen);
      if (start) {
        _setValue(_FeatureId.sensorRawPpg, demoTr('采集中', 'Collecting'));
      }
      _toast(
        start
            ? demoTr('PPG 已启动', 'PPG started')
            : demoTr('停止指令已发送', 'Stop command sent'),
      );
      return;
    }
    final packets = await _ring.getSensorRawHistory();
    final ppgPackets = packets
        .where((packet) => packet.type == SensorRawDataType.ppg)
        .toList();
    final samples = ppgPackets.fold<int>(
      0,
      (total, packet) => total + packet.ppg.length,
    );
    _setValue(
      _FeatureId.sensorRawPpg,
      demoTr(
        '${ppgPackets.length} 组 · $samples 点',
        '${ppgPackets.length} sets · $samples samples',
      ),
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(demoTr('PPG 历史数据', 'PPG history')),
        content: Text(
          ppgPackets.isEmpty
              ? demoTr('设备中暂无 PPG 历史数据。', 'No PPG history on the device.')
              : demoTr(
                  '获取 ${ppgPackets.length} 组，共 $samples 个采样点。',
                  'Received ${ppgPackets.length} sets and $samples samples.',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(demoTr('知道了', 'OK')),
          ),
        ],
      ),
    );
  }

  Future<void> _manageAlarm() async {
    final action = await _choose([
      demoTr('获取闹钟', 'Get alarms'),
      demoTr('新增闹钟', 'Add alarm'),
      demoTr('删除全部闹钟', 'Delete all alarms'),
    ]);
    if (action == null) return;
    if (action == 0) {
      final alarms = await _ring.getAlarm();
      _setValue(
        _FeatureId.alarm,
        demoTr('${alarms.length} 个闹钟', '${alarms.length} alarms'),
      );
      await _showAlarmList(alarms);
      return;
    }
    if (action == 2) {
      final confirmed = await _confirm(
        demoTr('删除全部闹钟', 'Delete all alarms'),
        demoTr('确定删除设备中的全部闹钟吗？', 'Delete all alarms on the device?'),
        confirmText: demoTr('删除', 'Delete'),
      );
      if (!confirmed) return;
      await _ring.deleteAllAlarm();
      _setValue(_FeatureId.alarm, demoTr('0 个闹钟', '0 alarms'));
      _toast(demoTr('已删除', 'Deleted'));
      return;
    }
    final value = await _editTime();
    if (value == null) return;
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value);
    if (match == null) {
      throw FormatException(demoTr('时间格式应为 HH:mm', 'Use HH:mm format'));
    }
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) {
      throw FormatException(demoTr('请输入有效时间', 'Enter a valid time'));
    }
    final alarms = await _ring.getAlarm();
    if (alarms.length >= 6) {
      throw StateError(
        demoTr('设备最多支持 6 个闹钟', 'The device supports up to 6 alarms'),
      );
    }
    final usedIds = alarms.map((alarm) => alarm.alarmId).toSet();
    var alarmId = 0;
    while (usedIds.contains(alarmId)) {
      alarmId++;
    }
    await _ring.setAlarm([
      ...alarms,
      Alarm(
        alarmId: alarmId,
        startHour: hour,
        startMin: minute,
        isOpen: true,
        repeats: const [1, 1, 1, 1, 1, 1, 1],
      ),
    ]);
    _setValue(
      _FeatureId.alarm,
      demoTr('${alarms.length + 1} 个闹钟', '${alarms.length + 1} alarms'),
    );
    _toast(demoTr('闹钟已添加', 'Alarm added'));
  }

  Future<void> _showAlarmList(List<Alarm> alarms) async {
    final weekdayNames = demoTr(
      '周日,周一,周二,周三,周四,周五,周六',
      'Sun,Mon,Tue,Wed,Thu,Fri,Sat',
    ).split(',');
    final content = alarms.isEmpty
        ? demoTr('设备中暂无闹钟', 'No alarms on the device')
        : [
            for (var index = 0; index < alarms.length; index++)
              '${index + 1}. ${alarms[index].startHour.toString().padLeft(2, '0')}:'
                  '${alarms[index].startMin.toString().padLeft(2, '0')} · '
                  '${_repeatText(alarms[index], weekdayNames)} · '
                  '${alarms[index].isOpen ? demoTr('开启', 'On') : demoTr('关闭', 'Off')}',
          ].join('\n');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          demoTr('设备闹钟（${alarms.length}）', 'Device alarms (${alarms.length})'),
        ),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(demoTr('知道了', 'OK')),
          ),
        ],
      ),
    );
  }

  String _repeatText(Alarm alarm, List<String> weekdays) {
    final days = <String>[];
    for (var index = 0; index < alarm.repeats.length && index < 7; index++) {
      if (alarm.repeats[index] == 1) days.add(weekdays[index]);
    }
    if (days.length == 7) return demoTr('每天', 'Every day');
    if (days.isEmpty) return demoTr('仅一次', 'Once');
    return days.join(demoTr('、', ', '));
  }

  Future<void> _runPowerAction() async {
    final capabilities = widget.controller.capabilities;
    final actions = <({String label, bool factoryReset})>[
      if (capabilities.has(DemoCapabilityKey.powerOff))
        (label: demoTr('设备关机', 'Power off'), factoryReset: false),
      if (capabilities.has(DemoCapabilityKey.factoryReset))
        (label: demoTr('恢复出厂设置', 'Factory reset'), factoryReset: true),
    ];
    final index = await _choose(actions.map((action) => action.label).toList());
    if (index == null) return;
    final action = actions[index];
    final confirmed = await _confirm(
      action.label,
      action.factoryReset
          ? demoTr(
              '设备数据将被清除，此操作不可撤销。',
              'Device data will be erased. This cannot be undone.',
            )
          : demoTr('确定让设备关机吗？', 'Power off the device?'),
      confirmText: action.factoryReset
          ? demoTr('恢复出厂', 'Reset')
          : demoTr('关机', 'Power off'),
    );
    if (!confirmed) return;
    if (action.factoryReset) {
      await _ring.factoryReset();
    } else {
      await _ring.powerOff();
    }
    _setValue(_FeatureId.powerOff, demoTr('指令已发送', 'Command sent'));
    _toast(
      action.factoryReset
          ? demoTr('恢复出厂指令已发送', 'Factory-reset command sent')
          : demoTr('关机指令已发送', 'Power-off command sent'),
    );
  }

  String _timedConfigText(TimedConfig config) => config.isOpen
      ? demoTr(
          '${config.duration} 分钟 · ${_timeText(config.startHour, config.startMin)}–${_timeText(config.endHour, config.endMin)}',
          '${config.duration} min · ${_timeText(config.startHour, config.startMin)}–${_timeText(config.endHour, config.endMin)}',
        )
      : demoTr('已关闭', 'Off');

  String _scheduleText(ScheduleToggle config) => config.isOpen
      ? '${_timeText(config.startHour, config.startMin)}–'
            '${_timeText(config.endHour, config.endMin)}'
      : demoTr('已关闭', 'Off');

  String _timeText(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  String _vibrationText(VibrationConfig config) {
    if (config.count == 0 || config.level == 0) return demoTr('已关闭', 'Off');
    final level = switch (config.level) {
      1 => demoTr('低', 'Low'),
      2 => demoTr('中', 'Medium'),
      3 => demoTr('高', 'High'),
      _ => demoTr('等级 ${config.level}', 'Level ${config.level}'),
    };
    return demoTr(
      '$level · ${config.count} 次',
      '$level · ${config.count} times',
    );
  }

  String _switchText(bool enabled) =>
      enabled ? demoTr('已开启', 'On') : demoTr('已关闭', 'Off');

  void _loaded(String id, String value) {
    _setValue(id, value);
    _toast(demoTr('当前设置已读取', 'Current setting loaded'));
  }

  void _saved(String id, String value) {
    _setValue(id, value);
    _toast(demoTr('设置成功', 'Setting saved'));
  }

  void _setValue(String id, String value) {
    if (mounted) setState(() => _values[id] = value);
  }

  Future<int?> _choose(List<String> options) {
    if (!mounted || options.isEmpty) return Future.value();
    return showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (var index = 0; index < options.length; index++)
              ListTile(
                title: Text(options[index], textAlign: TextAlign.center),
                onTap: () => Navigator.pop(context, index),
              ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirm(
    String title,
    String content, {
    required String confirmText,
  }) async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(demoTr('取消', 'Cancel')),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: DemoColors.danger),
                onPressed: () => Navigator.pop(context, true),
                child: Text(confirmText),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<String?> _editTime() async {
    if (!mounted) return null;
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      helpText: demoTr('新增闹钟', 'Add alarm'),
      cancelText: demoTr('取消', 'Cancel'),
      confirmText: demoTr('确定', 'OK'),
      hourLabelText: demoTr('小时', 'Hour'),
      minuteLabelText: demoTr('分钟', 'Minute'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (selected == null) return null;
    return '${selected.hour.toString().padLeft(2, '0')}:'
        '${selected.minute.toString().padLeft(2, '0')}';
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  List<_FeatureSpec> _supportedSettings(DemoCapabilities capabilities) => [
    _FeatureSpec(
      id: _FeatureId.userInfo,
      title: demoTr('用户信息', 'User profile'),
      subtitle: demoTr(
        '固定设置：男、20 岁、170.5 cm、80 kg',
        'Demo values: male, 20, 170.5 cm, 80 kg',
      ),
    ),
    if (capabilities.has(DemoCapabilityKey.brightScreenTime))
      _FeatureSpec(
        id: _FeatureId.timeFormat,
        title: demoTr('时间格式', 'Time format'),
        subtitle: demoTr('设置 12/24 小时制', 'Set 12-hour or 24-hour time'),
      ),
    if (capabilities.has(DemoCapabilityKey.alarm))
      _FeatureSpec(
        id: _FeatureId.alarm,
        title: demoTr('闹钟', 'Alarms'),
        subtitle: demoTr('设备闹钟管理', 'Manage device alarms'),
      ),
    if (capabilities.has(DemoCapabilityKey.brightScreenSleepTime))
      _FeatureSpec(
        id: _FeatureId.screenSleep,
        title: demoTr('屏幕睡眠', 'Screen sleep'),
        subtitle: demoTr('设置屏幕睡眠时段', 'Configure the screen-sleep schedule'),
      ),
    if (capabilities.has(DemoCapabilityKey.brightScreenTime))
      _FeatureSpec(
        id: _FeatureId.brightDuration,
        title: demoTr('亮屏时长', 'Screen duration'),
        subtitle: demoTr('设置屏幕保持点亮时间', 'Set how long the screen stays on'),
      ),
    if (capabilities.has(DemoCapabilityKey.raiseBrightScreen))
      _FeatureSpec(
        id: _FeatureId.raiseToWake,
        title: demoTr('抬腕亮屏', 'Raise to wake'),
        subtitle: demoTr('设置开关与生效时段', 'Configure switch and active schedule'),
      ),
    if (capabilities.has(DemoCapabilityKey.ledLight))
      _FeatureSpec(
        id: _FeatureId.ledLevel,
        title: demoTr('LED 亮度', 'LED brightness'),
        subtitle: demoTr('设置 LED 开关与亮度', 'Configure LED state and brightness'),
      ),
    if (capabilities.has(DemoCapabilityKey.wearDirection))
      _FeatureSpec(
        id: _FeatureId.wearHand,
        title: demoTr('佩戴位置', 'Wearing hand'),
        subtitle: demoTr('左手或右手佩戴', 'Wear on the left or right hand'),
      ),
    if (capabilities.has(DemoCapabilityKey.findDevice))
      _FeatureSpec(
        id: _FeatureId.findDevice,
        title: demoTr('查找设备', 'Find device'),
        subtitle: demoTr('让戒指发出查找提示', 'Ask the ring to identify itself'),
        immediate: true,
      ),
    if (capabilities.has(DemoCapabilityKey.takePhoto))
      _FeatureSpec(
        id: _FeatureId.takePhoto,
        title: demoTr('遥控拍照', 'Camera remote'),
        subtitle: demoTr('接收戒指拍照事件', 'Receive camera events from the ring'),
      ),
    if (capabilities.has(DemoCapabilityKey.videoHid) ||
        capabilities.has(DemoCapabilityKey.videoHidBook) ||
        capabilities.has(DemoCapabilityKey.videoHidMusic))
      _FeatureSpec(
        id: _FeatureId.videoHid,
        title: demoTr('Video HID', 'Video HID'),
        subtitle: demoTr(
          Platform.isAndroid ? '读取、设置模式或管理系统配对' : '读取或设置 HID 模式',
          Platform.isAndroid
              ? 'Read or set the mode and manage system pairing'
              : 'Read or set the HID mode',
        ),
      ),
    if (capabilities.has(DemoCapabilityKey.heartRate))
      _FeatureSpec(
        id: _FeatureId.heartRateMonitoring,
        title: demoTr('全天心率', 'All-day heart rate'),
        subtitle: demoTr('设置全天监测开关与间隔', 'Configure monitoring and interval'),
      ),
    if (capabilities.has(DemoCapabilityKey.bloodOxygen))
      _FeatureSpec(
        id: _FeatureId.bloodOxygenMonitoring,
        title: demoTr('全天血氧', 'All-day blood oxygen'),
        subtitle: demoTr('设置全天血氧监测', 'Configure all-day blood oxygen'),
      ),
    if (capabilities.has(DemoCapabilityKey.hrv))
      _FeatureSpec(
        id: _FeatureId.hrvMonitoring,
        title: demoTr('全天 HRV', 'All-day HRV'),
        subtitle: demoTr('设置全天 HRV 监测', 'Configure all-day HRV'),
      ),
    if (capabilities.has(DemoCapabilityKey.pressure))
      _FeatureSpec(
        id: _FeatureId.stressMonitoring,
        title: demoTr('全天压力', 'All-day stress'),
        subtitle: demoTr('设置全天压力监测', 'Configure all-day stress'),
      ),
    if (capabilities.has(DemoCapabilityKey.bloodPressure))
      _FeatureSpec(
        id: _FeatureId.bloodPressureMonitoring,
        title: demoTr('全天血压', 'All-day blood pressure'),
        subtitle: demoTr('设置全天血压监测', 'Configure all-day blood pressure'),
      ),
    if (capabilities.has(DemoCapabilityKey.bloodSugar))
      _FeatureSpec(
        id: _FeatureId.bloodSugarMonitoring,
        title: demoTr('全天血糖', 'All-day blood sugar'),
        subtitle: demoTr('设置全天血糖监测', 'Configure all-day blood sugar'),
      ),
    if (capabilities.has(DemoCapabilityKey.temperatureMonitoring) ||
        capabilities.has(DemoCapabilityKey.bodyTemperature))
      _FeatureSpec(
        id: _FeatureId.temperatureMonitoring,
        title: demoTr('全天体温', 'All-day temperature'),
        subtitle: demoTr('设置全天体温监测', 'Configure all-day temperature'),
      ),
    if (capabilities.has(DemoCapabilityKey.ppgMonitoring))
      _FeatureSpec(
        id: _FeatureId.ppgMonitoring,
        title: demoTr('PPG 定时监测', 'Scheduled PPG'),
        subtitle: demoTr('设置 PPG 定时监测', 'Configure scheduled PPG monitoring'),
      ),
    _FeatureSpec(
      id: _FeatureId.heartRateCalibration,
      title: demoTr('心率校准', 'Heart-rate calibration'),
      subtitle: demoTr('工厂测试功能', 'Factory-test function'),
      immediate: true,
    ),
    if (capabilities.has(DemoCapabilityKey.sensorRawPpg))
      _FeatureSpec(
        id: _FeatureId.sensorRawPpg,
        title: demoTr('PPG 原始数据', 'Raw PPG data'),
        subtitle: demoTr('启动、停止采集或获取历史数据', 'Start, stop, or get history'),
      ),
    if (capabilities.has(DemoCapabilityKey.heartRateAlert))
      _FeatureSpec(
        id: _FeatureId.heartRateAlert,
        title: demoTr('心率报警', 'Heart-rate alert'),
        subtitle: demoTr('设置心率上下限', 'Configure heart-rate limits'),
      ),
    if (capabilities.has(DemoCapabilityKey.bloodOxygenAlert))
      _FeatureSpec(
        id: _FeatureId.bloodOxygenAlert,
        title: demoTr('血氧报警', 'Blood-oxygen alert'),
        subtitle: demoTr('设置血氧下限', 'Configure the blood-oxygen lower limit'),
      ),
    if (capabilities.has(DemoCapabilityKey.vibrationLevel))
      _FeatureSpec(
        id: _FeatureId.vibrationCount,
        title: demoTr('震动次数', 'Vibration'),
        subtitle: demoTr('设置提醒震动次数', 'Configure vibration count and strength'),
      ),
    if (capabilities.has(DemoCapabilityKey.alarmVibrationDuration))
      _FeatureSpec(
        id: _FeatureId.alarmVibration,
        title: demoTr('闹钟震动时长', 'Alarm vibration'),
        subtitle: demoTr('设置闹钟震动参数', 'Configure alarm vibration'),
      ),
    if (capabilities.has(DemoCapabilityKey.vibrationInterval))
      _FeatureSpec(
        id: _FeatureId.vibrationInterval,
        title: demoTr('震动间隔', 'Vibration interval'),
        subtitle: demoTr(
          '设置每次震动的间隔',
          'Configure the interval between vibrations',
        ),
      ),
    if (capabilities.has(DemoCapabilityKey.countReminder))
      _FeatureSpec(
        id: _FeatureId.countReminder,
        title: demoTr('计数提醒', 'Count reminder'),
        subtitle: demoTr('设置计数提醒间隔', 'Configure the count-reminder interval'),
      ),
    if (capabilities.has(DemoCapabilityKey.fallDetect))
      _FeatureSpec(
        id: _FeatureId.fallDetect,
        title: demoTr('跌落提醒', 'Fall detection'),
        subtitle: demoTr('开启或关闭跌落检测', 'Enable or disable fall detection'),
      ),
    if (capabilities.has(DemoCapabilityKey.muslimSwitch))
      _FeatureSpec(
        id: _FeatureId.rememberSwitch,
        title: demoTr('赞念开关', 'Prayer-count switch'),
        subtitle: demoTr('开启或关闭赞念功能', 'Enable or disable prayer counting'),
      ),
    if ((Platform.isAndroid &&
            capabilities.has(DemoCapabilityKey.pushMessage)) ||
        (Platform.isIOS &&
            capabilities.has(DemoCapabilityKey.pushMessageSwitch)))
      _FeatureSpec(
        id: _FeatureId.messageNotification,
        title: demoTr('消息与通知', 'Messages and notifications'),
        subtitle: Platform.isAndroid
            ? demoTr('向设备发送测试消息', 'Send a test message to the device')
            : demoTr('读取或设置 ANCS 通知转发', 'Read or configure ANCS forwarding'),
        immediate: Platform.isAndroid,
      ),
    if (capabilities.has(DemoCapabilityKey.powerOff) ||
        capabilities.has(DemoCapabilityKey.factoryReset))
      _FeatureSpec(
        id: _FeatureId.powerOff,
        title: demoTr('关机与恢复出厂', 'Power and factory reset'),
        subtitle: demoTr('设备电源操作', 'Device power actions'),
      ),
  ];
}

class _FeatureSpec {
  const _FeatureSpec({
    required this.id,
    required this.title,
    required this.subtitle,
    this.immediate = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final bool immediate;

  String get symbol => title.characters.first;

  bool get readable => _FeatureId.readable.contains(id);
}

abstract final class _FeatureId {
  static const userInfo = 'userInfo';
  static const timeFormat = 'timeFormat';
  static const alarm = 'alarm';
  static const screenSleep = 'screenSleep';
  static const brightDuration = 'brightDuration';
  static const raiseToWake = 'raiseToWake';
  static const ledLevel = 'ledLevel';
  static const wearHand = 'wearHand';
  static const findDevice = 'findDevice';
  static const takePhoto = 'takePhoto';
  static const videoHid = 'videoHid';
  static const heartRateCalibration = 'heartRateCalibration';
  static const heartRateMonitoring = 'heartRateMonitoring';
  static const bloodOxygenMonitoring = 'bloodOxygenMonitoring';
  static const hrvMonitoring = 'hrvMonitoring';
  static const stressMonitoring = 'stressMonitoring';
  static const bloodPressureMonitoring = 'bloodPressureMonitoring';
  static const bloodSugarMonitoring = 'bloodSugarMonitoring';
  static const temperatureMonitoring = 'temperatureMonitoring';
  static const ppgMonitoring = 'ppgMonitoring';
  static const sensorRawPpg = 'sensorRawPPG';
  static const heartRateAlert = 'heartRateAlert';
  static const bloodOxygenAlert = 'bloodOxygenAlert';
  static const vibrationCount = 'vibrationCount';
  static const alarmVibration = 'alarmVibration';
  static const vibrationInterval = 'vibrationInterval';
  static const countReminder = 'countReminder';
  static const fallDetect = 'fallDetect';
  static const rememberSwitch = 'rememberSwitch';
  static const messageNotification = 'messageNotification';
  static const powerOff = 'powerOff';

  static const readable = <String>{
    alarm,
    screenSleep,
    brightDuration,
    raiseToWake,
    ledLevel,
    wearHand,
    videoHid,
    heartRateMonitoring,
    bloodOxygenMonitoring,
    hrvMonitoring,
    stressMonitoring,
    bloodPressureMonitoring,
    bloodSugarMonitoring,
    temperatureMonitoring,
    ppgMonitoring,
    heartRateAlert,
    bloodOxygenAlert,
    vibrationCount,
    alarmVibration,
    vibrationInterval,
    countReminder,
    fallDetect,
    rememberSwitch,
  };
}
