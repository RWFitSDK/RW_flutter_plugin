# RWFIT Ring Flutter Plugin — Integration Guide

---

## 1. Introduction

### 1.1 Supported Platforms and Languages

- Dart SDK `^3.12.0`, Flutter `>=3.3.0`
- Android minSdk **26**, compileSdk 35
- iOS **12.0+**; testing requires a **real device**

### 1.2 Terminology

- **App**: the Flutter application running on a phone or tablet
- **Device**: an RWFIT smart ring
- **Upload**: data sent from the device to the app
- **Command**: data or an operation sent from the app to the device
- **Ready signal**: the `onFunctionMenu` callback emitted after connection; business commands must wait for it
- **Full replacement**: a write operation for which the protocol requires the complete collection to be sent back, such as alarms

### 1.3 Notes

1. Use this plugin together with the `example/` project where possible. For a basic integration, focus on the scan page and device page.
2. All request/response methods return a `Future` and throw `RwfitException(code, message)` on failure. Events are typed `Stream`s; call `cancel()` in the page's `dispose` to avoid duplicate events.
3. **iOS simulators are not supported**. Simulators have no usable Bluetooth path for this plugin, and simulator architectures are excluded, so builds for an Apple Silicon simulator fail. Use a real device.
4. **Delivery is a GitHub repository plus a git dependency**. [`RWFitSDK/RW_flutter_plugin`](https://github.com/RWFitSDK/RW_flutter_plugin) includes `example/`, the bundled native SDKs (Android AAR in `android/repo/` and a vendored iOS `DHBleSDK.framework`), and Dart source. Pin a tag in the app's git dependency; no separate SDK files are required.

---

## 2. Quick Start

### Step 1: Add the Plugin

After cloning the repository, `example/` already uses a path dependency that points to the plugin root (`path: ../`), so it can be run directly:

```bash
git clone https://github.com/RWFitSDK/RW_flutter_plugin.git
cd RW_flutter_plugin/example
flutter pub get
flutter run   # iOS requires a real device
```

To integrate the plugin into your own app, declare a git dependency in the app's `pubspec.yaml` and pin the release tag with `ref`. No files need to be copied and no separate RW SDK is required:

```yaml
# <your_app>/pubspec.yaml
dependencies:
  rwfit_ble:
    git:
      url: https://github.com/RWFitSDK/RW_flutter_plugin.git
      ref: v0.0.4   # Pin the version; change this when upgrading
  # Used by the permission example below. You may use the app's existing
  # permission-management solution instead.
  permission_handler: ^12.0.2
```

```bash
flutter pub get          # After changing ref: flutter pub upgrade rwfit_ble
```

> The first iOS build runs `pod install` automatically; no custom native host is required.

### Step 2: Platform Configuration

**Android**

Set `minSdk = 26` in `android/app/build.gradle.kts`.

> ⚠️ **Required: register the plugin's bundled native SDK repository.** A successful `pub get` does not guarantee that Android can build. The RW ring native SDK AAR (`com.rwfit:blesdk-rwfit`) is bundled in the plugin's `android/repo` directory. **Gradle resolves `:app` transitive dependencies using the app's repository list; repositories declared inside the plugin do not propagate.** The app must therefore register the plugin's `repo` as a local Maven repository, or the build fails with `Could not find com.rwfit:blesdk-rwfit:2.260724`.

Add the following to `allprojects.repositories` in the app's root `android/build.gradle.kts`:

```kotlin
allprojects {
    repositories {
        google()
        mavenCentral()
        // RWFIT plugin's bundled native SDK repository. Using the :rwfit_ble
        // subproject's projectDir supports both path and git dependencies.
        maven { url = uri("${project(":rwfit_ble").projectDir}/repo") }
    }
}
```

Groovy DSL equivalent (`android/build.gradle`):

```groovy
allprojects {
    repositories {
        google()
        mavenCentral()
        maven { url "${project(':rwfit_ble').projectDir}/repo" }
    }
}
```

> If the app uses `settings.gradle(.kts)` with `dependencyResolutionManagement { repositoriesMode = RepositoriesMode.FAIL_ON_PROJECT_REPOS }`, add the `maven { ... }` entry to `dependencyResolutionManagement.repositories` instead, still using `project(":rwfit_ble").projectDir`.

`AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```

Android 12+ requires runtime requests for `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT`.

**iOS**

`Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Bluetooth is needed to connect to the RWFIT smart ring</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>Bluetooth is needed to connect to the RWFIT smart ring</string>
```

### Step 3: Initialize the SDK and Request Permissions

```dart
import 'dart:io';

import 'package:rwfit_ble/rwfit_ble.dart';
import 'package:permission_handler/permission_handler.dart';

if (Platform.isAndroid) {
  // Android 12+ needs runtime Bluetooth permissions. Older versions also
  // need location permission for scanning.
  await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
    Permission.locationWhenInUse,
  ].request();
}
// Initialize once per application.
await RwfitBle.instance.init();
```

> The plugin is distributed as Dart source plus bundled native SDKs. No native obfuscation configuration is required.

---

## 3. API Reference

> All methods return `Future` and throw `RwfitException(code, message)` on failure. Ordinary read/write commands wait for a device response. Startup methods such as scanning, connecting, finding a device, powering off, factory reset, health sync, and OTA only confirm that the task was initiated; use the corresponding event to determine the final state.
> Events are exposed as typed `Stream`s. Cancel subscriptions when the page is disposed.

### 3.1 Device Scanning, Connection, Binding, and Reconnection

##### 3.1.1 Scan for Bluetooth Devices

| Method / Stream | Parameters | Returns | Description |
|-----------------|------------|---------|-------------|
| `startScan()` | None | `Future<void>` | Start scanning supported devices; stops automatically after 10 seconds |
| `onScanResult` | — | `Stream<BleDevice>` | Emitted when a device is discovered |
| `onScanFinish` | — | `Stream<void>` | Emitted after automatic completion or `stopScan()` |

**`BleDevice` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `name` | `String` | Device name |
| `mac` | `String` | MAC address |
| `rssi` | `int` | Signal strength |
| `uuid` | `String?` | **iOS only**; primary device identifier that must be passed back when connecting |

```dart
ring.onScanResult.listen((d) => print('${d.name} ${d.mac}'));
await ring.startScan();
```

##### 3.1.2 Stop Scanning

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `stopScan()` | None | `Future<void>` | Stop scanning |

##### 3.1.3 Connect and Listen for State Changes

| Method / Stream | Parameters | Returns | Description |
|-----------------|------------|---------|-------------|
| `connect(BleDevice device)` | Complete `BleDevice` returned by scanning | `Future<void>` | Initiate a connection |
| `isConnected()` | None | `Future<bool>` | Whether the device is currently connected |
| `onConnectState` | — | `Stream<ConnectStateEvent>` | Connection-state changes |
| `onFunctionMenu` | — | `Stream<FunctionMenu>` | **Device ready signal**; business commands must wait for it |

**`ConnectStateEvent` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `state` | `ConnectState` enum | `connecting` / `connected` / `disconnected` / `failed` |
| `name` | `String?` | Device name |
| `mac` | `String?` | MAC address |
| `uuid` | `String?` | iOS only |
| `reason` | `String?` | Present only for `failed`; Android uses the native `RingBleError` enum name, while iOS always returns `"unknown"` because its native callback has no error parameter |

> [!TIP]
> `connected` is emitted before the device is ready. Send business commands only after `onFunctionMenu`.

##### 3.1.4 Disconnect

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `disconnect()` | None | `Future<void>` | Disconnect the device |

##### 3.1.5 Local Binding, Automatic Reconnection, and Unbinding

> [!IMPORTANT]
> As with the native SDKs, the app is responsible for local binding and persistence; see `example/lib/device_store.dart`. Save `{name, mac, uuid}` when the connection becomes ready and load it for reconnection on the next launch. On iOS, call `iosSetBindedStatus(true)` before reconnecting. See section 4.3 for the recommended flow.

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `reconnect([BleDevice? device])` | Optional; Android requires a device with `mac`, while iOS may pass null and use native reconnection | `Future<void>` | Reconnect a bound device |
| `iosSetBindedStatus(bool isBinded)` | `isBinded`: binding state | `Future<void>` | **iOS only**; Android no-op |
| `unbind()` | None | `Future<void>` | Unbind; Android sends the unbind command, while iOS clears binding state and disconnects |

##### 3.1.6 Device Capability Table

> [!IMPORTANT]
> Device models support different features. After the connection becomes ready, read `FunctionMenu` from `onFunctionMenu` and use it to disable or hide unsupported controls. The plugin does not gate business UI for the app.

**`FunctionMenu` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `name` | `String` | Device name |
| `mac` | `String` | MAC address |
| `uuid` | `String?` | Optional device identifier |
| `raw` | `Map<String, dynamic>` | `supportMenu` capability map |
| `supportsWorkout` | `bool` | Typed shortcut indicating multi-sport support |

**Capability properties:**

`onFunctionMenu.raw` and `getFunctionList()['supportMenu']` return the same normalized properties:

| Property | Type | Description |
|----------|------|-------------|
| `isPushMsgEnableSwitch` | `bool` | Whether the notification-control switch is enabled |
| `pushMsgSwitchValue` | `int` | Low 32 message-capability bits (bit 0–31) |
| `pushMsgSwitchValue2` | `int` | High 32 message-capability bits (bit 32–63); defaults to 0 on older devices |
| `activityDataInterval` | `int` | Intraday step-detail interval in minutes; returns 60 when not configured |
| `isAlarm` | `bool` | Alarm support |
| `isBrightScreenSleepTime` | `bool` | Sleep-mode screen schedule support |
| `isBrightScreenTime` | `bool` | Screen-on duration support |
| `isSupportWorkout` | `bool` | Multi-sport support |
| `isRememberSwitch` | `bool` | Muslim count switch support |
| `isSupportHrReminder` | `bool` | Heart-rate alert support |
| `isSupportBoReminder` | `bool` | SpO2 alert support |
| `isSupportMotoVibrationLevel` | `bool` | Motor vibration-level support |
| `isSupportAlarmVibrationDuration` | `bool` | Alarm vibration-count support |
| `isSupportVibrationInterval` | `bool` | Vibration-interval support |
| `isStep` | `bool` | Step support |
| `isHr` | `bool` | Heart-rate support |
| `isBloodPress` | `bool` | Blood-pressure support |
| `isSleep` | `bool` | Sleep support |
| `isBloodOxy` | `bool` | Blood-oxygen support |
| `isHrv` | `bool` | HRV support |
| `isPressure` | `bool` | Stress support |
| `isBloodSugar` | `bool` | Blood-sugar support |
| `isMuslimCountData` | `bool` | Muslim count data support |
| `isBodyTemp` | `bool` | Body-temperature data support |
| `isSupportMuslimTimeDisplayMode` | `bool` | Muslim time-display mode support |
| `isSupportSensorRawPPG` | `bool` | Raw PPG support |
| `isSupportPPGMonitoring` | `bool` | Timed PPG monitoring support |
| `isSupportTemperatureMonitoring` | `bool` | Timed temperature monitoring support |
| `isSupportCountReminder` | `bool` | Count-reminder interval support |
| `isSupportSensorRawACC` | `bool` | Raw ACC support |
| `isSupportSensorRawPPGRed` | `bool` | Raw red PPG support |
| `isSupportSensorRawIR` | `bool` | Raw IR support |
| `isSupportSensorRawSleep` | `bool` | Real-time sleep data support |
| `isSupportFallDetect` | `bool` | Fall-alert support |
| `isSupportRecording` | `bool` | Recording support |
| `isFindDevice` | `bool` | Find-device support |
| `isTakePhoto` | `bool` | Remote-camera support |
| `isLedLight` | `bool` | LED brightness support |
| `isWearDirection` | `bool` | Wear-direction support |
| `isVideoHid` | `bool` | Video HID support |
| `isVideoHidBook` | `bool` | Book HID mode support |
| `isVideoHidMusic` | `bool` | Music HID mode support |
| `isRaiseBrightScreen` | `bool` | Raise-to-wake support |
| `isPowerOff` | `bool` | Power-off support |
| `isFactoryReset` | `bool` | Factory-reset support |
| `isPushMessage` | `bool` | Message-push support |

**How to obtain capabilities:**

| Source | Returns | Description |
|--------|---------|-------------|
| `onFunctionMenu` | `Stream<FunctionMenu>` | Pushes the capability table when the connection becomes ready |
| `getFunctionList()` | `Future<Map<String, dynamic>>` | Actively gets the current table under `supportMenu` |

> [!NOTE]
> Prefer `onFunctionMenu` after connection. Before the table has been received, `getFunctionList()['supportMenu']` may be empty.

### 3.2 Device Operations

#### 3.2.1 Basic Command APIs

##### 3.2.1.1 Get SDK Version

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `getSdkVersion()` | None | `Future<String>` | Native SDK version |
| `getPluginVersion()` | None | `Future<String>` in `pluginVer_sdkVer` format | Plugin-specific API |

##### 3.2.1.2 Set User Information

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `setUserInfo(UserInfo info)` | `UserInfo` object | `Future<void>` | Set user biometrics |

**`UserInfo` constructor fields:**

| Field | Type | Description |
|-------|------|-------------|
| `gender` | `int` | 0=female, 1=male |
| `age` | `int` | Age |
| `height` | `double` | Height in cm |
| `weight` | `double` | Weight in kg |

##### 3.2.1.3 Get Device Information

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `getFirmwareVersion()` | None | `Future<FirmwareInfo>` | Firmware information |

**`FirmwareInfo` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `deviceClazz` | `String` | Device model |
| `deviceNo` | `String` | Firmware version |
| `uiVersion` | `String` | UI version |

> [!CAUTION]
> `deviceClazz` is the key field for matching OTA firmware. Before upgrading, confirm that the device value exactly matches the model declared by the firmware vendor.

##### 3.2.1.4 Get Battery Level

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `getPower()` | None | `Future<int>` | Battery percentage, 0–100 |

##### 3.2.1.5 Get and Set Video Control

> [!IMPORTANT]
> Android video control requires system Bluetooth HID pairing. A BLE connection or `setVideoHid()` does not perform this pairing. Call `createOrRemoveBond(1, mac)` to initiate pairing, or pass `type=2` to unpair.

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `getVideoHid()` | None | `Future<int>` | Get the `hidOpen` mode |
| `setVideoHid(int hidOpen)` | 0=off, 1=video, 2=Book, 3=Music | `Future<void>` | Set HID mode |
| `createOrRemoveBond(int type, String mac)` | `type`: 1=pair, 2=unpair; device MAC | `Future<bool>` indicating whether the operation was initiated | **Android only**, for system HID pairing; iOS no-op returns `false` |

##### 3.2.1.6 Get and Set LED Brightness

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `getRingLedLevel()` | None | `Future<LedLevel>` | Get LED brightness |
| `setRingLedLevel(LedLevel c)` | Configuration | `Future<void>` | Set LED brightness |

**`LedLevel` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `isOpen` | `bool` | Whether the LED is enabled |
| `lcdLevel` | `int` | 1=dim, 2=soft, 3=bright |

##### 3.2.1.7 Get and Set Wear Direction

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `getRingWearDir()` | None | `Future<bool>` | true=right hand, false=left hand |
| `setRingWearHand(bool isRight)` | `isRight`: true for right hand | `Future<void>` | Set the wearing hand |

##### 3.2.1.8 Start and Stop Camera Mode

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `controlPhoto(int state)` | 1=enter camera mode, 0=exit | `Future<void>` | Control camera mode |

After camera mode is enabled, a device-originated value of `2` requests the app to take a picture. The bridge normalizes it to `onTouchEvent`:

```dart
final photoSub = rwfit.onTouchEvent.listen((event) {
  if (event.action == TouchAction.cameraTakePicture) {
    // Trigger the app camera.
  }
});
```

Call `photoSub.cancel()` when the page is disposed. The app does not need to parse the raw value.

##### 3.2.1.9 Find Device

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `findDevice()` | None | `Future<void>` | Returns after issuing the command; LED or screen behavior depends on the model |

##### 3.2.1.10 Power Off and Factory Reset

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `powerOff()` | None | `Future<void>` | Returns after issuing the power-off command |
| `factoryReset()` | None | `Future<void>` | Returns after issuing the factory-reset command |

##### 3.2.1.11 Alarms

###### 3.2.1.11.1 Get Configured Alarms

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `getAlarm()` | None | `Future<List<Alarm>>` | Get all current alarms |

###### 3.2.1.11.2 Set Alarms

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `setAlarm(List<Alarm> alarms)` | Complete alarm list | `Future<void>` | **Full replacement** of all alarms |

> ⚠️ The protocol cannot update one alarm independently. Any change requires `getAlarm → copyWith → setAlarm` with the complete list.

**`Alarm` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `alarmId` | `int` | Alarm ID |
| `startHour` | `int` | Hour, 0–23 |
| `startMin` | `int` | Minute, 0–59 |
| `isOpen` | `bool` | Whether enabled |
| `repeats` | `List<int>` | Length 7, **Sunday through Saturday**; 1=on, 0=off |

Use `copyWith(...)` to change selected fields while preserving the others.

###### 3.2.1.11.3 Delete All Alarms

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `deleteAllAlarm()` | None | `Future<void>` | Delete all alarms |

##### 3.2.1.12 Get and Set Vibration Count

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `getVibrationCount()` | None | `Future<VibrationConfig>` | Get vibration configuration |
| `setVibrationCount(VibrationConfig c)` | Configuration | `Future<void>` | Set vibration configuration |

**`VibrationConfig` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `count` | `int` | 0–6; default 2, and 0 means no vibration |
| `level` | `int` | 0=off, 1=low, 2=medium, 3=high |

##### 3.2.1.13 Get and Set Screen Sleep Mode

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `getBrightScreenSleepTime()` | None | `Future<ScheduleToggle>` | Get the sleep-mode screen configuration |
| `setBrightScreenSleepTime(ScheduleToggle c)` | Configuration | `Future<void>` | Set the sleep-mode screen configuration |

**`ScheduleToggle` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `isOpen` | `bool` | Whether enabled |
| `startHour` | `int` | Start hour |
| `startMin` | `int` | Start minute |
| `endHour` | `int` | End hour |
| `endMin` | `int` | End minute |

##### 3.2.1.14 Messages and Calls

###### 3.2.1.14.1 Message Push

| Method | Parameters | Returns | Platform | Description |
|--------|------------|---------|----------|-------------|
| `pushMessage(Map<String, dynamic> msg)` | See below | `Future<void>` | **Android** | App pushes a message to the device display; iOS no-op |
| `setNotificationSwitch(Map<String, dynamic> switches)` | See below | `Future<void>` | **iOS** | Set ANCS notification-forwarding switches; Android no-op |
| `getNotificationSwitch()` | None | `Future<Map<String, dynamic>>` | **iOS** | Get notification switches; Android returns `{}` |

**`pushMessage` parameter map:**

| Key | Type | Required | Description |
|-----|------|----------|-------------|
| `appId` | `String` | Yes | App identifier |
| `title` | `String` | Yes | Message title |
| `content` | `String` | Yes | Message content |
| `msgType` | `int` | Optional | Message type |
| `timeMill` | `int` | Optional | Timestamp in milliseconds |

**`setNotificationSwitch` parameter map (key=switch name, value=`bool`):**

| Key | Description | Key | Description |
|-----|-------------|-----|-------------|
| `isCall` | Incoming call | `isSMS` | SMS |
| `isQQ` | QQ | `isWechat` | WeChat |
| `isWhatsapp` | WhatsApp | `isMessenger` | Messenger |
| `isTwitter` | Twitter | `isLinkedin` | LinkedIn |
| `isInstagram` | Instagram | `isFacebook` | Facebook |
| `isLine` | Line | `isWechatWork` | WeCom |
| `isDingding` | DingTalk | `isEmail` | Email |
| `isCalendar` | Calendar | `isViber` | Viber |
| `isSkype` | Skype | `isKakaotalk` | KakaoTalk |
| `isTumblr` | Tumblr | `isSnapchat` | Snapchat |
| `isYoutube` | YouTube | `isPinterset` | Pinterest |
| `isTiktok` | TikTok | `isGmail` | Gmail |
| `isJLSinaWeiBo` | Weibo | `isJLTelegram` | Telegram |
| `isJLBand` | Band | `isJLBetween` | Between |
| `isJLNavercafe` | Naver Cafe | `isJLNetflix` | Netflix |
| `isMax` | MAX | `isVkim` | VK Messenger |
| `isOther` | Other | | |

###### 3.2.1.14.2 Call Control

| Method / Stream | Parameters | Returns | Platform | Description |
|-----------------|------------|---------|----------|-------------|
| `controlPhone(CallControlAction action)` | `answer` or `reject` | `Future<void>` | **Android** | Send answer/reject state to the device; iOS no-op |
| `onCallControl` | — | `Stream<CallControlEvent>` | **Android** | Device-originated answer/reject action |

**`CallControlEvent` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `action` | `CallControlAction?` | `answer` or `reject`; null for an unknown value |
| `rawValue` | `int` | Raw Android SDK callback: 1=answer, 2=reject |

> iOS calls are handled by the system. `controlPhone` is a no-op and `onCallControl` emits no events on iOS.

###### 3.2.1.14.3 Music Control

On Android, connect the device and call `setVideoHid(3)` to select Music mode. After it succeeds, move the ring upward or downward to select the previous or next track; no additional listener is required.

iOS music control is handled by the system.

##### 3.2.1.15 Get and Set the Muslim Count Switch

Use this API only when `isRememberSwitch == true`. It enables or disables the Muslim count feature on the device.

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `getMuslimCountEnabled()` | None | `Future<bool>` | Get the Muslim count switch |
| `setMuslimCountEnabled(bool enabled)` | Enable state | `Future<void>` | Set the Muslim count switch |

##### 3.2.1.16 Get and Set Heart-Rate/Blood-Oxygen Alerts

| Method / Stream | Parameters | Returns | Description |
|-----------------|------------|---------|-------------|
| `getHeartRateAlert()` | None | `Future<HeartRateAlertConfig>` | Get heart-rate alerts |
| `setHeartRateAlert(HeartRateAlertConfig config)` | Configuration | `Future<void>` | Set high/low heart-rate alerts |
| `getBloodOxygenAlert()` | None | `Future<BloodOxygenAlertConfig>` | Get blood-oxygen alerts |
| `setBloodOxygenAlert(BloodOxygenAlertConfig config)` | Configuration | `Future<void>` | Set the low blood-oxygen alert |
| `onHealthAlert` | — | `Stream<HealthAlertEvent>` | Device-originated health alerts |

**`HeartRateAlertConfig` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `isOpen` | `bool` | Whether enabled |
| `highThreshold` | `int` | Alert above this value; device default is typically 160 bpm |
| `lowThreshold` | `int?` | Alert below this value; null means the device does not support low-heart-rate alerts |

**`BloodOxygenAlertConfig` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `isOpen` | `bool` | Whether enabled |
| `lowThreshold` | `int` | Alert below this value; protocol default is 94% |

**`HealthAlertEvent` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `type` | `HealthAlertType` | `highHeartRate`, `lowBloodOxygen`, `lowHeartRate`, or `unknown` |
| `rawType` | `int` | Raw alert type |
| `value` | `int` | Measurement that triggered the alert |

##### 3.2.1.17 Get and Set Screen-On Duration

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `getBrightScreenTime()` | None | `Future<int>` | Screen-on duration in seconds |
| `setBrightScreenTime(int timeSecond)` | `timeSecond`: duration in seconds | `Future<void>` | Set screen-on duration |

##### 3.2.1.18 Get and Set Raise-to-Wake Schedule

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `getRaiseBrightScreen()` | None | `Future<ScheduleToggle>` | Get raise-to-wake configuration |
| `setRaiseBrightScreen(ScheduleToggle c)` | Configuration | `Future<void>` | Set raise-to-wake configuration |

> See 3.2.1.13 for `ScheduleToggle` fields.

##### 3.2.1.19 Set 12/24-Hour Time Format

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `setTimeFormat(int format)` | `format`: 0=24-hour, 1=12-hour | `Future<void>` | Only effective on devices with a time display |

##### 3.2.1.20 Get and Set Alarm Vibration Duration

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `getAlarmVibrationDuration()` | None | `Future<int>` | Vibration count, 0–6 |
| `setAlarmVibrationDuration(int duration)` | Protocol value is actually a vibration count, 0–6 | `Future<void>` | Default 2; 0 means no vibration |

##### 3.2.1.21 Touch Event Notifications

| Method / Stream | Parameters | Returns | Description |
|-----------------|------------|---------|-------------|
| `onTouchEvent` | — | `Stream<TouchEvent>` | Touch, fall, camera, and music-control events |

**`TouchEvent` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `action` | `TouchAction` enum | Action type |
| `rawAction` | `String` | Raw action string |
| `keyType` | `int` | 1=touch key, 2=fall; 0 for camera/music events |
| `touchType` | `int` | 1=single, 2=double, 3=triple, 4=long press, 5=swing; 0 for camera/music events |

**`TouchAction` values:** `singleTap`, `doubleTap`, `tripleTap`, `longPress`, `swing`, `fallDetected`, `cameraTakePicture`, `musicPlay`, `musicPause`, `musicPrev`, `musicNext`, `musicVolumeUp`, `musicVolumeDown`, `unknown`.

> Camera actions are supported on both platforms. Music control depends on platform system capabilities and is supported by the Flutter event contract only on Android.

##### 3.2.1.22 Get and Set Vibration Interval

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `getVibrationInterval()` | None | `Future<int>` | Interval between vibrations in ms |
| `setVibrationInterval(int intervalMs)` | `intervalMs`: 100–1000 | `Future<void>` | Set the interval; device default is typically 500 ms |

##### 3.2.1.23 Heart-Rate Calibration (Factory Test)

| Method / Stream | Parameters | Returns | Description |
|-----------------|------------|---------|-------------|
| `startHeartRateCalibration()` | None | `Future<void>` | Start calibration; the bridge fixes test mode to `0x15` |
| `onHeartRateCalibration` | — | `Stream<HeartRateCalibrationResult>` | Calibration progress and result |

**`HeartRateCalibrationResult` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `testMode` | `int` | Heart-rate calibration uses `0x15` |
| `result` | `int` | 0=calibrating; non-zero=completed result |
| `isCalibrating` | `bool` | `result == 0` |
| `isCompleted` | `bool` | `result != 0` |

##### 3.2.1.24 Set Fall Detection

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `getFallDetect()` | None | `Future<bool>` | Get the fall-detection switch |
| `setFallDetect(bool enabled)` | Enable state | `Future<void>` | Set the fall-detection switch |

When enabled, detected falls are emitted through `onTouchEvent` with `action == TouchAction.fallDetected`.

##### 3.2.1.25 Set Count Reminder Interval

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `getCountReminderInterval()` | None | `Future<int>` | Get the reminder interval in minutes |
| `setCountReminderInterval(int intervalMinutes)` | 0, 30, 60, 90, or 120 | `Future<void>` | 0=off; other values are the interval |

#### 3.2.2 Health Data: Real-Time Measurement and All-Day Monitoring

##### 3.2.2.1 Start and Stop Real-Time Health Measurement

| Method / Stream | Parameters | Returns | Description |
|-----------------|------------|---------|-------------|
| `startRealtimeMeasure(RealtimeMetric m)` | `m`: measurement enum | `Future<void>` | Start real-time measurement |
| `stopRealtimeMeasure(RealtimeMetric m)` | `m`: measurement enum | `Future<void>` | Stop real-time measurement |
| `onRealtimeData` | — | `Stream<RealtimeData>` | Real-time measurement data |
| `onRealtimeMeasureComplete` | — | `Stream<void>` | Single-measurement completion event |

> ⚠️ **Mutual exclusion:** only one measurement type can be active. Stop the current type before starting another.

A successful `startRealtimeMeasure()` means only that the device accepted the start command. Subscribe to `onRealtimeMeasureComplete` before starting; the event indicates completion:

```dart
final completeSub = ring.onRealtimeMeasureComplete.listen((_) {
  print('Measurement complete');
});

await ring.startRealtimeMeasure(RealtimeMetric.hr);
```

**`RealtimeMetric` enum:**

| Value | Description |
|-------|-------------|
| `RealtimeMetric.hr` | Heart rate |
| `RealtimeMetric.bloodOxy` | Blood oxygen |
| `RealtimeMetric.hrv` | HRV |
| `RealtimeMetric.pressure` | Stress |
| `RealtimeMetric.bloodSugar` | Blood sugar |
| `RealtimeMetric.bloodPressure` | Blood pressure |

**`RealtimeData` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `type` | `HealthType?` | Data type |
| `value` | `double` | Primary value; blood sugar retains decimal precision, while integer-valued measurements use `.0` |
| `diastolic` | `int?` | Diastolic pressure, only for blood-pressure measurements |
| `timestampSec` | `int` | Unix timestamp in seconds, normalized across Android and iOS |
| `timestampMs` | `int` | **Deprecated compatibility getter**, equal to `timestampSec * 1000`; do not use in new code |

**`HealthType` enum:**

| Value | int value | Description |
|-------|-----------|-------------|
| `HealthType.hr` | 1 | Heart rate |
| `HealthType.bloodOxy` | 3 | Blood oxygen |
| `HealthType.bloodBp` | 4 | Blood pressure |
| `HealthType.pressure` | 8 | Stress |
| `HealthType.bloodSugar` | 9 | Blood sugar |
| `HealthType.hrv` | 13 | HRV |

##### 3.2.2.2 Configure All-Day Health Monitoring Intervals

Seven all-day health-monitoring types and timed PPG monitoring share `TimedConfig`. Getters return `Future<TimedConfig>` and setters accept `TimedConfig` and return `Future<void>`. This section lists the seven health types; timed PPG is covered in 3.2.5.0.

> [!IMPORTANT]
> Heart-rate and body-temperature intervals support 30 or 60 minutes. Blood oxygen, HRV, stress, blood sugar, and blood pressure use 60 minutes. Timed PPG defaults to 30 minutes; read the current device configuration before changing its switch. All monitoring windows are fixed to `00:00–23:59`, and the bridge clamps input and output to that full-day range.

**`TimedConfig` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `isOpen` | `bool` | Whether enabled |
| `duration` | `int` | Interval in minutes; constraints are listed below |
| `startHour` | `int` | Fixed to 0 |
| `startMin` | `int` | Fixed to 0 |
| `endHour` | `int` | Fixed to 23 |
| `endMin` | `int` | Fixed to 59 |

Use `copyWith(...)` to change the switch or interval while retaining other fields. Custom time fields are ignored and normalized to the full day.

###### 3.2.2.2.1 Get and Set Heart-Rate Monitoring

`getTimedHeartRate()` / `setTimedHeartRate(TimedConfig c)` — all-day heart-rate monitoring; interval must be 30 or 60 minutes.

###### 3.2.2.2.2 Get and Set Blood-Oxygen Monitoring

`getTimedBloodOxygen()` / `setTimedBloodOxygen(TimedConfig c)` — all-day blood-oxygen monitoring; interval is fixed at 60 minutes.

###### 3.2.2.2.3 Get and Set HRV Monitoring

`getTimedHRV()` / `setTimedHRV(TimedConfig c)` — all-day HRV monitoring; interval is fixed at 60 minutes.

###### 3.2.2.2.4 Get and Set Stress Monitoring

`getTimedStress()` / `setTimedStress(TimedConfig c)` — all-day stress monitoring; interval is fixed at 60 minutes.

###### 3.2.2.2.5 Get and Set Blood-Sugar Monitoring

`getTimedBloodSugar()` / `setTimedBloodSugar(TimedConfig c)` — all-day blood-sugar monitoring; interval is fixed at 60 minutes.

###### 3.2.2.2.6 Get and Set Blood-Pressure Monitoring

`getTimedBloodPressure()` / `setTimedBloodPressure(TimedConfig c)` — all-day blood-pressure monitoring; interval is fixed at 60 minutes.

###### 3.2.2.2.7 Get and Set Body-Temperature Monitoring

`getTimedBodyTemperature()` / `setTimedBodyTemperature(TimedConfig c)` — all-day body-temperature monitoring; interval must be 30 or 60 minutes.

##### 3.2.2.3 Synchronize All-Day Health History

| Method / Stream | Parameters | Returns | Description |
|-----------------|------------|---------|-------------|
| `syncAllHealthData()` | None | `Future<void>` | Start full health-data synchronization |
| `removeHealthDataCallback()` | None | `Future<void>` | Stop forwarding subsequent sync events to Flutter |
| `onSyncProgress` | — | `Stream<double>`, value 100 | Completion marker, immediately followed by `onSyncFinish` |
| `onSyncResult` | — | `Stream<SyncResult>` | Synchronized data |
| `onSyncFinish` | — | `Stream<void>` | Synchronization complete |
| `onSyncError` | — | `Stream<Map>` payload `{code}` | Synchronization error |

##### 3.2.2.4 All-Day Health Data Reference

> [!IMPORTANT]
> `time`, `beginTime`, `endTime`, and each detail item's `time` in this section are Unix timestamps in **seconds**. Multiply by `1000` when constructing a Dart `DateTime` from milliseconds.

###### 3.2.2.4.1 Health Callback Overview

**`SyncResult` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `type` | `String` | Data type; see below |
| `data` | `List<Map<String, dynamic>>` | Detailed records for that type |

**`type` values and typical fields in `data`:**

| type | Typical fields | Description |
|------|----------------|-------------|
| `step` | `time`, `date`, `activityDataInterval`, `totalSteps`, `totalCalorie`, `totalDistance`, `items[{time,index,steps,calorie,distance}]` | Steps |
| `sleep` | `time`, `date`, `duration`, `beginTime`, `endTime`, `items[{len,sleepType}]` | Sleep |
| `hr` | `time`, `date`, `items[{time,hr}]` | Heart rate |
| `bo` | `time`, `date`, `items[{time,bloodOxy}]` | Blood oxygen |
| `bp` | `time`, `date`, `items[{time,systolic,diastolic}]` | Blood pressure |
| `hrv` | `time`, `date`, `items[{time,hrv}]` | HRV |
| `pressure` | `time`, `date`, `items[{time,pressure}]` | Stress |
| `bloodSugar` | `time`, `date`, `items[{time,bloodSugar}]` | Blood sugar |
| `temp` | `time`, `date`, `items[{time,temp}]` | Body temperature |
| `muslimCount` | `time`, `date`, `totalCount`, `items[{time,count}]` | Muslim count |

###### 3.2.2.4.2 Standard Measurement Details

Except for step, sleep, and Muslim count data, measurement types are grouped by date and contain `time`, `date`, and `items`. Values and units are:

| Data | Value fields | Unit / Conversion |
|------|--------------|-------------------|
| Heart rate | `hr` | bpm |
| Blood pressure | `systolic`, `diastolic` | mmHg; systolic and diastolic pressure |
| Blood oxygen | `bloodOxy` | % |
| Body temperature | `temp` | Actual temperature is `temp / 10` °C; for example, 365 means 36.5 °C |
| Stress | `pressure` | Device stress value; unitless |
| Blood sugar | `bloodSugar` | Actual value as a `double`, retaining decimal precision |
| HRV | `hrv` | ms |

###### 3.2.2.4.3 Step Data

Each `step` date object contains:

| Field | Type | Description |
|-------|------|-------------|
| `time` | `int` | Date Unix timestamp in seconds |
| `date` | `String` | Date in `yyyyMMdd` format |
| `totalSteps` | `int` | Total steps for the day |
| `totalCalorie` | `int` | Total calories in cal |
| `totalDistance` | `int` | Total distance in m |
| `activityDataInterval` | `int` | Detail interval in minutes |
| `items` | `List<Map>` | `{time, index, steps, calorie, distance}`; `time` is Unix seconds |

###### 3.2.2.4.4 Sleep Data

Each `sleep` date object contains:

| Field | Type | Description |
|-------|------|-------------|
| `time` | `int` | Sleep-record Unix timestamp in seconds |
| `date` | `String` | Date in `yyyyMMdd` format |
| `duration` | `int` | Total sleep duration in minutes |
| `beginTime` / `endTime` | `int` | Sleep/wake Unix timestamps in seconds |
| `items` | `List<Map>` | `{len, sleepType}`; `len` is in minutes |

Historical `sleepType`: 0=awake, 1=light sleep, 2=deep sleep, 3=REM.

> These values differ from the raw real-time sleep protocol in 3.2.5.3, where 1=deep, 2=light, 3=awake, and 4=REM. Do not mix the protocols.

###### 3.2.2.4.5 Muslim Count Data

Each `muslimCount` date object contains:

| Field | Type | Description |
|-------|------|-------------|
| `time` | `int` | Date Unix timestamp in seconds |
| `date` | `String` | Date in `yyyyMMdd` format |
| `totalCount` | `int` | Total count for the day |
| `items` | `List<Map>` | `{time, count}`; `time` is Unix seconds |

#### 3.2.3 OTA Upgrade

> [!CAUTION]
> OTA firmware must be provided by the device vendor. First call `getFirmwareVersion()` and confirm that its non-empty `deviceClazz` exactly matches the non-empty model declared for the firmware file. Do not upgrade if they differ; mismatched firmware may make the device unusable.

```dart
final firmware = await ring.getFirmwareVersion();
const otaDeviceClazz = '<model declared by the device vendor>';
const otaPath = '<local path to the firmware file>';
if (firmware.deviceClazz.isEmpty ||
    otaDeviceClazz.isEmpty ||
    firmware.deviceClazz != otaDeviceClazz) {
  throw StateError(
    'OTA model mismatch: device=${firmware.deviceClazz}, '
    'firmware=$otaDeviceClazz',
  );
}
await ring.ringOta(otaPath);
```

| Method / Stream | Parameters | Returns | Description |
|-----------------|------------|---------|-------------|
| `ringOta(String path)` | Local firmware-file path | `Future<void>` | Returns when the OTA task is accepted, not when the upgrade completes |
| `onOtaProgress` | — | `Stream<double>` 0.0–1.0 | OTA progress |
| `onOtaFinish` | — | `Stream<OtaResult>` | OTA completion |

The Android bridge clamps OTA progress to `0.0–1.0`. The current Android SDK has been verified to report `0.0–1.0`; the `0–100` conversion branch is only defensive compatibility code and has not been observed with this SDK version.

**`OtaResult` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `success` | `bool` | Whether the upgrade succeeded |
| `code` | `int?` | Error code, present only on failure |

#### 3.2.4 Multi-Sport Workout

Enable this feature only when `FunctionMenu.supportsWorkout == true`. Query device state before starting a new workout to avoid replacing one already in progress. Disconnecting or closing the app does not stop the workout on the device. A workout must exceed two minutes before the device saves a history report.

##### 3.2.4.1 Get Device Workout State

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `getWorkoutState()` | None | `Future<WorkoutState>` | Get the current sport type and control state |

**`WorkoutState` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `sportType` | `int` | Current sport type |
| `controlType` | `WorkoutControlType` | Current control state |
| `isRunning` | `bool` | Whether a workout is active |

##### 3.2.4.2 Control a Device Workout

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `controlWorkout(int sportType, WorkoutControlType type)` | `sportType`: 7–161; start/resume/pause/end | `Future<void>` | Control workout state; throws `RwfitException` on failure |

**`WorkoutControlType` enum:**

| Value | int value | Description |
|-------|-----------|-------------|
| `WorkoutControlType.start` | `0x01` | Start |
| `WorkoutControlType.resume` | `0x02` | Resume |
| `WorkoutControlType.pause` | `0x03` | Pause |
| `WorkoutControlType.end` | `0x04` | End |
| `WorkoutControlType.unknown` | `-1` | Unrecognized; must not be sent as a control parameter |

##### 3.2.4.3 Enable or Disable Real-Time Workout Data

| Method / Stream | Parameters | Returns | Description |
|-----------------|------------|---------|-------------|
| `setWorkoutRealtimeEnabled(bool enabled)` | Enable state | `Future<void>` | Enable on workout-page entry and disable on exit |
| `onWorkoutRealtimeData` | — | `Stream<WorkoutRealtimeData>` | Real-time workout statistics |

**`WorkoutRealtimeData` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `duration` | `int` | Workout duration in seconds |
| `steps` | `int` | Step count |
| `distance` | `int` | Distance in m |
| `calorie` | `int` | Calories in Cal; Android is normalized to iOS semantics |
| `heartRate` | `int` | Real-time heart rate |
| `dataType` | `WorkoutDataType` | Always `appWorkoutData` in the public contract |
| `rawDataType` | `int` | Always `0x0223` in the public contract |

**`WorkoutDataType` enum:**

| Value | int value | Description |
|-------|-----------|-------------|
| `WorkoutDataType.appWorkoutData` | `0x0223` | Real-time workout data |
| `WorkoutDataType.enterOrExitWorkout` | `0x0274` | Compatibility value; current Flutter events do not return it |
| `WorkoutDataType.unknown` | `-1` | Unrecognized type |

##### 3.2.4.4 Get Workout Reports

| Method | Parameters | Returns | Description |
|--------|------------|---------|-------------|
| `getWorkoutReports()` | None | `Future<List<WorkoutReport>>` | Synchronize saved workout reports |

**`WorkoutReport` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `startTime` / `endTime` | `int` | Start/end Unix timestamps in seconds |
| `date` | `String` | Date in `yyyyMMdd` format |
| `sportType` | `int` | Sport type |
| `duration` | `int` | Duration in seconds |
| `step` / `distance` / `calorie` | `int` | Steps / distance in m / calories in Cal; Android is normalized to iOS semantics |
| `height` / `pressure` | `int` | Height / air pressure |
| `cadence` / `speed` / `pace` | `int` / `double` / `int` | Cadence / speed in m/h / pace |
| `averageHeartRate` | `int` | Average heart rate |
| `maxHeartRate` / `minHeartRate` | `int` | Maximum/minimum heart rate |
| `maxCadence` / `minCadence` | `int` | Maximum/minimum cadence |
| `maxPace` / `minPace` | `int` | Maximum/minimum pace |
| `heartRateCount` | `int` | Number of heart-rate samples |
| `viewType` | `int` | Workout data display type |
| `heartRateItems` | `List<WorkoutValueItem>` | Heart-rate details |
| `pacePerKmItems` | `List<WorkoutValueItem>` | Per-kilometer pace details |

`WorkoutValueItem` contains two `int` fields: `index` and `value`.

**Multi-sport example:**

```dart
final ring = RwfitBle.instance;

final sub = ring.onWorkoutRealtimeData.listen((data) {
  print('${data.duration}s, ${data.steps} steps, HR=${data.heartRate}');
});
await ring.setWorkoutRealtimeEnabled(true);

final state = await ring.getWorkoutState();
final sportType = state.isRunning ? state.sportType : 7; // 7=running
if (!state.isRunning) {
  await ring.controlWorkout(sportType, WorkoutControlType.start);
}

// Pause, resume, or end in response to user actions.
await ring.controlWorkout(sportType, WorkoutControlType.end);
await ring.setWorkoutRealtimeEnabled(false);
await sub.cancel();

final reports = await ring.getWorkoutReports();
```

#### 3.2.5 Raw Sensor Data

`SensorRawSelection` defines the valid sensor combinations:

| Enum | Value | Collection Combination |
|------|-------|------------------------|
| `acc` | 1 | ACC |
| `ppgGreen` | 2 | Green PPG |
| `ppgGreenAndAcc` | 3 | Green PPG + ACC |
| `ppgRed` | 4 | Red PPG |
| `ppgRedAndAcc` | 5 | Red PPG + ACC |
| `ppgGreenAndIr` | 10 | Green PPG + IR |
| `ppgGreenAccAndIr` | 11 | Green PPG + ACC + IR |
| `ppgRedAndIr` | 12 | Red PPG + IR |
| `ppgRedAccAndIr` | 13 | Red PPG + ACC + IR |

> Green and red PPG cannot be collected together, and IR cannot start alone. Selection values differ from returned data-type values; do not construct bit fields in app code. Use the enum directly.

##### 3.2.5.0 Timed PPG Monitoring

`getTimedPPG()` / `setTimedPPG(TimedConfig c)` — timed PPG monitoring; default interval is 30 minutes and the time range is fixed to `00:00–23:59`.

> [!IMPORTANT]
> The device retains only the latest timed PPG raw dataset. A subsequent measurement may overwrite unsynchronized data. Each completed measurement produces an `onSensorRawStopped` event; call `getSensorRawHistory()` promptly and persist the returned data.

##### 3.2.5.1 Start and Stop Raw Sensor Collection

| Method / Stream | Parameters | Returns | Description |
|-----------------|------------|---------|-------------|
| `controlSensorRaw(bool enabled, SensorRawSelection selection)` | `enabled`: enable state; `selection`: valid collection combination | `Future<void>` | Control raw-data collection |
| `onSensorRawData` | — | `Stream<SensorRawPacket>` | Device-originated raw-data packets |
| `onSensorRawStopped` | — | `Stream<SensorRawStoppedEvent>` | Device stopped collection; `reason` is the stop reason, and 0 means the native SDK supplied none |

When leaving the collection page, call `controlSensorRaw(false, selection)` with the same `selection`.

##### 3.2.5.2 Get Historical Raw Data

`getSensorRawHistory()` returns `Future<List<SensorRawPacket>>`. Each historical packet contains a data type, packet sequence, and sample array.

**`SensorRawPacket` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `type` | `SensorRawDataType` | Parsed data type |
| `rawType` | `int` | Raw type for forward compatibility |
| `sequence` | `int?` | Historical packet sequence; usually null for real-time packets |
| `timestampSec` | `int?` | Unix seconds; present only when supplied by the device |
| `ppg` | `List<int>` | Green PPG, int32 |
| `acc` | `List<AccRawSample>` | Three-axis ACC; each item contains int16 `x`, `y`, and `z` |
| `ppgRed` | `List<int>` | Red PPG, int32 |
| `ir` | `List<int>` | IR, int32 |
| `sleep` | `List<SleepRawSample>` | Real-time sleep state; each item contains `timestampSec` and `mode` |

**`SensorRawDataType`:** `timestamp(0)`, `ppg(1)`, `acc(2)`, `ppgRed(3)`, `ir(4)`, `sleep(5)`, `unknown(-1)`.

> The device typically stores up to approximately one minute of raw test data.

##### 3.2.5.3 Real-Time Sleep-State Push

On devices that support this feature, sleep packets are pushed automatically through `onSensorRawData`; do not call `controlSensorRaw()`. When `packet.type == SensorRawDataType.sleep`, read `packet.sleep`.

| `SleepRawSample.mode` | Description |
|-----------------------|-------------|
| 17 | Sleep started |
| 34 | Sleep ended |
| 1 | Deep sleep |
| 2 | Light sleep |
| 3 | Awake |
| 4 | REM |

This is the raw real-time sleep protocol and differs from historical `sleepType` in 3.2.2.4.4.

---

## 4. Appendix

### 4.1 Error Handling

All request/response methods throw `RwfitException` on failure:

```dart
try {
  await ring.getPower();
} on RwfitException catch (e) {
  print('Error code: ${e.code}, message: ${e.message}');
}
```

`code == 0` means success and is consumed internally; `code != 0` throws an exception.

### 4.2 Key Constraints

| Constraint | Description |
|------------|-------------|
| **Ready signal** | After connecting, **wait for `onFunctionMenu`** before sending commands; `connected` is earlier than ready |
| **Real-time measurement mutex** | Only one type at a time; call `stopRealtimeMeasure(...)` before switching |
| **Alarm full replacement** | Even one change requires `getAlarm → copyWith → setAlarm` with the complete list |
| **App-side capability gating** | Use `FunctionMenu.raw` to disable or hide controls; the plugin does not gate them |
| **Android 12+ permissions** | Request `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` at runtime |
| **iOS device identifier** | Associate devices by `uuid`, not MAC; call `iosSetBindedStatus(true)` before reconnecting |
| **EventSink cleanup** | Cancel all stream subscriptions when the page is disposed to avoid duplicate events |
| **Platform-exclusive methods** | Usually no-op on the inapplicable platform; returning without error does not mean the feature ran, so app logic must branch by platform |

### 4.3 Reconnection and Device Persistence

Recommended flow (see `example/lib/device_store.dart`):

1. When `onFunctionMenu` indicates ready, save `{name, mac, uuid}` locally and call `iosSetBindedStatus(true)`.
2. On the next launch, load the saved device and call `reconnect(savedDevice)`.
3. To switch devices, call `iosSetBindedStatus(false)` and clear local storage before entering the scan page.
4. On disconnect, call only `disconnect()`; retain storage so reconnection remains available.

```dart
import 'dart:io';

final saved = await DeviceStore.load();
if (saved != null) {
  if (Platform.isIOS) {
    await ring.iosSetBindedStatus(true);
  }
  await ring.reconnect(saved);
}
```

### 4.4 Full Usage Example

```dart
import 'dart:async';

import 'package:rwfit_ble/rwfit_ble.dart';

Future<void> connectAndRead() async {
  final ring = RwfitBle.instance;
  await ring.init();

  // Select the first result for brevity. A production app should let the user
  // select a device.
  final firstDevice = Completer<BleDevice>();
  final scanSub = ring.onScanResult.listen((device) {
    if (!firstDevice.isCompleted) firstDevice.complete(device);
  });
  await ring.startScan();
  final device = await firstDevice.future.timeout(const Duration(seconds: 15));
  await ring.stopScan();
  await scanSub.cancel();

  // Subscribe to the ready event before initiating the connection.
  final ready = Completer<FunctionMenu>();
  final readySub = ring.onFunctionMenu.listen((menu) {
    if (!ready.isCompleted) ready.complete(menu);
  });
  await ring.connect(device);
  final menu = await ready.future.timeout(const Duration(seconds: 15));
  print('Device ready: ${menu.name}');

  final power = await ring.getPower();
  print('Battery: $power%');

  // All-day heart rate supports only 30- or 60-minute intervals and always
  // uses the full-day time range.
  final hr = await ring.getTimedHeartRate();
  await ring.setTimedHeartRate(hr.copyWith(isOpen: true, duration: 30));

  final realtimeSub = ring.onRealtimeData.listen((d) {
    if (d.type == HealthType.hr) print('Heart rate: ${d.value}');
  });
  final completeSub = ring.onRealtimeMeasureComplete.listen((_) {
    print('Measurement complete');
  });
  await ring.startRealtimeMeasure(RealtimeMetric.hr);

  // Release resources when the page exits or measurement completes.
  await ring.stopRealtimeMeasure(RealtimeMetric.hr);
  await realtimeSub.cancel();
  await completeSub.cancel();
  await readySub.cancel();
}
```

---

## Flutter Plugin Revision History

**v0.0.4_20260806** (2026.08.06)

- Fixed `pubspec.yaml` comment parsing failures affecting GitHub dependencies in some environments
- Added Chinese/English switching to the demo and refreshed the bilingual integration guides
- Updated native SDK version guidance and public release contents

**v0.0.3_20260731** (2026.07.31)

- Improved the Android/iOS bridges and aligned capability keys, events, and error semantics
- Added timed monitoring, health alerts, device controls, and raw sensor data features
- Added real-time measurement completion events and refined health sync and connection-state handling
- Added capability-based gating and related feature pages to the demo
- Documented timed PPG single-dataset retention and prompt synchronization requirements

**v0.0.2_20260729** (2026.07.29)

- Added multi-sport state queries, workout controls, real-time workout data, and history reports
- Added workout type selection and real-time workout example pages
- Standardized real-time health timestamps as Unix seconds with `timestampSec`, while retaining the compatible `timestampMs` getter

---

## Contact / Technical Support

developer@dhouse88.com
