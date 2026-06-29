# RWFIT Ring Flutter Plugin — Integration Guide

For **app developers**: integrate the `rwfit_ble` plugin into your Flutter project and get the "scan → connect → call" flow working.
See the runnable example in the plugin's `example/` directory.

---

## 0. Deliverables & Supported Platforms

| Item | Description |
|------|-------------|
| Delivery | **GitHub repo + git dependency**: Repository [`RWFitSDK/RW_flutter_plugin`](https://github.com/RWFitSDK/RW_flutter_plugin) includes `example/` (runnable out of the box), bundled native SDKs, and Dart source. Apps reference it through a git dependency and pin versions with tags |
| Native SDK | **Bundled**: Android AAR in `android/repo/`; iOS `DHBleSDK.framework` is vendored. **No additional SDK files are needed** |
| Android | minSdk **26**, compileSdk 35 |
| iOS | **12.0+**; requires a **real device** for testing |
| Flutter / Dart | Dart SDK `^3.12.0`, Flutter `>=3.3.0` |

---

## 1. Adding the Plugin

### 1.1 Run the Example First (Zero Config)

After cloning the repo, `example/` already uses a path dependency that points to the plugin root (`path: ../`), so it works out of the box:

```bash
git clone https://github.com/RWFitSDK/RW_flutter_plugin.git
cd RW_flutter_plugin/example
flutter pub get
flutter run   # iOS requires a real device
```

### 1.2 Integrate into Your Own App

Declare a git dependency in your app's `pubspec.yaml` and pin the version with `ref`. No file copying or separate SDK download is needed:

```yaml
# <your_app>/pubspec.yaml
dependencies:
  rwfit_ble:
    git:
      url: https://github.com/RWFitSDK/RW_flutter_plugin.git
      ref: v0.0.1   # Pin version; change this when upgrading
```

```bash
flutter pub get          # After changing ref: flutter pub upgrade rwfit_ble
```

> The first iOS build automatically runs `pod install` (no custom native host setup is required).
>
> ⚠️ **Android required reading**: a successful `pub get` does not guarantee the app can build. Android also needs the plugin's bundled native SDK repository registered in the app's `android/build.gradle.kts`; otherwise, you'll get `Could not find com.rwfit:blesdk-rwfit:1.0`. See [2.1 Android](#21-android).

---

## 2. Platform Configuration

### 2.1 Android

`android/app/build.gradle.kts`: `minSdk = 26`

#### Required: Register the Plugin's Bundled Native SDK Repository ⚠️

The plugin bundles the RW ring native SDK AAR (`com.rwfit:blesdk-rwfit`) in its `android/repo` directory. **Gradle resolves `:app`'s transitive dependencies using the app's own repository list; repositories declared inside the plugin do not propagate**. You must register the plugin's `repo` directory as a local Maven repository on the **app side**; otherwise, the build fails with:

```
Could not find com.rwfit:blesdk-rwfit:1.0.
```

Add the following to your app's root `android/build.gradle.kts` in `allprojects.repositories` (Kotlin DSL):

```kotlin
allprojects {
    repositories {
        google()
        mavenCentral()
        // RWFIT plugin's bundled native SDK repo. Uses the :rwfit_ble subproject's projectDir,
        // so both path dependencies and git dependencies work without hard-coded paths.
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

> If your app uses `settings.gradle(.kts)` with `dependencyResolutionManagement { repositoriesMode = RepositoriesMode.FAIL_ON_PROJECT_REPOS }`, add the `maven { ... }` entry to `dependencyResolutionManagement.repositories` in settings instead (still using `project(":rwfit_ble").projectDir`).

`AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30"/>
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation"/>
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT"/>
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>
```

Android 12+ requires **runtime permission requests** for `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT`.

### 2.2 iOS

`Info.plist`:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Bluetooth is needed to connect to the RWFIT smart ring</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>Bluetooth is needed to connect to the RWFIT smart ring</string>
```

---

## 3. Initialization & Permissions

```dart
import 'package:rwfit_ble/rwfit_ble.dart';
import 'package:permission_handler/permission_handler.dart';

// Android 12+ runtime Bluetooth permissions
await [Permission.bluetoothScan, Permission.bluetoothConnect, Permission.locationWhenInUse].request();
// Initialize SDK (once per app lifecycle)
await RwfitBle.instance.init();
```

---

## 4. API Reference

> All request/response methods return `Future` and throw `RwfitException` on failure.
> Event streams are exposed as typed `Stream`s. Remember to `cancel()` subscriptions in the page's `dispose`.

### 4.1 Initialization

| Method | Parameters | Returns | Description |
|--------|-----------|---------|-------------|
| `init()` | None | `Future<void>` | Initialize the SDK once at app startup |
| `getSdkVersion()` | None | `Future<String>` | Native SDK version |
| `getPluginVersion()` | None | `Future<String>` | Plugin version in `pluginVer_sdkVer` format |

---

### 4.2 Scanning

| Method / Stream | Parameters | Returns | Description |
|----------------|-----------|---------|-------------|
| `startScan({bool filter = true})` | `filter`: filter out unnamed devices, default `true` | `Future<void>` | Start scanning |
| `stopScan()` | None | `Future<void>` | Stop scanning |
| `onScanResult` | — | `Stream<BleDevice>` | Fires when a device is discovered |
| `onScanFinish` | — | `Stream<void>` | Fires when scanning ends |
| `onScanError` | — | `Stream<Map>` payload: `{code, msg}` | Scan error |

**`BleDevice` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `name` | `String` | Device name |
| `mac` | `String` | MAC address |
| `rssi` | `int` | Signal strength |
| `uuid` | `String?` | **iOS only**, primary device identifier; must be passed back when connecting |

---

### 4.3 Connection

| Method / Stream | Parameters | Returns | Description |
|----------------|-----------|---------|-------------|
| `connect(BleDevice device)` | Complete `BleDevice` from scan result | `Future<void>` | Initiate connection |
| `disconnect()` | None | `Future<void>` | Disconnect |
| `reconnect([BleDevice? device])` | Optional; Android requires it (with `mac`); iOS can be null and uses built-in reconnect | `Future<void>` | Reconnect to a bound device |
| `isConnected()` | None | `Future<bool>` | Whether currently connected |
| `iosSetBindedStatus(bool isBinded)` | `isBinded`: bound status | `Future<void>` | **iOS only**, Android no-op |
| `onConnectState` | — | `Stream<ConnectStateEvent>` | Connection state changes |
| `onFunctionMenu` | — | `Stream<FunctionMenu>` | **Device ready signal** — only send commands after receiving this |

**`ConnectStateEvent` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `state` | `ConnectState` enum | `connecting` / `connected` / `disconnected` / `failed` |
| `name` | `String?` | Device name |
| `mac` | `String?` | MAC |
| `uuid` | `String?` | iOS only |
| `reason` | `String?` | Only present on `failed` |

**`FunctionMenu` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `name` | `String` | Device name |
| `mac` | `String` | MAC |
| `uuid` | `String?` | iOS only |
| `raw` | `Map<String, dynamic>` | supportMenu capability map; the app uses this to show, hide, or disable UI |

Typical `raw` (supportMenu) keys: `isStep`, `isSleep`, `isHr`, `isBloodOxy`, `isBloodPress`, `isBloodSugar`, `isHrv`, `isPressure`, `isBodyTemp`, `isAlarm`, `isBrightScreenTime`, `isBrightScreenSleepTime`, `isPushMsgEnableSwitch`, `isFindDevice`, `isTakePhoto`, `isSupportMotoVibrationLevel`, `isSupportAlarmVibrationDuration`, `isMuslimCountData`, `isSupportMuslimTimeDisplayMode`. All values are `bool`.

---

### 4.4 Device Info

| Method | Parameters | Returns | Description |
|--------|-----------|---------|-------------|
| `getPower()` | None | `Future<int>` | Battery percentage, 0–100 |
| `getFirmwareVersion()` | None | `Future<FirmwareInfo>` | Firmware version info |
| `setUserInfo(UserInfo info)` | `UserInfo` object | `Future<void>` | Set user biometrics |
| `setTimeFormat(int format)` | `format`: 0=12-hour, 1=24-hour | `Future<void>` | Set the time display format |
| `getFunctionList()` | None | `Future<Map<String, dynamic>>` | Get device supported features |
| `setRingBtName(String name)` | `name`: new BT name | `Future<void>` | Change ring Bluetooth broadcast name |

**`FirmwareInfo` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `deviceClazz` | `String` | Device model |
| `deviceNo` | `String` | Firmware version number |
| `uiVersion` | `String` | UI version |

**`UserInfo` fields (constructor parameters):**

| Field | Type | Description |
|-------|------|-------------|
| `gender` | `int` | 0=female, 1=male |
| `age` | `int` | Age |
| `height` | `double` | Height (cm) |
| `weight` | `double` | Weight (kg) |

---

### 4.5 Timed Health Monitoring (6 Types)

All six APIs share identical signatures, with `TimedConfig` as input/output:

| Method | Description |
|--------|-------------|
| `getTimedHeartRate()` / `setTimedHeartRate(TimedConfig c)` | All-day heart rate monitoring |
| `getTimedBloodOxygen()` / `setTimedBloodOxygen(TimedConfig c)` | All-day blood oxygen monitoring |
| `getTimedHRV()` / `setTimedHRV(TimedConfig c)` | All-day HRV monitoring |
| `getTimedStress()` / `setTimedStress(TimedConfig c)` | All-day stress monitoring |
| `getTimedBloodSugar()` / `setTimedBloodSugar(TimedConfig c)` | All-day blood sugar monitoring |
| `getTimedBloodPressure()` / `setTimedBloodPressure(TimedConfig c)` | All-day blood pressure monitoring |

Each get method returns `Future<TimedConfig>`. Each set method accepts `TimedConfig` and returns `Future<void>`.

**`TimedConfig` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `isOpen` | `bool` | Whether enabled |
| `duration` | `int` | Measurement interval (minutes), default 60 |
| `startHour` | `int` | Start hour (0–23) |
| `startMin` | `int` | Start minute (0–59) |
| `endHour` | `int` | End hour (0–23) |
| `endMin` | `int` | End minute (0–59) |

`TimedConfig` supports `copyWith(...)` for modifying individual fields before sending the config back.

---

### 4.6 Real-Time Measurement

| Method / Stream | Parameters | Returns | Description |
|----------------|-----------|---------|-------------|
| `startRealtimeMeasure(RealtimeMetric m)` | `m`: measurement type enum | `Future<void>` | Start real-time measurement |
| `stopRealtimeMeasure(RealtimeMetric m)` | `m`: measurement type enum | `Future<void>` | Stop real-time measurement |
| `onRealtimeData` | — | `Stream<RealtimeData>` | Real-time data callback |

> ⚠️ **Mutual exclusion**: Only one measurement type can be active at a time. You must stop the current type before starting another.

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
| `type` | `HealthType?` | Data type enum |
| `value` | `int` | Primary measurement value |
| `diastolic` | `int?` | Diastolic pressure (only for blood pressure) |
| `timestampMs` | `int` | Measurement timestamp (milliseconds) |

**`HealthType` enum:**

| Value | int value | Description |
|-------|-----------|-------------|
| `HealthType.hr` | 1 | Heart rate |
| `HealthType.bloodOxy` | 3 | Blood oxygen |
| `HealthType.bloodBp` | 4 | Blood pressure |
| `HealthType.pressure` | 8 | Stress |
| `HealthType.bloodSugar` | 9 | Blood sugar |
| `HealthType.hrv` | 13 | HRV |

---

### 4.7 Device Control

#### 4.7.1 Basic Controls

| Method | Parameters | Returns | Description |
|--------|-----------|---------|-------------|
| `findDevice()` | None | `Future<void>` | Find device (device vibrates) |
| `powerOff()` | None | `Future<void>` | Power off |
| `factoryReset()` | None | `Future<void>` | Factory reset |
| `controlPhoto(int state)` | `state`: 1=enter photo mode, 0=exit | `Future<void>` | Photo control |
| `onTouchEvent` | — | `Stream<TouchEvent>` | Touch/photo/music control events |

**`TouchEvent` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `action` | `TouchAction` enum | Action type |
| `rawAction` | `String` | Raw action string |
| `keyType` | `int` | Reserved (currently always 0) |
| `touchType` | `int` | Reserved (currently always 0) |

**`TouchAction` enum values:** `cameraTakePicture`, `musicPlay`, `musicPause`, `musicPrev`, `musicNext`, `musicVolumeUp`, `musicVolumeDown`, `unknown`

---

#### 4.7.2 Alarms

| Method | Parameters | Returns | Description |
|--------|-----------|---------|-------------|
| `getAlarm()` | None | `Future<List<Alarm>>` | Get all current alarms |
| `setAlarm(List<Alarm> alarms)` | Complete alarm list | `Future<void>` | **Full replacement** of all alarms |
| `deleteAllAlarm()` | None | `Future<void>` | Delete all alarms |

> ⚠️ The protocol does not support modifying a single alarm. Any change requires `getAlarm → copyWith → setAlarm` with the full list.

**`Alarm` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `alarmId` | `int` | Alarm ID |
| `startHour` | `int` | Hour (0–23) |
| `startMin` | `int` | Minute (0–59) |
| `isOpen` | `bool` | Whether enabled |
| `alarmTag` | `String` | Label text |
| `repeats` | `List<int>` | Length 7, Monday–Sunday toggles (1=on, 0=off) |

Supports `copyWith(...)` for modifying individual fields.

---

#### 4.7.3 Screen Settings

| Method | Parameters | Returns | Description |
|--------|-----------|---------|-------------|
| `getRaiseBrightScreen()` | None | `Future<ScheduleToggle>` | Get raise-to-wake config |
| `setRaiseBrightScreen(ScheduleToggle c)` | Config | `Future<void>` | Set raise-to-wake |
| `getBrightScreenTime()` | None | `Future<int>` | Screen-on duration, in seconds |
| `setBrightScreenTime(int timeSecond)` | `timeSecond`: duration in seconds | `Future<void>` | Set the screen-on duration |
| `getBrightScreenSleepTime()` | None | `Future<ScheduleToggle>` | Get sleep mode screen config |
| `setBrightScreenSleepTime(ScheduleToggle c)` | Config | `Future<void>` | Set sleep mode screen |
| `getRingLedLevel()` | None | `Future<LedLevel>` | Get LED brightness |
| `setRingLedLevel(LedLevel c)` | Config | `Future<void>` | Set LED brightness |

**`ScheduleToggle` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `isOpen` | `bool` | Whether enabled |
| `startHour` | `int` | Start hour |
| `startMin` | `int` | Start minute |
| `endHour` | `int` | End hour |
| `endMin` | `int` | End minute |

**`LedLevel` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `isOpen` | `bool` | Whether LED is enabled |
| `lcdLevel` | `int` | Brightness level: 1=dim, 2=soft, 3=bright |

---

#### 4.7.4 Video HID

| Method | Parameters | Returns | Description |
|--------|-----------|---------|-------------|
| `getVideoHid()` | None | `Future<int>` `hidOpen` value | Get HID mode |
| `setVideoHid(int hidOpen)` | `hidOpen`: 0=off, 1=iOS mode, 2=Android mode, 3=auto | `Future<void>` | Set HID mode |
| `createOrRemoveBond(int type, String mac)` | `type`: 1=pair, 2=unpair; `mac`: device MAC | `Future<bool>` pairing result | **Android only**; iOS no-op returns false |

---

#### 4.7.5 Wear Direction

| Method | Parameters | Returns | Description |
|--------|-----------|---------|-------------|
| `getRingWearDir()` | None | `Future<bool>` true=right hand, false=left hand | Get the wearing hand |
| `setRingWearHand(bool isRight)` | `isRight`: true=right hand | `Future<void>` | Set the wearing hand |

---

#### 4.7.6 Vibration

| Method | Parameters | Returns | Description |
|--------|-----------|---------|-------------|
| `getVibrationCount()` | None | `Future<VibrationConfig>` | Get vibration config |
| `setVibrationCount(VibrationConfig c)` | Config | `Future<void>` | Set vibration config |
| `getAlarmVibrationDuration()` | None | `Future<int>` | Alarm vibration duration, in seconds |
| `setAlarmVibrationDuration(int duration)` | `duration`: duration in seconds | `Future<void>` | Set the alarm vibration duration |

**`VibrationConfig` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `count` | `int` | Vibration count |
| `level` | `int` | Vibration intensity level |

---

### 4.8 Data Sync

| Method / Stream | Parameters | Returns | Description |
|----------------|-----------|---------|-------------|
| `syncAllHealthData()` | None | `Future<void>` | Start full health data sync |
| `removeHealthDataCallback()` | None | `Future<void>` | Remove sync callback |
| `onSyncProgress` | — | `Stream<double>` 0–100 | Sync progress |
| `onSyncResult` | — | `Stream<SyncResult>` | Synchronized data |
| `onSyncFinish` | — | `Stream<void>` | Sync complete |
| `onSyncError` | — | `Stream<Map>` payload: `{code}` | Sync error |

**`SyncResult` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `type` | `String` | Data type; see the table below |
| `data` | `List<Map<String, dynamic>>` | Detailed records for that type |

**`type` values and data item fields:**

| type | data item typical fields | Description |
|------|--------------------------|-------------|
| `step` | `time`, `date`, `totalSteps`, `totalCalorie`, `totalDistance`, `items[{index,steps,calorie,distance}]` | Steps |
| `sleep` | `time`, `date`, `duration`, `beginTime`, `endTime`, `items[{len,sleepType}]` | Sleep |
| `hr` | `time`, `date`, `items[{time,hr}]` | Heart rate |
| `bo` | `time`, `date`, `items[{time,bloodOxy}]` | Blood oxygen |
| `bp` | `time`, `date`, `items[{time,systolic,diastolic}]` | Blood pressure |
| `hrv` | `time`, `date`, `items[{time,hrv}]` | HRV |
| `pressure` | `time`, `date`, `items[{time,pressure}]` | Stress |
| `bloodSugar` | `time`, `date`, `items[{time,bloodSugar}]` | Blood sugar |
| `temp` | `time`, `date`, `items[{time,temp}]` | Body temperature |
| `muslimCount` | `time`, `date`, `totalCount`, `items[{time,count}]` | Prayer bead count |

---

### 4.9 OTA Upgrade

| Method / Stream | Parameters | Returns | Description |
|----------------|-----------|---------|-------------|
| `ringOta(String path)` | `path`: local firmware file path | `Future<void>` | Start OTA |
| `onOtaProgress` | — | `Stream<double>` 0.0–1.0 | OTA progress |
| `onOtaFinish` | — | `Stream<OtaResult>` | OTA complete |

**`OtaResult` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `success` | `bool` | Whether succeeded |
| `code` | `int?` | Error code (only on failure) |

---

### 4.10 Unbind

| Method | Parameters | Returns | Description |
|--------|-----------|---------|-------------|
| `unbind()` | None | `Future<void>` | Unbind device (Android sends unbind command; iOS clears bind state + disconnects) |

---

### 4.11 Message Push / Notification Switch

| Method | Parameters | Returns | Platform | Description |
|--------|-----------|---------|----------|-------------|
| `pushMessage(Map<String, dynamic> msg)` | See below | `Future<void>` | **Android** | Push a message to the device display; iOS no-op |
| `setNotificationSwitch(Map<String, dynamic> switches)` | See below | `Future<void>` | **iOS** | Set ANCS notification forwarding switches; Android no-op |
| `getNotificationSwitch()` | None | `Future<Map<String, dynamic>>` | **iOS** | Get notification switch state; Android returns `{}` |

**`pushMessage` parameter Map:**

| key | Type | Required | Description |
|-----|------|----------|-------------|
| `appId` | `String` | ✓ | App identifier |
| `title` | `String` | ✓ | Message title |
| `content` | `String` | ✓ | Message content |
| `msgType` | `int` | Optional | Message type |
| `timeMill` | `int` | Optional | Timestamp (milliseconds) |

**`setNotificationSwitch` parameter Map (key = switch name, value = bool):**

| key | Description | key | Description |
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
| `isOther` | Other | | |

---

## 5. Error Handling

All request/response methods throw `RwfitException` on failure:

```dart
try {
  await ring.getPower();
} on RwfitException catch (e) {
  print('Error code: ${e.code}, message: ${e.message}');
}
```

`code == 0` means success (consumed internally, never thrown); `code != 0` always throws.

---

## 6. Key Constraints

| Constraint | Description |
|------------|-------------|
| **Ready signal** | After connecting, you **must wait for `onFunctionMenu`** before sending commands; `connected` fires before ready |
| **Real-time measurement mutex** | Only one type at a time; call `stopRealtimeMeasure(...)` before switching |
| **Alarm full replacement** | Even changing one alarm requires `getAlarm → copyWith → setAlarm` with full list |
| **Capability gating is app-side** | Read `FunctionMenu.raw` to show, hide, or disable buttons; the plugin does not gate for you |
| **Android 12+ permissions** | `BLUETOOTH_SCAN` and `BLUETOOTH_CONNECT` must be requested at runtime |
| **iOS device identifier** | Use `uuid` for device association (not MAC); reconnect requires `iosSetBindedStatus(true)` first |
| **EventSink cleanup** | Cancel all Stream subscriptions on page `dispose` to avoid event duplication |
| **Platform-exclusive methods** | Return success (no-op) on the other platform; safe to call unconditionally |

---

## 7. Reconnection & Device Persistence

Recommended approach (see `example/lib/device_store.dart`):

1. When the connection is ready (`onFunctionMenu`): save `{name, mac, uuid}` to local storage and call `iosSetBindedStatus(true)`
2. On the next launch: load the saved device and call `reconnect(savedDevice)`
3. When switching devices: call `iosSetBindedStatus(false)` and clear local storage before entering the scan page
4. On disconnect: only call `disconnect()`; do not clear storage, so reconnection remains available

```dart
// Reconnect
final saved = await DeviceStore.load();
if (saved != null) await ring.reconnect(saved);
```

---

## 8. Full Usage Example

```dart
import 'package:rwfit_ble/rwfit_ble.dart';

final ring = RwfitBle.instance;

// Initialize
await ring.init();

// Scan
ring.onScanResult.listen((d) => print('${d.name} ${d.mac}'));
await ring.startScan();

// Connect and wait until the device is ready
ring.onFunctionMenu.listen((menu) async {
  // Now you can start sending commands
  final power = await ring.getPower();
  print('Battery: $power%');

  // Timed heart rate config
  final hr = await ring.getTimedHeartRate();
  await ring.setTimedHeartRate(hr.copyWith(isOpen: true, duration: 30));

  // Real-time heart rate
  ring.onRealtimeData.listen((d) {
    if (d.type == HealthType.hr) print('Heart rate: ${d.value}');
  });
  await ring.startRealtimeMeasure(RealtimeMetric.hr);
});
await ring.connect(device);
```

---

## 9. FAQ

| Issue | Solution |
|-------|----------|
| Connected but calls don't respond | Commands were sent before `onFunctionMenu`; wait for the ready signal |
| Can iOS use simulator? | **No iOS simulator support; use a real device only**. The simulator has no Bluetooth support, and simulator architectures are excluded, so it will not compile on Apple Silicon Macs |
| Android 12 scan fails | Runtime `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT` permissions are missing |
| `minSdkVersion` conflict | App's `minSdk` must be ≥ 26 |
| `Could not find com.rwfit:blesdk-rwfit:1.0` | **Not a cache or download issue**: the app has not registered the plugin's bundled native SDK repo. Add `maven { url = uri("${project(":rwfit_ble").projectDir}/repo") }` to your app's `android/build.gradle.kts`. See [2.1 Android](#21-android). Repeated `flutter clean` or pub-cache cleanup will not help |
| iOS "Module not found" | Verify `pod install` succeeded, then `flutter clean` and rebuild |
