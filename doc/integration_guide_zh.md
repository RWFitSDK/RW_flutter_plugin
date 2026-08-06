# RWFIT 戒指 Flutter 插件 —— 集成文档

---

## 1. 简介

### 1.1 适用平台与语言

- Dart SDK `^3.12.0`、Flutter `>=3.3.0`
- Android minSdk **26**、compileSdk 35
- iOS **12.0+**，需**真机**测试

### 1.2 相关术语

- **App**：手机/平板上运行的 Flutter 应用
- **设备**：RWFIT 智能戒指
- **上传**：设备向 App 发送数据
- **下发**：App 向设备发送数据
- **就绪信号**：连接成功后由 `onFunctionMenu` 回调，业务指令须在其之后发起
- **全量下发**：协议要求整批回传的写操作（如闹钟），改一条也要整批回发

### 1.3 注意事项

1. 使用此插件最好结合示例工程 `example/`；参考例子只需关注扫描页与设备页两个页面代码即可。
2. 所有请求-响应方法返回 `Future`，失败抛 `RwfitException(code, message)`；事件流为 typed `Stream`，页面 `dispose` 时须 `cancel()`，避免事件叠加。
3. **iOS 不支持模拟器**（模拟器无蓝牙；且插件已排除模拟器架构，Apple Silicon Mac 上跑模拟器会直接编译失败），请用真机。
4. **交付形式为 GitHub 仓库 + git 依赖**：仓库 [`RWFitSDK/RW_flutter_plugin`](https://github.com/RWFitSDK/RW_flutter_plugin) 含 `example/`、内置原生 SDK（Android aar 在 `android/repo/`，iOS `DHBleSDK.framework` 已 vendored）、Dart 源码。App 通过 git 依赖引入，用 tag 锁版本，无需额外 SDK 文件。

---

## 2. 快速开始（Quick Start）

### 第1步：引入插件

克隆仓库后，`example/` 已用 path 依赖指向插件本体（`path: ../`），开箱即用，进目录直接运行即可验证环境：

```bash
git clone https://github.com/RWFitSDK/RW_flutter_plugin.git
cd RW_flutter_plugin/example
flutter pub get
flutter run   # iOS 需真机
```

集成进你自己的 App：在 App 的 `pubspec.yaml` 声明 git 依赖（用 `ref` 锁定版本 tag），无需拷贝任何文件、无需单独获取 RW SDK：

```yaml
# <your_app>/pubspec.yaml
dependencies:
  rwfit_ble:
    git:
      url: https://github.com/RWFitSDK/RW_flutter_plugin.git
      ref: v0.0.4   # 锁定版本，升级时改这里
  # 下方权限申请示例使用；也可替换为 App 现有的权限管理方案
  permission_handler: ^12.0.2
```

```bash
flutter pub get          # 升级版本改 ref 后：flutter pub upgrade rwfit_ble
```

> iOS 首次构建会自动 `pod install`（无需自定义基座）。

### 第2步：平台配置

**Android**

`android/app/build.gradle.kts`：`minSdk = 26`

> ⚠️ **必需：注册插件内置的原生 SDK 仓库**。`pub get` 成功 ≠ 能构建。插件随包内置了 RW 戒指原生 SDK 的 AAR（`com.rwfit:blesdk-rwfit`），位于插件目录的 `android/repo`。**Gradle 解析 `:app` 的传递依赖时用的是 App 自己的仓库列表，插件内部声明的仓库不会传递过来**，所以必须在 **App 侧**把插件目录下的 `repo` 注册为本地 maven 仓库，否则构建报 `Could not find com.rwfit:blesdk-rwfit:2.260724`。详见「第 2 步：平台配置」。

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

**iOS**

`Info.plist`：

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>需要蓝牙以连接 RWFIT 智能戒指</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>需要蓝牙以连接 RWFIT 智能戒指</string>
```

### 第3步：初始化 SDK 与权限

```dart
import 'dart:io';

import 'package:rwfit_ble/rwfit_ble.dart';
import 'package:permission_handler/permission_handler.dart';

if (Platform.isAndroid) {
  // Android 12+ 需要蓝牙运行时权限；旧版本扫描还需要定位权限。
  await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.locationWhenInUse,
  ].request();
}
// 初始化 SDK（全应用一次）
await RwfitBle.instance.init();
```

> 插件以 Dart 源码 + 内置原生 SDK 形式分发，无原生混淆配置需求。

---

## 3. 接口说明（API Reference）

> 所有方法返回 `Future`，调用失败抛 `RwfitException(code, message)`。普通读写指令等待设备响应；扫描、连接、查找设备、关机/恢复出厂、健康同步及 OTA 等启动型方法仅表示任务已发起，最终状态通过对应事件确认。
> 事件流通过 typed `Stream` 暴露，需在页面 `dispose` 时 `cancel()`。

### 3.1 设备搜索与连接, 绑定与重连

##### 3.1.1 搜索蓝牙

| 方法 / Stream | 参数 | 返回 | 说明 |
|--------------|------|------|------|
| `startScan()` | 无 | `Future<void>` | 开始扫描支持的设备；10 秒后自动结束 |
| `onScanResult` | — | `Stream<BleDevice>` | 扫描到设备时触发 |
| `onScanFinish` | — | `Stream<void>` | 自动结束或调用 `stopScan()` 时触发 |

**`BleDevice` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | `String` | 设备名称 |
| `mac` | `String` | MAC 地址 |
| `rssi` | `int` | 信号强度 |
| `uuid` | `String?` | **仅 iOS**，设备主标识；连接时必须回传 |

```dart
ring.onScanResult.listen((d) => print('${d.name} ${d.mac}'));
await ring.startScan();
```

##### 3.1.2 停止搜索

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `stopScan()` | 无 | `Future<void>` | 停止扫描 |

##### 3.1.3 连接设备与状态监听

| 方法 / Stream | 参数 | 返回 | 说明 |
|--------------|------|------|------|
| `connect(BleDevice device)` | 扫描得到的完整 `BleDevice` | `Future<void>` | 发起连接 |
| `isConnected()` | 无 | `Future<bool>` | 当前是否已连接 |
| `onConnectState` | — | `Stream<ConnectStateEvent>` | 连接状态变化 |
| `onFunctionMenu` | — | `Stream<FunctionMenu>` | **设备就绪信号**，收到后才可发业务指令 |

**`ConnectStateEvent` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `state` | `ConnectState` 枚举 | `connecting` / `connected` / `disconnected` / `failed` |
| `name` | `String?` | 设备名 |
| `mac` | `String?` | MAC |
| `uuid` | `String?` | 仅 iOS |
| `reason` | `String?` | 仅 `failed` 时有；Android 为原生 `RingBleError` 枚举名，iOS 原生回调不提供错误参数，固定为 `"unknown"` |

> [!TIP]
> 连接后，业务操作应在 `onFunctionMenu`（设备就绪）之后才进行；`connected` 早于就绪。

##### 3.1.4 断开连接设备

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `disconnect()` | 无 | `Future<void>` | 断开连接 |

##### 3.1.5 本地绑定与自动重连,解绑

> [!IMPORTANT]
> 与原生 SDK 一致，本地绑定/持久化需 App 自行实现（参考 `example/lib/device_store.dart`）。连接就绪时保存设备 `{name, mac, uuid}`，下次启动读取后重连。iOS 重连前需先 `iosSetBindedStatus(true)`。推荐做法见「4.3 重连与设备持久化」。

| 方法 | 参数 | 返回 | 说明 |
|--------------|------|------|------|
| `reconnect([BleDevice? device])` | 可选，Android 需传(含 mac)；iOS 可空(走内置重连) | `Future<void>` | 重连已绑定设备 |
| `iosSetBindedStatus(bool isBinded)` | `isBinded`：绑定状态 | `Future<void>` | **iOS 专用**，Android no-op |
| `unbind()` | 无 | `Future<void>` | 解绑设备（Android 下发解绑指令；iOS 清除绑定态+断开） |

##### 3.1.6 设备功能配置表

> [!IMPORTANT]
> 因设备型号多、支持功能不同，连接就绪后通过 `onFunctionMenu` 获取能力表 `FunctionMenu`，App 据此做按钮灰显/隐藏，插件不替你判断。

**`FunctionMenu` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `name` | `String` | 设备名 |
| `mac` | `String` | MAC |
| `uuid` | `String?` | 可选设备标识 |
| `raw` | `Map<String, dynamic>` | supportMenu 能力表 |
| `supportsWorkout` | `bool` | 是否支持多运动（便捷字段） |

**功能属性：**

`onFunctionMenu.raw` 与 `getFunctionList()['supportMenu']` 返回相同的统一功能属性：

| 属性 | 类型 | 说明 |
|---|---|---|
| `isPushMsgEnableSwitch` | `bool` | 是否启用消息控制开关 |
| `pushMsgSwitchValue` | `int` | 消息类型支持能力低 32 位（bit0-bit31） |
| `pushMsgSwitchValue2` | `int` | 消息类型支持能力高 32 位（bit32-bit63），旧设备默认为 0 |
| `activityDataInterval` | `int` | 当天计步明细间隔，单位分钟；未配置时返回 60 |
| `isAlarm` | `bool` | 是否支持闹钟 |
| `isBrightScreenSleepTime` | `bool` | 是否支持屏幕睡眠时间设置 |
| `isBrightScreenTime` | `bool` | 是否支持亮屏时长设置 |
| `isSupportWorkout` | `bool` | 是否支持多运动 |
| `isRememberSwitch` | `bool` | 是否支持 Muslim 赞念/计数开关 |
| `isSupportHrReminder` | `bool` | 是否支持 HR 报警提示 |
| `isSupportBoReminder` | `bool` | 是否支持 SpO2 报警提示 |
| `isSupportMotoVibrationLevel` | `bool` | 是否支持马达震动等级 |
| `isSupportAlarmVibrationDuration` | `bool` | 是否支持闹钟震动次数设置 |
| `isSupportVibrationInterval` | `bool` | 是否支持震动间隔时长设置 |
| `isStep` | `bool` | 是否支持计步 |
| `isHr` | `bool` | 是否支持心率 |
| `isBloodPress` | `bool` | 是否支持血压 |
| `isSleep` | `bool` | 是否支持睡眠 |
| `isBloodOxy` | `bool` | 是否支持血氧 |
| `isHrv` | `bool` | 是否支持心率变异性 |
| `isPressure` | `bool` | 是否支持压力 |
| `isBloodSugar` | `bool` | 是否支持血糖 |
| `isMuslimCountData` | `bool` | 是否支持 Muslim 赞念/计数数据 |
| `isBodyTemp` | `bool` | 是否支持体温 |
| `isSupportMuslimTimeDisplayMode` | `bool` | 是否支持 Muslim 时间显示模式 |
| `isSupportSensorRawPPG` | `bool` | 是否支持获取 PPG 原始数据 |
| `isSupportPPGMonitoring` | `bool` | 是否支持 PPG 定时监测 |
| `isSupportTemperatureMonitoring` | `bool` | 是否支持温度定时监测 |
| `isSupportCountReminder` | `bool` | 是否支持计数提醒间隔设置 |
| `isSupportSensorRawACC` | `bool` | 是否支持获取 ACC 原始数据 |
| `isSupportSensorRawPPGRed` | `bool` | 是否支持获取 PPG Red 原始数据 |
| `isSupportSensorRawIR` | `bool` | 是否支持获取 IR 红外原始数据 |
| `isSupportSensorRawSleep` | `bool` | 是否支持睡眠实时数据 |
| `isSupportFallDetect` | `bool` | 是否支持跌落提醒 |
| `isSupportRecording` | `bool` | 是否支持录音 |
| `isFindDevice` | `bool` | 是否支持查找设备 |
| `isTakePhoto` | `bool` | 是否支持遥控拍照 |
| `isLedLight` | `bool` | 是否支持 LED 亮度设置 |
| `isWearDirection` | `bool` | 是否支持佩戴方向设置 |
| `isVideoHid` | `bool` | 是否支持视频 HID |
| `isVideoHidBook` | `bool` | 是否支持 Book HID 模式 |
| `isVideoHidMusic` | `bool` | 是否支持 Music HID 模式 |
| `isRaiseBrightScreen` | `bool` | 是否支持抬腕亮屏 |
| `isPowerOff` | `bool` | 是否支持关机 |
| `isFactoryReset` | `bool` | 是否支持恢复出厂设置 |
| `isPushMessage` | `bool` | 是否支持消息推送 |

**获取方式：**

| 方式 | 返回 | 说明 |
|---|---|---|
| `onFunctionMenu` | `Stream<FunctionMenu>` | 连接就绪后推送设备功能表 |
| `getFunctionList()` | `Future<Map<String, dynamic>>` | 主动获取当前功能表，属性位于返回值的 `supportMenu` 中 |

> [!NOTE]
> 建议优先使用连接就绪后推送的 `onFunctionMenu`。尚未获取到设备功能表时，`getFunctionList()` 的 `supportMenu` 可能为空。

### 3.2 设备功能操作

#### 3.2.1 基础功能指令接口

##### 3.2.1.1 Get SDK Version

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `getSdkVersion()` | 无 | `Future<String>` 原生 SDK 版本号 | |
| `getPluginVersion()` | 无 | `Future<String>` 格式 `pluginVer_sdkVer` | 插件额外提供 |

##### 3.2.1.2 设置用户信息

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `setUserInfo(UserInfo info)` | `UserInfo` 对象 | `Future<void>` | 设置用户体征 |

**`UserInfo` 字段（构造参数）：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `gender` | `int` | 0=女, 1=男 |
| `age` | `int` | 年龄 |
| `height` | `double` | 身高(cm) |
| `weight` | `double` | 体重(kg) |

##### 3.2.1.3 获取设备信息

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `getFirmwareVersion()` | 无 | `Future<FirmwareInfo>` | 固件版本信息 |

**`FirmwareInfo` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `deviceClazz` | `String` | 设备型号 |
| `deviceNo` | `String` | 固件版本号 |
| `uiVersion` | `String` | UI 版本 |

> [!CAUTION]
> `deviceClazz` 是 OTA 固件匹配的关键字段。升级前必须确认设备返回的 `deviceClazz` 与设备厂家提供的升级文件适用型号完全一致。

##### 3.2.1.4 获取电量

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `getPower()` | 无 | `Future<int>` 电量百分比 0–100 | |

##### 3.2.1.5 获取与设置视频控制开关

> [!IMPORTANT]
> Android 视频控制依赖系统蓝牙 HID 配对，仅连接 BLE 或调用
> `setVideoHid()` 不会完成该配对。未配对时调用
> `createOrRemoveBond(1, mac)` 发起配对；传入 `type=2` 可解除配对。

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `getVideoHid()` | 无 | `Future<int>` hidOpen 值 | 获取 HID 模式 |
| `setVideoHid(int hidOpen)` | `hidOpen`：0=关闭, 1=视频, 2=Book, 3=Music | `Future<void>` | 设置 HID 模式 |
| `createOrRemoveBond(int type, String mac)` | `type`：1=配对, 2=取消；`mac`：设备 MAC | `Future<bool>` 是否成功发起操作 | **Android 专用**，用于视频 HID 系统配对；iOS no-op 返回 `false` |

##### 3.2.1.6 获取与设置LED亮屏强度

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `getRingLedLevel()` | 无 | `Future<LedLevel>` | 获取 LED 亮度 |
| `setRingLedLevel(LedLevel c)` | 配置 | `Future<void>` | 设置 LED 亮度 |

**`LedLevel` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `isOpen` | `bool` | 是否开启 LED |
| `lcdLevel` | `int` | 亮度等级：1=微光, 2=柔光, 3=强光 |

##### 3.2.1.7 获取与设置佩戴位置

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `getRingWearDir()` | 无 | `Future<bool>` true=右手, false=左手 | |
| `setRingWearHand(bool isRight)` | `isRight`：true=右手佩戴 | `Future<void>` | |

##### 3.2.1.8 启动与关闭拍照

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `controlPhoto(int state)` | `state`：1=进入拍照模式, 0=退出 | `Future<void>` | 拍照控制 |

进入拍照模式后，设备主动上报值 `2` 表示请求 App 拍照。插件已将其统一转换为 `onTouchEvent` 事件：

```dart
final photoSub = rwfit.onTouchEvent.listen((event) {
  if (event.action == TouchAction.cameraTakePicture) {
    // 调用 App 相机完成拍照
  }
});
```

页面销毁时调用 `photoSub.cancel()`。原始值 `2` 由桥接层处理，App 无需解析。

##### 3.2.1.9 查找设备

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `findDevice()` | 无 | `Future<void>` | 发出查找设备指令后返回；设备灯或屏幕表现取决于设备 |

##### 3.2.1.10 关机,恢复出厂设置

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `powerOff()` | 无 | `Future<void>` | 发出关机指令后返回 |
| `factoryReset()` | 无 | `Future<void>` | 发出恢复出厂指令后返回 |

##### 3.2.1.11 闹钟

###### 3.2.1.11.1 获取已设置闹钟

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `getAlarm()` | 无 | `Future<List<Alarm>>` | 获取当前所有闹钟 |

###### 3.2.1.11.2 设置闹钟

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `setAlarm(List<Alarm> alarms)` | 完整闹钟列表 | `Future<void>` | **全量下发**所有闹钟 |

> ⚠️ 协议不支持单独修改某个闹钟，任何修改都要 `getAlarm → copyWith → setAlarm` 整批下发。

**`Alarm` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `alarmId` | `int` | 闹钟 ID |
| `startHour` | `int` | 时(0–23) |
| `startMin` | `int` | 分(0–59) |
| `isOpen` | `bool` | 是否启用 |
| `repeats` | `List<int>` | 长度 7，按**周日到周六**排列，1=开、0=关 |

可通过 `copyWith(...)` 复制当前闹钟并修改指定字段，未指定的字段保持不变。

###### 3.2.1.11.3 删除所有闹钟

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `deleteAllAlarm()` | 无 | `Future<void>` | 删除全部闹钟 |

##### 3.2.1.12 震动次数设置与获取

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `getVibrationCount()` | 无 | `Future<VibrationConfig>` | 获取振动配置 |
| `setVibrationCount(VibrationConfig c)` | 配置 | `Future<void>` | 设置振动配置 |

**`VibrationConfig` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `count` | `int` | 振动次数：0–6，默认 2；0 表示不振动 |
| `level` | `int` | 振动强度：0=关闭，1=低，2=中，3=高 |

##### 3.2.1.13 屏幕睡眠模式设置与获取

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `getBrightScreenSleepTime()` | 无 | `Future<ScheduleToggle>` | 获取睡眠模式亮屏配置 |
| `setBrightScreenSleepTime(ScheduleToggle c)` | 配置 | `Future<void>` | 设置睡眠模式亮屏 |

**`ScheduleToggle` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `isOpen` | `bool` | 是否开启 |
| `startHour` | `int` | 开始时-小时 |
| `startMin` | `int` | 开始时-分钟 |
| `endHour` | `int` | 结束时-小时 |
| `endMin` | `int` | 结束时-分钟 |

##### 3.2.1.14 消息与来电

###### 3.2.1.14.1 消息推送

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
| `isJLBand` | Band | `isJLBetween` | Between |
| `isJLNavercafe` | Naver Cafe | `isJLNetflix` | Netflix |
| `isMax` | MAX | `isVkim` | VK Messenger |
| `isOther` | 其他 | | |

###### 3.2.1.14.2 来电控制

| 方法 / Stream | 参数 | 返回 | 平台 | 说明 |
|--------------|------|------|------|------|
| `controlPhone(CallControlAction action)` | `answer` 或 `reject` | `Future<void>` | **Android** | 向设备发送接听/拒接状态；iOS no-op |
| `onCallControl` | — | `Stream<CallControlEvent>` | **Android** | 设备主动发来的接听/拒接动作 |

**`CallControlEvent` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `action` | `CallControlAction?` | `answer`=接听，`reject`=拒接；未知值为 null |
| `rawValue` | `int` | Android SDK 的原始回调值：1=接听，2=拒接 |

> iOS 通话由系统处理；调用 `controlPhone` 为 no-op，`onCallControl` 不会上报。

###### 3.2.1.14.3 音乐控制

Android 连接设备后，调用 `setVideoHid(3)` 设置 Music 模式。设置成功后，
上下晃动戒指即可控制上一曲或下一曲，无需额外监听事件。

iOS 音乐控制由系统处理。

##### 3.2.1.15 获取与设置赞念是否打开

仅在功能属性 `isRememberSwitch == true` 时使用。此功能仅用于打开或关闭设备上的赞念功能。

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `getMuslimCountEnabled()` | 无 | `Future<bool>` | 获取设备赞念功能开关 |
| `setMuslimCountEnabled(bool enabled)` | 是否开启 | `Future<void>` | 设置设备赞念功能开关 |

##### 3.2.1.16 获取与设置心率/血氧报警配置

| 方法 / Stream | 参数 | 返回 | 说明 |
|--------------|------|------|------|
| `getHeartRateAlert()` | 无 | `Future<HeartRateAlertConfig>` | 获取心率报警配置 |
| `setHeartRateAlert(HeartRateAlertConfig config)` | 心率配置 | `Future<void>` | 设置心率过高/过低报警 |
| `getBloodOxygenAlert()` | 无 | `Future<BloodOxygenAlertConfig>` | 获取血氧报警配置 |
| `setBloodOxygenAlert(BloodOxygenAlertConfig config)` | 血氧配置 | `Future<void>` | 设置血氧过低报警 |
| `onHealthAlert` | — | `Stream<HealthAlertEvent>` | 设备主动上报的健康报警 |

**`HeartRateAlertConfig` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `isOpen` | `bool` | 是否开启 |
| `highThreshold` | `int` | 心率高于该值时报警，设备默认通常为 160 bpm |
| `lowThreshold` | `int?` | 心率低于该值时报警；null 表示设备不支持低心率报警 |

**`BloodOxygenAlertConfig` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `isOpen` | `bool` | 是否开启 |
| `lowThreshold` | `int` | 血氧低于该值时报警，协议默认值为 94% |

**`HealthAlertEvent` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | `HealthAlertType` | `highHeartRate`、`lowBloodOxygen`、`lowHeartRate` 或 `unknown` |
| `rawType` | `int` | 原始报警类型值 |
| `value` | `int` | 触发报警的实际测量值 |

##### 3.2.1.17 获取与设置亮屏时长

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `getBrightScreenTime()` | 无 | `Future<int>` 亮屏时长(秒) | |
| `setBrightScreenTime(int timeSecond)` | `timeSecond`：亮屏时长(秒) | `Future<void>` | |

##### 3.2.1.18 获取与设置抬腕亮屏时长

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `getRaiseBrightScreen()` | 无 | `Future<ScheduleToggle>` | 获取抬腕亮屏配置 |
| `setRaiseBrightScreen(ScheduleToggle c)` | 配置 | `Future<void>` | 设置抬腕亮屏 |

> `ScheduleToggle` 字段见 3.2.1.13。

##### 3.2.1.19 设置时间格式12/24小时制

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `setTimeFormat(int format)` | `format`：0=24小时制, 1=12小时制 | `Future<void>` | 仅对带时间显示的设备有效 |

##### 3.2.1.20 闹钟震动时长设置与获取

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `getAlarmVibrationDuration()` | 无 | `Future<int>` 振动次数 0–6 | 获取闹钟振动次数 |
| `setAlarmVibrationDuration(int duration)` | `duration`：协议实际表示振动次数，0–6 | `Future<void>` | 默认 2 次；0 表示不振动 |



##### 3.2.1.21 触摸事件通知

| 方法 / Stream | 参数 | 返回 | 说明 |
|--------------|------|------|------|
| `onTouchEvent` | — | `Stream<TouchEvent>` | 触摸、跌落、拍照及音乐控制事件 |

**`TouchEvent` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `action` | `TouchAction` 枚举 | 动作类型 |
| `rawAction` | `String` | 原始动作字符串 |
| `keyType` | `int` | 1=触摸按键，2=跌落；拍照/音乐事件为 0 |
| `touchType` | `int` | 1=单击，2=双击，3=三击，4=长按，5=甩动；拍照/音乐事件为 0 |

**`TouchAction` 枚举值：** `singleTap`, `doubleTap`, `tripleTap`, `longPress`, `swing`, `fallDetected`, `cameraTakePicture`, `musicPlay`, `musicPause`, `musicPrev`, `musicNext`, `musicVolumeUp`, `musicVolumeDown`, `unknown`

> 拍照动作两端均支持；音乐控制依赖平台系统能力，仅 Android 支持。

##### 3.2.1.22 震动间隔时长设置与获取

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `getVibrationInterval()` | 无 | `Future<int>` | 获取每次震动之间的间隔，单位 ms |
| `setVibrationInterval(int intervalMs)` | `intervalMs`：100–1000 | `Future<void>` | 设置震动间隔；设备默认通常为 500 ms |

##### 3.2.1.23 心率校正(工厂测试)

| 方法 / Stream | 参数 | 返回 | 说明 |
|--------------|------|------|------|
| `startHeartRateCalibration()` | 无 | `Future<void>` | 启动心率校正，测试模式由桥接固定为 `0x15` |
| `onHeartRateCalibration` | — | `Stream<HeartRateCalibrationResult>` | 校正过程及最终结果 |

**`HeartRateCalibrationResult` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `testMode` | `int` | 测试模式；心率校正为 `0x15` |
| `result` | `int` | 0=校正中，非 0=校正完成结果 |
| `isCalibrating` | `bool` | `result == 0` |
| `isCompleted` | `bool` | `result != 0` |

##### 3.2.1.24 跌落提醒设置

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `getFallDetect()` | 无 | `Future<bool>` | 获取跌落提醒开关 |
| `setFallDetect(bool enabled)` | 是否开启 | `Future<void>` | 设置跌落提醒开关 |

开启后，设备检测到跌落会通过 `onTouchEvent` 上报，`action == TouchAction.fallDetected`。

##### 3.2.1.25 计数提醒间隔设置

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `getCountReminderInterval()` | 无 | `Future<int>` | 获取提醒间隔，单位分钟 |
| `setCountReminderInterval(int intervalMinutes)` | 0、30、60、90 或 120 | `Future<void>` | 0=关闭，其余为提醒间隔 |

#### 3.2.2 健康数据同步(实时单次与全天检测)

##### 3.2.2.1 实时检测-启动与关闭设备健康数据检测

| 方法 / Stream | 参数 | 返回 | 说明 |
|--------------|------|------|------|
| `startRealtimeMeasure(RealtimeMetric m)` | `m`：测量项枚举 | `Future<void>` | 开启实时测量 |
| `stopRealtimeMeasure(RealtimeMetric m)` | `m`：测量项枚举 | `Future<void>` | 停止实时测量 |
| `onRealtimeData` | — | `Stream<RealtimeData>` | 实时数据回调 |
| `onRealtimeMeasureComplete` | — | `Stream<void>` | 单次测量完成回调 |

> ⚠️ **互斥约束**：同一时间只能开启一种测量类型，切换前必须先 `stop` 当前类型。

`startRealtimeMeasure()` 返回成功仅表示设备已接受启动指令。请在启动前监听
`onRealtimeMeasureComplete`，收到回调后表示本次测量完成：

```dart
final completeSub = ring.onRealtimeMeasureComplete.listen((_) {
  print('测量完成');
});

