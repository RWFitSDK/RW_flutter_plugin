# RWFIT 戒指 Flutter 插件 —— 集成文档

面向**接入方 App 开发者**：把 `rwfit_ble` 插件集成进你的 Flutter 工程并跑通"扫描 → 连接 → 调用"。
可运行范例见插件包内 `example/`。

---

## 0. 交付物与支持平台

| 项 | 说明 |
|---|---|
| 交付形式 | **GitHub 仓库 + git 依赖**：仓库 [`RWFitSDK/RW_flutter_plugin`](https://github.com/RWFitSDK/RW_flutter_plugin) 含 `example/`（可直接运行验证）、内置原生 SDK、Dart 源码。App 通过 git 依赖引入，用 tag 锁版本 |
| 原生 SDK | **已内置**：Android aar 在 `android/repo/`，iOS `DHBleSDK.framework` 已 vendored。**无需额外 SDK 文件** |
| Android | minSdk **26**、compileSdk 35 |
| iOS | **12.0+**；需**真机**测试 |
| Flutter / Dart | Dart SDK `^3.12.0`、Flutter `>=3.3.0` |

---

## 1. 引入插件

### 1.1 先跑通 example（无需配置）

克隆仓库后，`example/` 已用 path 依赖指向插件本体（`path: ../`），开箱即用，进目录直接运行即可验证环境：

```bash
git clone https://github.com/RWFitSDK/RW_flutter_plugin.git
cd RW_flutter_plugin/example
flutter pub get
flutter run   # iOS 需真机
```

### 1.2 集成进你自己的 App

在 App 的 `pubspec.yaml` 声明 git 依赖（用 `ref` 锁定版本 tag），无需拷贝任何文件、无需单独获取 RW SDK：

```yaml
# <your_app>/pubspec.yaml
dependencies:
  rwfit_ble:
    git:
      url: https://github.com/RWFitSDK/RW_flutter_plugin.git
      ref: v0.0.1   # 锁定版本，升级时改这里
```

```bash
flutter pub get          # 升级版本改 ref 后：flutter pub upgrade rwfit_ble
```

> iOS 首次构建会自动 `pod install`（无需自定义基座）。
>
> ⚠️ **Android 必读**：`pub get` 成功 ≠ 能构建。Android 还需在 App 的 `android/build.gradle.kts` 注册插件内置的原生 SDK 仓库，否则报 `Could not find com.rwfit:blesdk-rwfit:1.0`。见 [2.1 Android](#21-android)。

---

## 2. 平台配置

### 2.1 Android

`android/app/build.gradle.kts`：`minSdk = 26`

#### 必需：注册插件内置的原生 SDK 仓库 ⚠️

插件随包内置了 RW 戒指原生 SDK 的 AAR（`com.rwfit:blesdk-rwfit`），位于插件目录的 `android/repo`。**Gradle 解析 `:app` 的传递依赖时用的是 App 自己的仓库列表，插件内部声明的仓库不会传递过来**，所以必须在 **App 侧**把插件目录下的 `repo` 注册为本地 maven 仓库，否则构建报：

```
Could not find com.rwfit:blesdk-rwfit:1.0.
```

在你的 App 根目录 `android/build.gradle.kts` 的 `allprojects.repositories` 中加一行（Kotlin DSL）：

```kotlin
allprojects {
    repositories {
        google()
        mavenCentral()
        // RWFIT 插件内置原生 SDK 仓库。用 :rwfit_ble 子工程的 projectDir，
        // path 依赖与 git 依赖（pub-cache 路径带 commit hash）都自动适配，无需写死路径。
        maven { url = uri("${project(":rwfit_ble").projectDir}/repo") }
    }
}
```

Groovy DSL（`android/build.gradle`）等价写法：

```groovy
allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url "${project(':rwfit_ble').projectDir}/repo" }
    }
}
```

> 若 App 用了 `settings.gradle(.kts)` 的 `dependencyResolutionManagement { repositoriesMode = RepositoriesMode.FAIL_ON_PROJECT_REPOS }`，则需把上面的 `maven { ... }` 改加到 settings 的 `dependencyResolutionManagement.repositories` 里（同样用 `project(":rwfit_ble").projectDir`）。

`AndroidManifest.xml`：

```xml
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```

Android 12+ 需**运行时动态申请** `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT`。

### 2.2 iOS

`Info.plist`：

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>需要蓝牙以连接 RWFIT 智能戒指</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>需要蓝牙以连接 RWFIT 智能戒指</string>
```

---

## 3. 初始化与权限

```dart
import 'package:rwfit_ble/rwfit_ble.dart';
import 'package:permission_handler/permission_handler.dart';

// Android 12+ 运行时申请蓝牙权限
await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.locationWhenInUse].request();
// 初始化 SDK（全应用一次）
await RwfitBle.instance.init();
```

---

## 4. API 参考

> 所有请求-响应方法返回 `Future`，失败抛 `RwfitException(code, message)`。
> 事件流通过 typed `Stream` 暴露，需在页面 `dispose` 时 `cancel()`。

### 4.1 初始化

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `init()` | 无 | `Future<void>` | 初始化 SDK，应用启动调用一次 |
| `getSdkVersion()` | 无 | `Future<String>` 原生 SDK 版本号 | |
| `getPluginVersion()` | 无 | `Future<String>` 格式 `pluginVer_sdkVer` | |

---

### 4.2 扫描

| 方法 / Stream | 参数 | 返回 | 说明 |
|--------------|------|------|------|
| `startScan({bool filter = true})` | `filter`: 是否过滤无名设备，默认 `true` | `Future<void>` | 开始扫描 |
| `stopScan()` | 无 | `Future<void>` | 停止扫描 |
| `onScanResult` | — | `Stream<BleDevice>` | 扫描到设备时触发 |
| `onScanFinish` | — | `Stream<void>` | 扫描结束时触发 |
| `onScanError` | — | `Stream<Map>` payload: `{code, msg}` | 扫描出错 |

**`BleDevice` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | `String` | 设备名称 |
| `mac` | `String` | MAC 地址 |
| `rssi` | `int` | 信号强度 |
| `uuid` | `String?` | **仅 iOS**，设备主标识；连接时必须回传 |

---

### 4.3 连接

| 方法 / Stream | 参数 | 返回 | 说明 |
|--------------|------|------|------|
| `connect(BleDevice device)` | 扫描得到的完整 `BleDevice` | `Future<void>` | 发起连接 |
| `disconnect()` | 无 | `Future<void>` | 断开连接 |
| `reconnect([BleDevice? device])` | 可选，Android 需传(含 mac)；iOS 可空(走内置重连) | `Future<void>` | 重连已绑定设备 |
| `isConnected()` | 无 | `Future<bool>` | 当前是否已连接 |
| `iosSetBindedStatus(bool isBinded)` | `isBinded`: 绑定状态 | `Future<void>` | **iOS 专用**，Android no-op |
| `onConnectState` | — | `Stream<ConnectStateEvent>` | 连接状态变化 |
| `onFunctionMenu` | — | `Stream<FunctionMenu>` | **设备就绪信号**，收到后才可发业务指令 |

**`ConnectStateEvent` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `state` | `ConnectState` 枚举 | `connecting` / `connected` / `disconnected` / `failed` |
| `name` | `String?` | 设备名 |
| `mac` | `String?` | MAC |
| `uuid` | `String?` | 仅 iOS |
| `reason` | `String?` | 仅 `failed` 时有 |

**`FunctionMenu` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | `String` | 设备名 |
| `mac` | `String` | MAC |
| `uuid` | `String?` | 仅 iOS |
| `raw` | `Map<String, dynamic>` | supportMenu 能力表，App 据此做按钮灰显/隐藏 |

`raw` (supportMenu) 典型 key：`isStep`, `isSleep`, `isHr`, `isBloodOxy`, `isBloodPress`, `isBloodSugar`, `isHrv`, `isPressure`, `isBodyTemp`, `isAlarm`, `isBrightScreenTime`, `isBrightScreenSleepTime`, `isPushMsgEnableSwitch`, `isFindDevice`, `isTakePhoto`, `isSupportMotoVibrationLevel`, `isSupportAlarmVibrationDuration`, `isMuslimCountData`, `isSupportMuslimTimeDisplayMode`。值均为 `bool`。

---

### 4.4 设备信息

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `getPower()` | 无 | `Future<int>` 电量百分比 0–100 | |
| `getFirmwareVersion()` | 无 | `Future<FirmwareInfo>` | 固件版本信息 |
| `setUserInfo(UserInfo info)` | `UserInfo` 对象 | `Future<void>` | 设置用户体征 |
| `setTimeFormat(int format)` | `format`: 0=12小时制, 1=24小时制 | `Future<void>` | |
| `getFunctionList()` | 无 | `Future<Map<String, dynamic>>` | 获取设备支持的功能列表 |
| `setRingBtName(String name)` | `name`: 新蓝牙名 | `Future<void>` | 修改戒指蓝牙广播名 |

**`FirmwareInfo` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `deviceClazz` | `String` | 设备型号 |
| `deviceNo` | `String` | 固件版本号 |
| `uiVersion` | `String` | UI 版本 |

**`UserInfo` 字段（构造参数）：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `gender` | `int` | 0=女, 1=男 |
| `age` | `int` | 年龄 |
| `height` | `double` | 身高(cm) |
| `weight` | `double` | 体重(kg) |

---

### 4.5 全天检测（6 项）

6 项 API 签名完全同构，入参/返回均为 `TimedConfig`：

| 方法 | 说明 |
|------|------|
| `getTimedHeartRate()` / `setTimedHeartRate(TimedConfig c)` | 全天心率检测 |
| `getTimedBloodOxygen()` / `setTimedBloodOxygen(TimedConfig c)` | 全天血氧检测 |
| `getTimedHRV()` / `setTimedHRV(TimedConfig c)` | 全天 HRV 检测 |
| `getTimedStress()` / `setTimedStress(TimedConfig c)` | 全天压力检测 |
| `getTimedBloodSugar()` / `setTimedBloodSugar(TimedConfig c)` | 全天血糖检测 |
| `getTimedBloodPressure()` / `setTimedBloodPressure(TimedConfig c)` | 全天血压检测 |

get 返回 `Future<TimedConfig>`，set 接收 `TimedConfig` 返回 `Future<void>`。

**`TimedConfig` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `isOpen` | `bool` | 是否开启 |
| `duration` | `int` | 检测间隔(分钟)，默认 60 |
| `startHour` | `int` | 开始时-小时(0–23) |
| `startMin` | `int` | 开始时-分钟(0–59) |
| `endHour` | `int` | 结束时-小时(0–23) |
| `endMin` | `int` | 结束时-分钟(0–59) |

支持 `copyWith(...)` 便于修改单个字段后回发。

---

### 4.6 实时测量

| 方法 / Stream | 参数 | 返回 | 说明 |
|--------------|------|------|------|
| `startRealtimeMeasure(RealtimeMetric m)` | `m`: 测量项枚举 | `Future<void>` | 开启实时测量 |
| `stopRealtimeMeasure(RealtimeMetric m)` | `m`: 测量项枚举 | `Future<void>` | 停止实时测量 |
| `onRealtimeData` | — | `Stream<RealtimeData>` | 实时数据回调 |

> ⚠️ **互斥约束**：同一时间只能开启一种测量类型，切换前必须先 `stop` 当前类型。

**`RealtimeMetric` 枚举：**

| 值 | 说明 |
|----|------|
| `RealtimeMetric.hr` | 心率 |
| `RealtimeMetric.bloodOxy` | 血氧 |
| `RealtimeMetric.hrv` | HRV |
| `RealtimeMetric.pressure` | 压力 |
| `RealtimeMetric.bloodSugar` | 血糖 |
| `RealtimeMetric.bloodPressure` | 血压 |

**`RealtimeData` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | `HealthType?` | 数据类型枚举 |
| `value` | `int` | 测量主值 |
| `diastolic` | `int?` | 舒张压（仅血压测量时有值） |
| `timestampMs` | `int` | 测量时间戳(毫秒) |

**`HealthType` 枚举：**

| 值 | int value | 说明 |
|----|-----------|------|
| `HealthType.hr` | 1 | 心率 |
| `HealthType.bloodOxy` | 3 | 血氧 |
| `HealthType.bloodBp` | 4 | 血压 |
| `HealthType.pressure` | 8 | 压力 |
| `HealthType.bloodSugar` | 9 | 血糖 |
| `HealthType.hrv` | 13 | HRV |

---

### 4.7 设备控制

#### 4.7.1 基本控制

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `findDevice()` | 无 | `Future<void>` | 查找设备（设备振动） |
| `powerOff()` | 无 | `Future<void>` | 关机 |
| `factoryReset()` | 无 | `Future<void>` | 恢复出厂设置 |
| `controlPhoto(int state)` | `state`: 1=进入拍照模式, 0=退出 | `Future<void>` | 拍照控制 |
| `onTouchEvent` | — | `Stream<TouchEvent>` | 触摸/拍照/音乐控制事件 |

**`TouchEvent` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `action` | `TouchAction` 枚举 | 动作类型 |
| `rawAction` | `String` | 原始动作字符串 |
| `keyType` | `int` | 预留（当前恒 0） |
| `touchType` | `int` | 预留（当前恒 0） |

**`TouchAction` 枚举值：** `cameraTakePicture`, `musicPlay`, `musicPause`, `musicPrev`, `musicNext`, `musicVolumeUp`, `musicVolumeDown`, `unknown`

---

#### 4.7.2 闹钟

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `getAlarm()` | 无 | `Future<List<Alarm>>` | 获取当前所有闹钟 |
| `setAlarm(List<Alarm> alarms)` | 完整闹钟列表 | `Future<void>` | **全量下发**所有闹钟 |
| `deleteAllAlarm()` | 无 | `Future<void>` | 删除全部闹钟 |

> ⚠️ 协议不支持单独修改某个闹钟，任何修改都要 `getAlarm → copyWith → setAlarm` 整批下发。

**`Alarm` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `alarmId` | `int` | 闹钟 ID |
| `startHour` | `int` | 时(0–23) |
| `startMin` | `int` | 分(0–59) |
| `isOpen` | `bool` | 是否启用 |
| `alarmTag` | `String` | 标签文本 |
| `repeats` | `List<int>` | 长度 7，周一~周日开关(1=开 0=关) |

支持 `copyWith(...)` 便于修改单个字段。

---

#### 4.7.3 屏幕设置

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `getRaiseBrightScreen()` | 无 | `Future<ScheduleToggle>` | 获取抬腕亮屏配置 |
| `setRaiseBrightScreen(ScheduleToggle c)` | 配置 | `Future<void>` | 设置抬腕亮屏 |
| `getBrightScreenTime()` | 无 | `Future<int>` 亮屏时长(秒) | |
| `setBrightScreenTime(int timeSecond)` | `timeSecond`: 亮屏时长(秒) | `Future<void>` | |
| `getBrightScreenSleepTime()` | 无 | `Future<ScheduleToggle>` | 获取睡眠模式亮屏配置 |
| `setBrightScreenSleepTime(ScheduleToggle c)` | 配置 | `Future<void>` | 设置睡眠模式亮屏 |
| `getRingLedLevel()` | 无 | `Future<LedLevel>` | 获取 LED 亮度 |
| `setRingLedLevel(LedLevel c)` | 配置 | `Future<void>` | 设置 LED 亮度 |

**`ScheduleToggle` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `isOpen` | `bool` | 是否开启 |
| `startHour` | `int` | 开始时-小时 |
| `startMin` | `int` | 开始时-分钟 |
| `endHour` | `int` | 结束时-小时 |
| `endMin` | `int` | 结束时-分钟 |

**`LedLevel` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `isOpen` | `bool` | 是否开启 LED |
| `lcdLevel` | `int` | 亮度等级：1=微光, 2=柔光, 3=强光 |

---

#### 4.7.4 视频 HID

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `getVideoHid()` | 无 | `Future<int>` hidOpen 值 | 获取 HID 模式 |
| `setVideoHid(int hidOpen)` | `hidOpen`: 0=关闭, 1=视频, 2=Book, 3=Music | `Future<void>` | 设置 HID 模式 |
| `createOrRemoveBond(int type, String mac)` | `type`: 1=配对, 2=取消; `mac`: 设备 MAC | `Future<bool>` 配对结果 | **Android 专用**，iOS no-op 返回 false |

---

#### 4.7.5 佩戴方向

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `getRingWearDir()` | 无 | `Future<bool>` true=右手, false=左手 | |
| `setRingWearHand(bool isRight)` | `isRight`: true=右手佩戴 | `Future<void>` | |

---

#### 4.7.6 振动

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `getVibrationCount()` | 无 | `Future<VibrationConfig>` | 获取振动配置 |
| `setVibrationCount(VibrationConfig c)` | 配置 | `Future<void>` | 设置振动配置 |
| `getAlarmVibrationDuration()` | 无 | `Future<int>` 振动时长(秒) | 闹钟振动持续时长 |
| `setAlarmVibrationDuration(int duration)` | `duration`: 振动时长(秒) | `Future<void>` | |

**`VibrationConfig` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `count` | `int` | 振动次数 |
| `level` | `int` | 振动强度等级 |

---

### 4.8 数据同步

| 方法 / Stream | 参数 | 返回 | 说明 |
|--------------|------|------|------|
| `syncAllHealthData()` | 无 | `Future<void>` | 发起全量健康数据同步 |
| `removeHealthDataCallback()` | 无 | `Future<void>` | 移除同步回调 |
| `onSyncProgress` | — | `Stream<double>` 0–100 | 同步进度 |
| `onSyncResult` | — | `Stream<SyncResult>` | 同步到的数据 |
| `onSyncFinish` | — | `Stream<void>` | 同步完成 |
| `onSyncError` | — | `Stream<Map>` payload: `{code}` | 同步错误 |

**`SyncResult` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | `String` | 数据类型，见下表 |
| `data` | `List<Map<String, dynamic>>` | 该类型的数据明细列表 |

**`type` 取值与 data 内字段：**

| type | data item 典型字段 | 说明 |
|------|-------------------|------|
| `step` | `time`, `date`, `totalSteps`, `totalCalorie`, `totalDistance`, `items[{index,steps,calorie,distance}]` | 步数 |
| `sleep` | `time`, `date`, `duration`, `beginTime`, `endTime`, `items[{len,sleepType}]` | 睡眠 |
| `hr` | `time`, `date`, `items[{time,hr}]` | 心率 |
| `bo` | `time`, `date`, `items[{time,bloodOxy}]` | 血氧 |
| `bp` | `time`, `date`, `items[{time,systolic,diastolic}]` | 血压 |
| `hrv` | `time`, `date`, `items[{time,hrv}]` | HRV |
| `pressure` | `time`, `date`, `items[{time,pressure}]` | 压力 |
| `bloodSugar` | `time`, `date`, `items[{time,bloodSugar}]` | 血糖 |
| `temp` | `time`, `date`, `items[{time,temp}]` | 体温 |
| `muslimCount` | `time`, `date`, `totalCount`, `items[{time,count}]` | 念珠计数 |

---

### 4.9 OTA 升级

| 方法 / Stream | 参数 | 返回 | 说明 |
|--------------|------|------|------|
| `ringOta(String path)` | `path`: 固件文件本地路径 | `Future<void>` | 开始 OTA |
| `onOtaProgress` | — | `Stream<double>` 0.0–1.0 | OTA 进度 |
| `onOtaFinish` | — | `Stream<OtaResult>` | OTA 完成 |

**`OtaResult` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `success` | `bool` | 是否成功 |
| `code` | `int?` | 错误码（仅失败时有值） |

---

### 4.10 解绑

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `unbind()` | 无 | `Future<void>` | 解绑设备（Android 下发解绑指令；iOS 清除绑定态+断开） |

---

### 4.11 消息推送 / 通知开关

| 方法 | 参数 | 返回 | 平台 | 说明 |
|------|------|------|------|------|
| `pushMessage(Map<String, dynamic> msg)` | 见下表 | `Future<void>` | **Android** | APP 主动推消息到设备显示；iOS no-op |
| `setNotificationSwitch(Map<String, dynamic> switches)` | 见下表 | `Future<void>` | **iOS** | 设置 ANCS 通知转发开关；Android no-op |
| `getNotificationSwitch()` | 无 | `Future<Map<String, dynamic>>` | **iOS** | 获取通知开关状态；Android 返回 `{}` |

**`pushMessage` 参数 Map：**

| key | 类型 | 必填 | 说明 |
|-----|------|------|------|
| `appId` | `String` | ✓ | App 标识 |
| `title` | `String` | ✓ | 消息标题 |
| `content` | `String` | ✓ | 消息内容 |
| `msgType` | `int` | 选填 | 消息类型 |
| `timeMill` | `int` | 选填 | 时间戳(毫秒) |

**`setNotificationSwitch` 参数 Map（key 为开关名，value 为 bool）：**

| key | 说明 | key | 说明 |
|-----|------|-----|------|
| `isCall` | 来电 | `isSMS` | 短信 |
| `isQQ` | QQ | `isWechat` | 微信 |
| `isWhatsapp` | WhatsApp | `isMessenger` | Messenger |
| `isTwitter` | Twitter | `isLinkedin` | LinkedIn |
| `isInstagram` | Instagram | `isFacebook` | Facebook |
| `isLine` | Line | `isWechatWork` | 企业微信 |
| `isDingding` | 钉钉 | `isEmail` | 邮件 |
| `isCalendar` | 日历 | `isViber` | Viber |
| `isSkype` | Skype | `isKakaotalk` | KakaoTalk |
| `isTumblr` | Tumblr | `isSnapchat` | Snapchat |
| `isYoutube` | YouTube | `isPinterset` | Pinterest |
| `isTiktok` | TikTok | `isGmail` | Gmail |
| `isJLSinaWeiBo` | 微博 | `isJLTelegram` | Telegram |
| `isOther` | 其他 | | |

---

## 5. 错误处理

所有请求-响应方法失败时抛出 `RwfitException`：

```dart
try {
  await ring.getPower();
} on RwfitException catch (e) {
  print('错误码: ${e.code}, 消息: ${e.message}');
}
```

`code == 0` 为成功（内部消费，不会抛出）；`code != 0` 均抛异常。

---

## 6. 关键约束

| 约束 | 说明 |
|------|------|
| **就绪信号** | 连接成功后**必须等 `onFunctionMenu`** 才可发指令；`connected` 早于就绪 |
| **实时测量互斥** | 同一时间只能开一种，切换前先 `stopRealtimeMeasure(...)` |
| **闹钟全量下发** | 改一条也要 `getAlarm → copyWith → setAlarm` 整批回发 |
| **能力门控在 App 侧** | 读 `FunctionMenu.raw` 做按钮灰显/隐藏，插件不替你判断 |
| **Android 12+ 权限** | `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT` 运行时动态申请 |
| **iOS 设备标识** | 优先用 `uuid` 关联（非 MAC），重连需先 `iosSetBindedStatus(true)` |
| **EventSink 释放** | 页面 `dispose` 时取消所有 Stream 订阅，避免事件叠加 |
| **平台独占方法** | 在不适用平台为 no-op 返回成功，可无条件调用 |

---

## 7. 重连与设备持久化

推荐做法（参考 `example/lib/device_store.dart`）：

1. 连接就绪(`onFunctionMenu`)时：保存设备 `{name, mac, uuid}` 到本地存储 + `iosSetBindedStatus(true)`
2. 下次启动：读取已保存设备，调 `reconnect(savedDevice)` 重连
3. 换设备：进扫描页前 `iosSetBindedStatus(false)` + 清除本地保存
4. 断开连接：只调 `disconnect()`，不清除保存（仍可重连）

```dart
// 重连
final saved = await DeviceStore.load();
if (saved != null) await ring.reconnect(saved);
```

---

## 8. 完整使用示例

```dart
import 'package:rwfit_ble/rwfit_ble.dart';

final ring = RwfitBle.instance;

// 初始化
await ring.init();

// 扫描
ring.onScanResult.listen((d) => print('${d.name} ${d.mac}'));
await ring.startScan();

// 连接 + 等就绪
ring.onFunctionMenu.listen((menu) async {
  // 可以开始操作了
  final power = await ring.getPower();
  print('电量: $power%');

  // 全天心率检测配置
  final hr = await ring.getTimedHeartRate();
  await ring.setTimedHeartRate(hr.copyWith(isOpen: true, duration: 30));

  // 实时心率
  ring.onRealtimeData.listen((d) {
    if (d.type == HealthType.hr) print('心率: ${d.value}');
  });
  await ring.startRealtimeMeasure(RealtimeMetric.hr);
});
await ring.connect(device);
```

---

## 9. FAQ

| 问题 | 解决 |
|------|------|
| 连上了但调用没反应 | 没等 `onFunctionMenu` 就发指令，请等就绪 |
| iOS 能否用模拟器 | **不支持 iOS 模拟器，仅支持真机**（模拟器无蓝牙；且插件已排除模拟器架构，Apple Silicon Mac 上跑模拟器会直接编译失败）。请用真机 |
| Android 12 扫描失败 | 缺运行时 `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT` 权限 |
| `minSdkVersion` 冲突 | App 的 `minSdk` 需 ≥ 26 |
| `Could not find com.rwfit:blesdk-rwfit:1.0` | **不是缓存或拉取问题**：App 没注册插件内置的原生 SDK 仓库。在 App 的 `android/build.gradle.kts` 加 `maven { url = uri("${project(":rwfit_ble").projectDir}/repo") }`，见 [2.1 Android](#21-android)。反复 `flutter clean`／清 pub-cache 都无效 |
| iOS "Module not found" | 确认 `pod install` 成功，`flutter clean` 后重新构建 |