await ring.startRealtimeMeasure(RealtimeMetric.hr);
```

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
| `value` | `double` | 测量主值；血糖保留小数，其他测量值以 `.0` 表示 |
| `diastolic` | `int?` | 舒张压（仅血压测量时有值） |
| `timestampSec` | `int` | 测量时间戳，Unix 秒（Android/iOS 已由桥接层统一） |
| `timestampMs` | `int` | **已废弃兼容 getter**，等于 `timestampSec * 1000`；新代码不要使用 |

**`HealthType` 枚举：**

| 值 | int value | 说明 |
|----|-----------|------|
| `HealthType.hr` | 1 | 心率 |
| `HealthType.bloodOxy` | 3 | 血氧 |
| `HealthType.bloodBp` | 4 | 血压 |
| `HealthType.pressure` | 8 | 压力 |
| `HealthType.bloodSugar` | 9 | 血糖 |
| `HealthType.hrv` | 13 | HRV |

##### 3.2.2.2 全天检测-设置健康数据全天监听间隔

7 项全天健康检测与 PPG 定时监测共用 `TimedConfig`：get 返回 `Future<TimedConfig>`，set 接收 `TimedConfig` 返回 `Future<void>`。本节详列 7 项全天健康检测，PPG 见 §3.2.5.0。

> [!IMPORTANT]
> 心率和体温间隔可设为 30 或 60 分钟；血氧、HRV、压力、血糖和血压固定为 60 分钟。PPG 默认间隔为 30 分钟，应优先读取设备当前配置后修改开关。所有检测的开始与结束时间固定为 `00:00–23:59`；桥接层会将输入和输出统一夹紧到该全天时段。

**`TimedConfig` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `isOpen` | `bool` | 是否开启 |
| `duration` | `int` | 检测间隔（分钟），具体限制见各小节 |
| `startHour` | `int` | 固定为 0 |
| `startMin` | `int` | 固定为 0 |
| `endHour` | `int` | 固定为 23 |
| `endMin` | `int` | 固定为 59 |

支持 `copyWith(...)` 便于修改开关或间隔后回发；自定义时间字段会被桥接层忽略并统一为全天。

###### 3.2.2.2.1 心率检测设置与获取

`getTimedHeartRate()` / `setTimedHeartRate(TimedConfig c)` — 全天心率检测，间隔仅支持 30 或 60 分钟。

###### 3.2.2.2.2 血氧检测设置与获取

`getTimedBloodOxygen()` / `setTimedBloodOxygen(TimedConfig c)` — 全天血氧检测，间隔固定 60 分钟。

###### 3.2.2.2.3 心率变异性(HRV)检测设置与获取

`getTimedHRV()` / `setTimedHRV(TimedConfig c)` — 全天 HRV 检测，间隔固定 60 分钟。

###### 3.2.2.2.4 压力检测设置与获取

`getTimedStress()` / `setTimedStress(TimedConfig c)` — 全天压力检测，间隔固定 60 分钟。

###### 3.2.2.2.5 血糖检测设置与获取

`getTimedBloodSugar()` / `setTimedBloodSugar(TimedConfig c)` — 全天血糖检测，间隔固定 60 分钟。

###### 3.2.2.2.6 血压检测设置与获取

`getTimedBloodPressure()` / `setTimedBloodPressure(TimedConfig c)` — 全天血压检测，间隔固定 60 分钟。

###### 3.2.2.2.7 体温检测设置与获取

`getTimedBodyTemperature()` / `setTimedBodyTemperature(TimedConfig c)` — 全天体温检测，间隔支持 30 或 60 分钟。

##### 3.2.2.3 全天检测-同步健康历史数据

| 方法 / Stream | 参数 | 返回 | 说明 |
|--------------|------|------|------|
| `syncAllHealthData()` | 无 | `Future<void>` | 发起全量健康数据同步 |
| `removeHealthDataCallback()` | 无 | `Future<void>` | 停止向 Flutter 转发后续同步事件 |
| `onSyncProgress` | — | `Stream<double>`，值为 100 | 同步完成标记；紧接着触发 `onSyncFinish` |
| `onSyncResult` | — | `Stream<SyncResult>` | 同步到的数据 |
| `onSyncFinish` | — | `Stream<void>` | 同步完成 |
| `onSyncError` | — | `Stream<Map>` payload: `{code}` | 同步错误 |

##### 3.2.2.4 全天检测-健康数据说明

> [!IMPORTANT]
> 本节中的 `time`、`beginTime`、`endTime` 及明细项 `time` 均为 Unix 时间戳，单位为**秒**；转换为 Dart `DateTime` 的毫秒时间戳时需乘以 `1000`。

###### 3.2.2.4.1 健康数据回调总览

**`SyncResult` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | `String` | 数据类型，见下表 |
| `data` | `List<Map<String, dynamic>>` | 该类型的数据明细列表 |

**`type` 取值与 data 内字段：**

| type | data item 典型字段 | 说明 |
|------|-------------------|------|
| `step` | `time`, `date`, `activityDataInterval`, `totalSteps`, `totalCalorie`, `totalDistance`, `items[{time,index,steps,calorie,distance}]` | 步数 |
| `sleep` | `time`, `date`, `duration`, `beginTime`, `endTime`, `items[{len,sleepType}]` | 睡眠 |
| `hr` | `time`, `date`, `items[{time,hr}]` | 心率 |
| `bo` | `time`, `date`, `items[{time,bloodOxy}]` | 血氧 |
| `bp` | `time`, `date`, `items[{time,systolic,diastolic}]` | 血压 |
| `hrv` | `time`, `date`, `items[{time,hrv}]` | HRV |
| `pressure` | `time`, `date`, `items[{time,pressure}]` | 压力 |
| `bloodSugar` | `time`, `date`, `items[{time,bloodSugar}]` | 血糖 |
| `temp` | `time`, `date`, `items[{time,temp}]` | 体温 |
| `muslimCount` | `time`, `date`, `totalCount`, `items[{time,count}]` | 念珠计数 |

###### 3.2.2.4.2 普通测量数据明细

除计步、睡眠和赞念外，普通测量类型均按日期返回 `time`、`date` 和 `items`。数值字段与单位如下：

| 数据 | 数值字段 | 单位 / 换算 |
|------|---------|-------------|
| 心率 | `hr` | bpm |
| 血压 | `systolic`, `diastolic` | mmHg，分别为收缩压和舒张压 |
| 血氧 | `bloodOxy` | % |
| 体温 | `temp` | 实际温度为 `temp / 10` ℃，例如 365 表示 36.5 ℃ |
| 压力 | `pressure` | 设备压力值，无单位 |
| 血糖 | `bloodSugar` | 实际血糖数值，`double`，保留小数精度 |
| HRV | `hrv` | ms |

###### 3.2.2.4.3 计步数据

`step` 每个日期对象包含：

| 字段 | 类型 | 说明 |
|------|------|------|
| `time` | `int` | 日期 Unix 时间戳，单位秒 |
| `date` | `String` | 日期，格式 `yyyyMMdd` |
| `totalSteps` | `int` | 当天总步数 |
| `totalCalorie` | `int` | 当天总热量，单位 cal |
| `totalDistance` | `int` | 当天总距离，单位 m |
| `activityDataInterval` | `int` | 计步明细间隔，单位分钟 |
| `items` | `List<Map>` | 明细项：`{time, index, steps, calorie, distance}`，`time` 为 Unix 秒 |

###### 3.2.2.4.4 睡眠数据

`sleep` 每个日期对象包含：

| 字段 | 类型 | 说明 |
|------|------|------|
| `time` | `int` | 睡眠记录 Unix 时间戳，单位秒 |
| `date` | `String` | 日期，格式 `yyyyMMdd` |
| `duration` | `int` | 睡眠总时长，单位分钟 |
| `beginTime` / `endTime` | `int` | 入睡/醒来 Unix 时间戳，单位秒 |
| `items` | `List<Map>` | `{len, sleepType}`；`len` 单位分钟 |

`sleepType`：0=清醒，1=浅睡，2=深睡，3=REM。

> 此处是历史睡眠数据的状态值。`3.2.5.3` 中 1=深睡、2=浅睡、3=清醒、4=REM 属于另一套“传感器原始睡眠实时推送”协议，两套取值不要混用。

###### 3.2.2.4.5 赞念数据

`muslimCount` 每个日期对象包含：

| 字段 | 类型 | 说明 |
|------|------|------|
| `time` | `int` | 日期 Unix 时间戳，单位秒 |
| `date` | `String` | 日期，格式 `yyyyMMdd` |
| `totalCount` | `int` | 当天总计数 |
| `items` | `List<Map>` | 明细项：`{time, count}`，其中 `time` 为 Unix 秒 |

#### 3.2.3 OTA升级

> [!CAUTION]
> OTA 固件必须由设备厂家提供。升级前先调用 `getFirmwareVersion()`，并确认返回的 `deviceClazz` 与厂家声明的固件适用型号均非空且完全一致；型号不一致时禁止升级，否则可能导致设备无法使用。

```dart
final firmware = await ring.getFirmwareVersion();
const otaDeviceClazz = '由设备厂家提供的适用型号';
const otaPath = '/固件文件的本地路径';
if (firmware.deviceClazz.isEmpty ||
    otaDeviceClazz.isEmpty ||
    firmware.deviceClazz != otaDeviceClazz) {
  throw StateError(
    'OTA 型号不匹配: device=${firmware.deviceClazz}, firmware=$otaDeviceClazz',
  );
}
await ring.ringOta(otaPath);
```

| 方法 / Stream | 参数 | 返回 | 说明 |
|--------------|------|------|------|
| `ringOta(String path)` | `path`：固件文件本地路径 | `Future<void>` | OTA 任务成功提交后返回；不代表升级完成 |
| `onOtaProgress` | — | `Stream<double>` 0.0–1.0 | OTA 进度 |
| `onOtaFinish` | — | `Stream<OtaResult>` | OTA 完成 |

Android 桥接会将 OTA 进度统一限制为 `0.0–1.0`。当前 Android SDK
已验证的回调尺度是 `0.0–1.0`；兼容 `0–100` 的换算分支仅为防御性保护，
未在当前 SDK 版本发现实际触发场景。

**`OtaResult` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `success` | `bool` | 是否成功 |
| `code` | `int?` | 错误码（仅失败时有值） |

#### 3.2.4 多运动Workout

仅在 `FunctionMenu.supportsWorkout == true` 时启用此功能。开始新运动前应先查询设备状态，避免覆盖正在进行的运动。App 断开或关闭不会结束设备上的运动；运动时长超过 2 分钟后，设备才会保存历史报告。

##### 3.2.4.1 获取设备多运动状态

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `getWorkoutState()` | 无 | `Future<WorkoutState>` | 查询当前运动类型与控制状态 |

**`WorkoutState` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `sportType` | `int` | 当前运动类型 |
| `controlType` | `WorkoutControlType` | 当前控制状态 |
| `isRunning` | `bool` | 是否存在正在进行的运动 |

##### 3.2.4.2 控制设备进入多运动

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `controlWorkout(int sportType, WorkoutControlType type)` | `sportType`：7～161；`type`：开始/继续/暂停/结束 | `Future<void>` | 控制运动状态；失败时抛出 `RwfitException` |

**`WorkoutControlType` 枚举：**

| 值 | int value | 说明 |
|----|-----------|------|
| `WorkoutControlType.start` | `0x01` | 开始 |
| `WorkoutControlType.resume` | `0x02` | 继续 |
| `WorkoutControlType.pause` | `0x03` | 暂停 |
| `WorkoutControlType.end` | `0x04` | 结束 |
| `WorkoutControlType.unknown` | `-1` | 未识别状态；不可作为控制参数发送 |

##### 3.2.4.3 控制开启/关闭设备实时通知运动数据

| 方法 / Stream | 参数 | 返回 | 说明 |
|--------------|------|------|------|
| `setWorkoutRealtimeEnabled(bool enabled)` | 是否开启实时数据 | `Future<void>` | 进入运动页面时开启，离开页面时关闭 |
| `onWorkoutRealtimeData` | — | `Stream<WorkoutRealtimeData>` | 实时运动统计 |

**`WorkoutRealtimeData` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `duration` | `int` | 运动时长（秒） |
| `steps` | `int` | 步数 |
| `distance` | `int` | 距离（米） |
| `calorie` | `int` | 热量（Cal）；Android 桥接已按 iOS 语义统一 |
| `heartRate` | `int` | 实时心率 |
| `dataType` | `WorkoutDataType` | 对外固定为 `appWorkoutData` |
| `rawDataType` | `int` | 对外固定为 `0x0223` |

**`WorkoutDataType` 枚举：**

| 值 | int value | 说明 |
|----|-----------|------|
| `WorkoutDataType.appWorkoutData` | `0x0223` | 运动过程中的实时数据 |
| `WorkoutDataType.enterOrExitWorkout` | `0x0274` | 保留的兼容枚举；当前 Flutter 事件不返回该值 |
| `WorkoutDataType.unknown` | `-1` | 未识别类型 |

##### 3.2.4.4 获取多运动数据报告

| 方法 | 参数 | 返回 | 说明 |
|------|------|------|------|
| `getWorkoutReports()` | 无 | `Future<List<WorkoutReport>>` | 同步设备保存的运动报告 |

**`WorkoutReport` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `startTime` / `endTime` | `int` | 开始/结束时间戳（秒） |
| `date` | `String` | 日期，格式 `yyyyMMdd` |
| `sportType` | `int` | 运动类型 |
| `duration` | `int` | 运动时长（秒） |
| `step` / `distance` / `calorie` | `int` | 步数 / 距离（米）/ 热量（Cal）；Android 已按 iOS 语义统一 |
| `height` / `pressure` | `int` | 高度 / 气压 |
| `cadence` / `speed` / `pace` | `int` / `double` / `int` | 步频 / 速度（m/h）/ 配速 |
| `averageHeartRate` | `int` | 平均心率 |
| `maxHeartRate` / `minHeartRate` | `int` | 最大/最小心率 |
| `maxCadence` / `minCadence` | `int` | 最大/最小步频 |
| `maxPace` / `minPace` | `int` | 最大/最小配速 |
| `heartRateCount` | `int` | 心率数据数量 |
| `viewType` | `int` | 运动数据显示类型 |
| `heartRateItems` | `List<WorkoutValueItem>` | 心率明细 |
| `pacePerKmItems` | `List<WorkoutValueItem>` | 每公里配速明细 |

`WorkoutValueItem` 包含 `index` 和 `value` 两个 `int` 字段。

**多运动使用示例：**

```dart
final ring = RwfitBle.instance;

final sub = ring.onWorkoutRealtimeData.listen((data) {
  print('${data.duration}s, ${data.steps} steps, HR=${data.heartRate}');
});
await ring.setWorkoutRealtimeEnabled(true);

final state = await ring.getWorkoutState();
final sportType = state.isRunning ? state.sportType : 7; // 7=跑步
if (!state.isRunning) {
  await ring.controlWorkout(sportType, WorkoutControlType.start);
}

// 根据用户操作暂停、继续或结束运动。
await ring.controlWorkout(sportType, WorkoutControlType.end);
await ring.setWorkoutRealtimeEnabled(false);
await sub.cancel();

final reports = await ring.getWorkoutReports();
```

#### 3.2.5 传感器原始数据

传感器控制组合由 `SensorRawSelection` 枚举统一约束：

| 枚举 | 值 | 采集组合 |
|------|----|----------|
| `acc` | 1 | ACC |
| `ppgGreen` | 2 | 绿光 PPG |
| `ppgGreenAndAcc` | 3 | 绿光 PPG + ACC |
| `ppgRed` | 4 | 红光 PPG |
| `ppgRedAndAcc` | 5 | 红光 PPG + ACC |
| `ppgGreenAndIr` | 10 | 绿光 PPG + IR |
| `ppgGreenAccAndIr` | 11 | 绿光 PPG + ACC + IR |
| `ppgRedAndIr` | 12 | 红光 PPG + IR |
| `ppgRedAccAndIr` | 13 | 红光 PPG + ACC + IR |

> 绿光与红光不能同时采集；IR 不能单独启动。控制组合的编号与返回数据类型编号不同，业务代码不要自行拼位，直接使用枚举。

##### 3.2.5.0 PPG定时监测

`getTimedPPG()` / `setTimedPPG(TimedConfig c)` — PPG 定时监测；默认间隔为 30 分钟，时间范围固定为 `00:00–23:59`。

> [!IMPORTANT]
> 设备只保存最近一份 PPG 定时监测原始数据，下一次监测可能覆盖尚未同步的数据。每次监测完成后，设备会通过 `onSensorRawStopped` 发出停止通知；收到通知后应及时调用 `getSensorRawHistory()` 同步并持久化数据。

##### 3.2.5.1 启动与关闭传感器原始数据

| 方法 / Stream | 参数 | 返回 | 说明 |
|--------------|------|------|------|
| `controlSensorRaw(bool enabled, SensorRawSelection selection)` | `enabled`：开启/关闭；`selection`：合法采集组合 | `Future<void>` | 控制原始数据采集 |
| `onSensorRawData` | — | `Stream<SensorRawPacket>` | 设备主动推送的原始数据包 |
| `onSensorRawStopped` | — | `Stream<SensorRawStoppedEvent>` | 设备主动停止采集；`reason` 为停止原因，0 表示原生未提供原因 |

离开采集页面时应使用相同的 `selection` 调用 `controlSensorRaw(false, selection)`。

##### 3.2.5.2 历史原始数据获取

`getSensorRawHistory()` 返回 `Future<List<SensorRawPacket>>`。每个历史包包含数据类型、包序号和该包的采样数组。

**`SensorRawPacket` 字段：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `type` | `SensorRawDataType` | 已解析的数据类型 |
| `rawType` | `int` | 原始类型值，用于兼容新增类型 |
| `sequence` | `int?` | 历史包序号；实时包通常为空 |
| `timestampSec` | `int?` | Unix 秒；仅设备提供时间戳时有值 |
| `ppg` | `List<int>` | 绿光 PPG，int32 |
| `acc` | `List<AccRawSample>` | ACC 三轴值；每项含 `x`、`y`、`z`（int16） |
| `ppgRed` | `List<int>` | 红光 PPG，int32 |
| `ir` | `List<int>` | IR，int32 |
| `sleep` | `List<SleepRawSample>` | 睡眠实时状态；每项含 `timestampSec`、`mode` |

**`SensorRawDataType`：** `timestamp(0)`、`ppg(1)`、`acc(2)`、`ppgRed(3)`、`ir(4)`、`sleep(5)`、`unknown(-1)`。

> 原始数据设备通常最多保存约 1 分钟测试数据。

##### 3.2.5.3 睡眠状态实时推送

支持该功能时，设备会在睡眠过程中自动通过 `onSensorRawData` 推送，无需调用 `controlSensorRaw()`。判断 `packet.type == SensorRawDataType.sleep` 后读取 `packet.sleep`。

| `SleepRawSample.mode` | 说明 |
|-----------------------|------|
| 17 | 睡眠开始 |
| 34 | 睡眠结束 |
| 1 | 深睡 |
| 2 | 浅睡 |
| 3 | 清醒 |
| 4 | REM |

以上是原始睡眠实时协议，与 3.2.2.4.4 的历史睡眠 `sleepType` 不同。

---

## 4. 附录

### 4.1 错误处理

所有请求-响应方法失败时抛出 `RwfitException`：

```dart
try {
  await ring.getPower();
} on RwfitException catch (e) {
  print('错误码: ${e.code}, 消息: ${e.message}');
}
```

`code == 0` 为成功（内部消费，不会抛出）；`code != 0` 均抛异常。

### 4.2 关键约束

| 约束 | 说明 |
|------|------|
| **就绪信号** | 连接成功后**必须等 `onFunctionMenu`** 才可发指令；`connected` 早于就绪 |
| **实时测量互斥** | 同一时间只能开一种，切换前先 `stopRealtimeMeasure(...)` |
| **闹钟全量下发** | 改一条也要 `getAlarm → copyWith → setAlarm` 整批回发 |
| **能力门控在 App 侧** | 读 `FunctionMenu.raw` 做按钮灰显/隐藏，插件不替你判断 |
| **Android 12+ 权限** | `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT` 运行时动态申请 |
| **iOS 设备标识** | 优先用 `uuid` 关联（非 MAC），重连需先 `iosSetBindedStatus(true)` |
| **EventSink 释放** | 页面 `dispose` 时取消所有 Stream 订阅，避免事件叠加 |
| **平台独占方法** | 不适用平台通常 no-op；返回未报错不代表功能已执行，业务层应按平台区分 |

### 4.3 重连与设备持久化

推荐做法（参考 `example/lib/device_store.dart`）：

1. 连接就绪(`onFunctionMenu`)时：保存设备 `{name, mac, uuid}` 到本地存储 + `iosSetBindedStatus(true)`
2. 下次启动：读取已保存设备，调 `reconnect(savedDevice)` 重连
3. 换设备：进扫描页前 `iosSetBindedStatus(false)` + 清除本地保存
4. 断开连接：只调 `disconnect()`，不清除保存（仍可重连）

```dart
import 'dart:io';

// 重连
final saved = await DeviceStore.load();
if (saved != null) {
  if (Platform.isIOS) {
    await ring.iosSetBindedStatus(true);
  }
  await ring.reconnect(saved);
}
```

### 4.4 完整使用示例

```dart
import 'dart:async';

import 'package:rwfit_ble/rwfit_ble.dart';

Future<void> connectAndRead() async {
  final ring = RwfitBle.instance;
  await ring.init();

  // 扫描并取第一个设备。正式 App 应让用户从扫描结果中选择。
  final firstDevice = Completer<BleDevice>();
  final scanSub = ring.onScanResult.listen((device) {
    if (!firstDevice.isCompleted) firstDevice.complete(device);
  });
  await ring.startScan();
  final device = await firstDevice.future.timeout(const Duration(seconds: 15));
  await ring.stopScan();
  await scanSub.cancel();

  // 必须先订阅就绪事件，再发起连接。
  final ready = Completer<FunctionMenu>();
  final readySub = ring.onFunctionMenu.listen((menu) {
    if (!ready.isCompleted) ready.complete(menu);
  });
  await ring.connect(device);
  final menu = await ready.future.timeout(const Duration(seconds: 15));
  print('设备已就绪: ${menu.name}');

  final power = await ring.getPower();
  print('电量: $power%');

  // 全天心率仅支持 30 或 60 分钟，时间段固定为全天。
  final hr = await ring.getTimedHeartRate();
  await ring.setTimedHeartRate(hr.copyWith(isOpen: true, duration: 30));

  final realtimeSub = ring.onRealtimeData.listen((d) {
    if (d.type == HealthType.hr) print('心率: ${d.value}');
  });
  final completeSub = ring.onRealtimeMeasureComplete.listen((_) {
    print('测量完成');
  });
  await ring.startRealtimeMeasure(RealtimeMetric.hr);

  // 页面退出或测量完成时释放资源。
  await ring.stopRealtimeMeasure(RealtimeMetric.hr);
  await realtimeSub.cancel();
  await completeSub.cancel();
  await readySub.cancel();
}
```

---

## Flutter 插件修订记录

**v0.0.4_20260806** (2026.08.06)

- 修复部分环境通过 GitHub 依赖解析 `pubspec.yaml` 注释失败的问题
- Demo 新增中英文切换并完善双语集成文档
- 更新原生 SDK 版本说明及公开仓库发布内容

**v0.0.3_20260731** (2026.07.31)

- 完善 Android/iOS 双端桥接，统一能力字段、事件及错误语义
- 补充定时监测、健康提醒、设备控制和传感器原始数据等功能
- 新增实时单次测量完成通知，优化健康同步与连接状态处理
- Demo 增加设备能力门控并完善相关功能页面
- 补充 PPG 定时监测单份数据保留及完成后及时同步说明

**v0.0.2_20260729** (2026.07.29)

- 新增多运动状态查询、运动控制、实时运动数据和历史运动报告接口
- 新增运动类型列表和实时运动示例页面
- 实时健康数据时间戳统一为 Unix 秒，新增 `timestampSec`；保留 `timestampMs` 兼容 getter

---

## 联系方式 / 技术支持

developer@dhouse88.com
