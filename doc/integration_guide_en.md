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
      ref: v0.0.3   # Pin version; change this when upgrading
```

```bash
flutter pub get          # After changing ref: flutter pub upgrade rwfit_ble
```

> The first iOS build automatically runs `pod install` (no custom native host setup is required).
>
> ⚠️ **Android required reading**: a successful `pub get` does not guarantee the app can build. Android also needs the plugin's bundled native SDK repository registered in the app's `android/build.gradle.kts`; otherwise, you'll get `Could not find com.rwfit:blesdk-rwfit:2.260724`. See [2.1 Android](#21-android).

---

## 2. Platform Configuration

### 2.1 Android

`android/app/build.gradle.kts`: `minSdk = 26`

#### Required: Register the Plugin's Bundled Native SDK Repository ⚠️

The plugin bundles the RW ring native SDK AAR (`com.rwfit:blesdk-rwfit`) in its `android/repo` directory. **Gradle resolves `:app`'s transitive dependencies using the app's own repository list; repositories declared inside the plugin do not propagate**. You must register the plugin's `repo` directory as a local Maven repository on the **app side**; otherwise, the build fails with:

```
Could not find com.rwfit:blesdk-rwfit:2.260724.
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
| `startScan()` | None | `Future<void>` | Start scanning supported devices; ends automatically after 10 seconds |
| `stopScan()` | None | `Future<void>` | Stop scanning |
| `onScanResult` | — | `Stream<BleDevice>` | Fires when a device is discovered |
| `onScanFinish` | — | `Stream<void>` | Fires when scanning ends |

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
| `uuid` | `String?` | Optional device identifier |
| `reason` | `String?` | Only present on `failed`; Android returns the native `RingBleError` enum name, while iOS always returns `"unknown"` because its native callback has no error parameter |

**`FunctionMenu` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `name` | `String` | Device name |
| `mac` | `String` | MAC |
| `uuid` | `String?` | iOS only |
| `raw` | `Map<String, dynamic>` | supportMenu capability map; the app uses this to show, hide, or disable UI |

`onFunctionMenu.raw` and `getFunctionList()['supportMenu']` use the same normalized keys on both platforms:

- Integer values: `pushMsgSwitchValue`, `pushMsgSwitchValue2`, `activityDataInterval`.
- Boolean values: `isPushMsgEnableSwitch`, `isAlarm`, `isBrightScreenSleepTime`, `isBrightScreenTime`, `isSupportWorkout`, `isRememberSwitch`, `isSupportHrReminder`, `isSupportBoReminder`, `isSupportMotoVibrationLevel`, `isSupportAlarmVibrationDuration`, `isSupportVibrationInterval`, `isStep`, `isHr`, `isBloodPress`, `isSleep`, `isBloodOxy`, `isHrv`, `isPressure`, `isBloodSugar`, `isMuslimCountData`, `isBodyTemp`, `isSupportMuslimTimeDisplayMode`, `isSupportSensorRawPPG`, `isSupportPPGMonitoring`, `isSupportTemperatureMonitoring`, `isSupportCountReminder`, `isSupportSensorRawACC`, `isSupportSensorRawPPGRed`, `isSupportSensorRawIR`, `isSupportSensorRawSleep`, `isSupportFallDetect`, `isSupportRecording`, `isFindDevice`, `isTakePhoto`, `isLedLight`, `isWearDirection`, `isVideoHid`, `isVideoHidBook`, `isVideoHidMusic`, `isRaiseBrightScreen`, `isPowerOff`, `isFactoryReset`, and `isPushMessage`.

`FunctionMenu.supportsWorkout` is the typed workout-capability shortcut.
`activityDataInterval` is normalized to 60 minutes when the value is not
configured.
`isBodyTemp` indicates support for body-temperature history data, while
`isSupportTemperatureMonitoring` indicates support for timed temperature
monitoring. Treat them as separate capabilities.

---

### 4.4 Device Info

| Method | Parameters | Returns | Description |
|--------|-----------|---------|-------------|
| `getPower()` | None | `Future<int>` | Battery percentage, 0–100 |
| `getFirmwareVersion()` | None | `Future<FirmwareInfo>` | Firmware version info |
| `setUserInfo(UserInfo info)` | `UserInfo` object | `Future<void>` | Set user biometrics |
| `setTimeFormat(int format)` | `format`: 0=24-hour, 1=12-hour | `Future<void>` | Set the time display format; only effective on devices with a time display |
| `getFunctionList()` | None | `Future<Map<String, dynamic>>` | Get device supported features |

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

### 4.5 Timed Health Monitoring (7 All-Day Types + PPG)

Seven all-day health-monitoring types and timed PPG monitoring share
`TimedConfig`. This section lists the seven all-day APIs plus PPG; the
raw-sensor details for PPG are covered in
[4.13 Raw Sensor Data](#413-raw-sensor-data).

| Method | Description |
|--------|-------------|
| `getTimedHeartRate()` / `setTimedHeartRate(TimedConfig c)` | All-day heart rate monitoring |
| `getTimedBloodOxygen()` / `setTimedBloodOxygen(TimedConfig c)` | All-day blood oxygen monitoring |
| `getTimedHRV()` / `setTimedHRV(TimedConfig c)` | All-day HRV monitoring |
| `getTimedStress()` / `setTimedStress(TimedConfig c)` | All-day stress monitoring |
| `getTimedBloodSugar()` / `setTimedBloodSugar(TimedConfig c)` | All-day blood sugar monitoring |
| `getTimedBloodPressure()` / `setTimedBloodPressure(TimedConfig c)` | All-day blood pressure monitoring |
| `getTimedBodyTemperature()` / `setTimedBodyTemperature(TimedConfig c)` | All-day body-temperature monitoring |
| `getTimedPPG()` / `setTimedPPG(TimedConfig c)` | Timed PPG monitoring |

Each get method returns `Future<TimedConfig>`. Each set method accepts `TimedConfig` and returns `Future<void>`.
The monitoring window is fixed to `00:00–23:59`; the bridge normalizes both input and output to this all-day window.
Heart-rate and body-temperature intervals support 30 or 60 minutes. Blood oxygen, HRV, stress, blood sugar, and blood pressure use 60 minutes. For PPG, read the current device config before changing the switch.

**`TimedConfig` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `isOpen` | `bool` | Whether enabled |
| `duration` | `int` | Measurement interval (minutes), default 60 |
| `startHour` | `int` | Fixed to 0 |
| `startMin` | `int` | Fixed to 0 |
| `endHour` | `int` | Fixed to 23 |
| `endMin` | `int` | Fixed to 59 |

`TimedConfig` supports `copyWith(...)` for modifying the switch or interval before sending the config back. Custom time fields are ignored and normalized by the bridge.

---

### 4.6 Real-Time Measurement

| Method / Stream | Parameters | Returns | Description |
|----------------|-----------|---------|-------------|
| `startRealtimeMeasure(RealtimeMetric m)` | `m`: measurement type enum | `Future<void>` | Start real-time measurement |
| `stopRealtimeMeasure(RealtimeMetric m)` | `m`: measurement type enum | `Future<void>` | Stop real-time measurement |
| `onRealtimeData` | — | `Stream<RealtimeData>` | Real-time data callback |
| `onRealtimeMeasureComplete` | — | `Stream<void>` | Single measurement completion callback |

> ⚠️ **Mutual exclusion**: Only one measurement type can be active at a time. You must stop the current type before starting another.

A successful `startRealtimeMeasure()` only means that the device accepted the
start command. Listen to `onRealtimeMeasureComplete` before starting; an event
indicates that the current measurement has completed:

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
| `type` | `HealthType?` | Data type enum |
| `value` | `double` | Primary measurement value; blood sugar retains decimal precision, while integer-valued measurements are represented with `.0` |
| `diastolic` | `int?` | Diastolic pressure (only for blood pressure) |
| `timestampSec` | `int` | Measurement timestamp in Unix seconds, normalized on Android and iOS |
| `timestampMs` | `int` | **Deprecated compatibility getter** equal to `timestampSec * 1000`; do not use in new code |

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

### 4.7 Multi-Sport Workout

Enable this feature only when `FunctionMenu.supportsWorkout == true`. Query the device state before starting a new workout to avoid replacing an active workout. Disconnecting or closing the app does not stop a workout on the device. A workout must exceed two minutes before the device saves a report.

| Method / Stream | Parameters | Returns | Description |
|----------------|------------|---------|-------------|
| `getWorkoutState()` | None | `Future<WorkoutState>` | Query the current sport type and control state |
| `controlWorkout(int sportType, WorkoutControlType type)` | `sportType`: 7–161; `type`: start/resume/pause/end | `Future<void>` | Control the workout state; throws `RwfitException` on failure |
| `setWorkoutRealtimeEnabled(bool enabled)` | Enable/disable live data | `Future<void>` | Enable when entering the workout page and disable when leaving |
| `onWorkoutRealtimeData` | — | `Stream<WorkoutRealtimeData>` | Live workout statistics |
| `getWorkoutReports()` | None | `Future<List<WorkoutReport>>` | Sync saved workout reports |

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

// Pause, resume, or end the workout in response to user actions.
await ring.controlWorkout(sportType, WorkoutControlType.end);
await ring.setWorkoutRealtimeEnabled(false);
await sub.cancel();

final reports = await ring.getWorkoutReports();
```

**`WorkoutState` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `sportType` | `int` | Current sport type |
| `controlType` | `WorkoutControlType` | Current control state |
| `isRunning` | `bool` | Whether a workout is active |

**`WorkoutControlType` enum:**

| Value | int value | Description |
|-------|-----------|-------------|
| `WorkoutControlType.start` | `0x01` | Start |
| `WorkoutControlType.resume` | `0x02` | Resume |
| `WorkoutControlType.pause` | `0x03` | Pause |
| `WorkoutControlType.end` | `0x04` | End |
| `WorkoutControlType.unknown` | `-1` | Unrecognized state; must not be sent as a control parameter |

**`WorkoutRealtimeData` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `duration` | `int` | Workout duration in seconds |
| `steps` | `int` | Step count |
| `distance` | `int` | Distance in meters |
| `calorie` | `int` | Calories in cal |
| `heartRate` | `int` | Live heart rate |
| `dataType` | `WorkoutDataType` | Always `appWorkoutData` in the Flutter contract |
| `rawDataType` | `int` | Always `0x0223` in the Flutter contract |

**`WorkoutDataType` enum:**

| Value | int value | Description |
|-------|-----------|-------------|
| `WorkoutDataType.appWorkoutData` | `0x0223` | Live workout data |
| `WorkoutDataType.enterOrExitWorkout` | `0x0274` | Compatibility enum; current Flutter events do not return it |
| `WorkoutDataType.unknown` | `-1` | Unrecognized type |

**`WorkoutReport` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `startTime` / `endTime` | `int` | Start/end Unix timestamp in seconds |
| `date` | `String` | Date in `yyyyMMdd` format |
| `sportType` | `int` | Sport type |
| `duration` | `int` | Workout duration in seconds |
| `step` / `distance` / `calorie` | `int` | Steps / distance in meters / calories in cal |
| `height` / `pressure` | `int` | Height / air pressure |
| `cadence` / `speed` / `pace` | `int` / `double` / `int` | Cadence / speed / pace |
| `averageHeartRate` | `int` | Average heart rate |
| `maxHeartRate` / `minHeartRate` | `int` | Maximum/minimum heart rate |
| `maxCadence` / `minCadence` | `int` | Maximum/minimum cadence |
| `maxPace` / `minPace` | `int` | Maximum/minimum pace |
| `heartRateCount` | `int` | Number of heart-rate samples |
| `viewType` | `int` | Workout data display type |
| `heartRateItems` | `List<WorkoutValueItem>` | Heart-rate samples |
| `pacePerKmItems` | `List<WorkoutValueItem>` | Per-kilometer pace samples |

`WorkoutValueItem` contains two `int` fields: `index` and `value`.

---

### 4.8 Device Control

#### 4.8.1 Basic Controls

| Method | Parameters | Returns | Description |
|--------|-----------|---------|-------------|
| `findDevice()` | None | `Future<void>` | Find device; the LED or screen response depends on the device model |
| `powerOff()` | None | `Future<void>` | Power off |
| `factoryReset()` | None | `Future<void>` | Factory reset |
| `controlPhoto(int state)` | `state`: 1=enter photo mode, 0=exit | `Future<void>` | Photo control |
| `onTouchEvent` | — | `Stream<TouchEvent>` | Touch/fall/photo/music control events |
| `startHeartRateCalibration()` | None | `Future<void>` | Start heart-rate calibration; the bridge fixes the test mode to `0x15` |
| `onHeartRateCalibration` | — | `Stream<HeartRateCalibrationResult>` | Calibration progress and result |
| `getFallDetect()` / `setFallDetect(bool enabled)` | Fall-detection switch | `Future<bool>` / `Future<void>` | Get/set fall detection |
| `getCountReminderInterval()` / `setCountReminderInterval(int minutes)` | 0/30/60/90/120 minutes | `Future<int>` / `Future<void>` | Get/set count reminder interval; 0 disables reminders |
| `controlPhone(CallControlAction action)` | `answer` or `reject` | `Future<void>` | Android call control; iOS no-op |
| `onCallControl` | — | `Stream<CallControlEvent>` | Device-originated answer/reject action on Android |

After photo mode is enabled, a device-originated value of `2` requests the app
to take a picture. The bridge converts it to an `onTouchEvent` event whose
action is `TouchAction.cameraTakePicture`; applications do not parse the raw
value.

**`TouchEvent` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `action` | `TouchAction` enum | Action type |
| `rawAction` | `String` | Raw action string |
| `keyType` | `int` | 1=touch key, 2=fall; 0 for photo/music events |
| `touchType` | `int` | 1=single, 2=double, 3=triple, 4=long press, 5=swing; 0 for photo/music events |

**`TouchAction` enum values:** `singleTap`, `doubleTap`, `tripleTap`, `longPress`, `swing`, `fallDetected`, `cameraTakePicture`, `musicPlay`, `musicPause`, `musicPrev`, `musicNext`, `musicVolumeUp`, `musicVolumeDown`, `unknown`

**`HeartRateCalibrationResult` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `testMode` | `int` | Test mode; heart-rate calibration uses `0x15` |
| `result` | `int` | 0=calibrating; a non-zero value is the completed calibration result |
| `isCalibrating` | `bool` | `result == 0` |
| `isCompleted` | `bool` | `result != 0` |

**`CallControlEvent` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `action` | `CallControlAction?` | `answer` or `reject`; null for an unknown value |
| `rawValue` | `int` | Raw Android SDK callback value: 1=answer, 2=reject |

On iOS, calls are handled by the system: `controlPhone` is a no-op and
`onCallControl` does not emit events.

---

#### 4.8.2 Alarms

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
| `repeats` | `List<int>` | Length 7, Sunday–Saturday toggles (index 0=Sunday; 1=on, 0=off) |

Supports `copyWith(...)` for modifying individual fields.

---

#### 4.8.3 Screen Settings

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

#### 4.8.4 Video HID

> [!IMPORTANT]
> Android video control requires system Bluetooth HID pairing. A BLE connection
> or `setVideoHid()` does not perform this pairing. Call
> `createOrRemoveBond(1, mac)` to pair, or pass `type=2` to unpair.

| Method | Parameters | Returns | Description |
|--------|-----------|---------|-------------|
| `getVideoHid()` | None | `Future<int>` `hidOpen` value | Get HID mode |
| `setVideoHid(int hidOpen)` | `hidOpen`: 0=off, 1=video, 2=book, 3=music | `Future<void>` | Set HID mode |
| `createOrRemoveBond(int type, String mac)` | `type`: 1=pair, 2=unpair; `mac`: device MAC | `Future<bool>` whether the operation was initiated | **Android only**, for video HID system pairing; iOS no-op returns `false` |

---

#### 4.8.5 Music Control

On Android, connect the device and call `setVideoHid(3)` to select Music mode.
After the setting succeeds, move the ring upward or downward to control the
previous or next track; no additional event listener is required. Music
control on iOS is handled by the system.

---

#### 4.8.6 Wear Direction

| Method | Parameters | Returns | Description |
|--------|-----------|---------|-------------|
| `getRingWearDir()` | None | `Future<bool>` true=right hand, false=left hand | Get the wearing hand |
| `setRingWearHand(bool isRight)` | `isRight`: true=right hand | `Future<void>` | Set the wearing hand |

---

#### 4.8.7 Vibration

| Method | Parameters | Returns | Description |
|--------|-----------|---------|-------------|
| `getVibrationCount()` | None | `Future<VibrationConfig>` | Get vibration config |
| `setVibrationCount(VibrationConfig c)` | Config | `Future<void>` | Set vibration config |
| `getAlarmVibrationDuration()` | None | `Future<int>` | Alarm vibration count (0–6); default 2, and 0 means no vibration |
| `setAlarmVibrationDuration(int duration)` | `duration`: vibration count (0–6) | `Future<void>` | Set the alarm vibration count; default 2, and 0 means no vibration |
| `getVibrationInterval()` | None | `Future<int>` | Interval between vibrations, in ms |
| `setVibrationInterval(int intervalMs)` | `intervalMs`: 100–1000 | `Future<void>` | Set the vibration interval |

**`VibrationConfig` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `count` | `int` | Vibration count: 0–6; default 2, and 0 means no vibration |
| `level` | `int` | Vibration level: 0=off, 1=low, 2=medium, 3=high |

---

#### 4.8.8 Muslim Count and Health Alerts

Use the Muslim count APIs only when the capability property
`isRememberSwitch == true`.

| Method / Stream | Parameters | Returns | Description |
|-----------------|------------|---------|-------------|
| `getMuslimCountEnabled()` | None | `Future<bool>` | Get the device Muslim count switch |
| `setMuslimCountEnabled(bool enabled)` | Enable state | `Future<void>` | Set the device Muslim count switch |
| `getHeartRateAlert()` | None | `Future<HeartRateAlertConfig>` | Get heart-rate alert settings |
| `setHeartRateAlert(HeartRateAlertConfig config)` | Alert config | `Future<void>` | Set high/low heart-rate alerts |
| `getBloodOxygenAlert()` | None | `Future<BloodOxygenAlertConfig>` | Get blood-oxygen alert settings |
| `setBloodOxygenAlert(BloodOxygenAlertConfig config)` | Alert config | `Future<void>` | Set the low blood-oxygen alert |
| `onHealthAlert` | — | `Stream<HealthAlertEvent>` | Device-originated health alerts |

`HeartRateAlertConfig` contains `isOpen`, `highThreshold` (typically 160 bpm
by default), and nullable `lowThreshold`. A null low threshold means that the
device does not support a low-heart-rate alert. `BloodOxygenAlertConfig`
contains `isOpen` and the semantically normalized `lowThreshold`; the protocol
default is 94%.

`HealthAlertEvent.type` is `highHeartRate`, `lowBloodOxygen`,
`lowHeartRate`, or `unknown`; `value` is the measurement that triggered the
alert.

---

### 4.9 Data Sync

| Method / Stream | Parameters | Returns | Description |
|----------------|-----------|---------|-------------|
| `syncAllHealthData()` | None | `Future<void>` | Start full health data sync |
| `removeHealthDataCallback()` | None | `Future<void>` | Remove sync callback |
| `onSyncProgress` | — | `Stream<double>`, value `100` | Sync-complete marker, immediately followed by `onSyncFinish` |
| `onSyncResult` | — | `Stream<SyncResult>` | Synchronized data |
| `onSyncFinish` | — | `Stream<void>` | Sync complete |
| `onSyncError` | — | `Stream<Map>` payload: `{code}` | Sync error |

> [!IMPORTANT]
> `time`, `beginTime`, `endTime`, and each detail item's `time` in this
> section are Unix timestamps in **seconds**. Multiply by `1000` when creating
> a Dart `DateTime` from milliseconds.

**`SyncResult` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `type` | `String` | Data type; see the table below |
| `data` | `List<Map<String, dynamic>>` | Detailed records for that type |

**`type` values and data item fields:**

| type | data item typical fields | Description |
|------|--------------------------|-------------|
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

**Measurement values and units:**

Except for step, sleep, and Muslim count records, measurement types are grouped
by date and contain `time`, `date`, and `items`.

| Data | Value fields | Unit / conversion |
|------|--------------|-------------------|
| Heart rate | `hr` | bpm |
| Blood pressure | `systolic`, `diastolic` | mmHg; systolic and diastolic pressure |
| Blood oxygen | `bloodOxy` | % |
| Body temperature | `temp` | Actual temperature is `temp / 10` °C; for example, 365 means 36.5 °C |
| Stress | `pressure` | Device stress value; unitless |
| Blood sugar | `bloodSugar` | Actual blood-sugar value as a `double`, retaining decimal precision |
| HRV | `hrv` | ms |

**Step data:**

Each `step` date object contains `time` (Unix seconds), `date` (`yyyyMMdd`),
`totalSteps`, `totalCalorie` (cal), `totalDistance` (m),
`activityDataInterval` (minutes), and `items`. Each item contains
`{time, index, steps, calorie, distance}`, where `time` is also in Unix seconds.

**Historical sleep data:**

Each `sleep` date object contains `time`, `date`, `duration` (minutes),
`beginTime`, `endTime`, and `items[{len,sleepType}]`; `len` is in minutes.
Historical `sleepType` values are 0=awake, 1=light sleep, 2=deep sleep, and
3=REM.

> These historical sleep values are different from the raw real-time sleep
> modes in [4.13 Raw Sensor Data](#413-raw-sensor-data): 1=deep, 2=light,
> 3=awake, and 4=REM. Do not mix the two protocols.

---

### 4.10 OTA Upgrade

| Method / Stream | Parameters | Returns | Description |
|----------------|-----------|---------|-------------|
| `ringOta(String path)` | `path`: local firmware file path | `Future<void>` | Start OTA |
| `onOtaProgress` | — | `Stream<double>` 0.0–1.0 | OTA progress |
| `onOtaFinish` | — | `Stream<OtaResult>` | OTA complete |

The Android bridge normalizes OTA progress to `0.0–1.0`. The current Android
SDK has been verified to report `0.0–1.0`; conversion from `0–100` remains only
a defensive compatibility branch and has not been observed with this SDK
version.

**`OtaResult` fields:**

| Field | Type | Description |
|-------|------|-------------|
| `success` | `bool` | Whether succeeded |
| `code` | `int?` | Error code (only on failure) |

---

### 4.11 Unbind

| Method | Parameters | Returns | Description |
|--------|-----------|---------|-------------|
| `unbind()` | None | `Future<void>` | Unbind device (Android sends unbind command; iOS clears bind state + disconnects) |

---

### 4.12 Message Push / Notification Switch

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
| `isJLBand` | Band | `isJLBetween` | Between |
| `isJLNavercafe` | Naver Cafe | `isJLNetflix` | Netflix |
| `isMax` | MAX | `isVkim` | VK Messenger |
| `isOther` | Other | | |

---

### 4.13 Raw Sensor Data

| Method / Stream | Parameters | Returns | Description |
|-----------------|------------|---------|-------------|
| `getTimedPPG()` / `setTimedPPG(TimedConfig c)` | Timed config | `Future<TimedConfig>` / `Future<void>` | Get/set timed PPG monitoring |
| `controlSensorRaw(bool enabled, SensorRawSelection selection)` | Enable state and a valid sensor combination | `Future<void>` | Start/stop raw sensor collection |
| `getSensorRawHistory()` | None | `Future<List<SensorRawPacket>>` | Synchronize saved raw packets |
| `onSensorRawData` | — | `Stream<SensorRawPacket>` | Device-originated raw/sleep packets |
| `onSensorRawStopped` | — | `Stream<SensorRawStoppedEvent>` | Device stopped collection; reason 0 means unspecified |

> [!IMPORTANT]
> The device retains only the latest timed PPG raw dataset. A subsequent
> measurement may overwrite data that has not been synchronized. When
> `onSensorRawStopped` reports that a measurement has finished, call
> `getSensorRawHistory()` promptly and persist the returned data.

`SensorRawSelection` provides the valid combinations: `acc(1)`,
`ppgGreen(2)`, `ppgGreenAndAcc(3)`, `ppgRed(4)`, `ppgRedAndAcc(5)`,
`ppgGreenAndIr(10)`, `ppgGreenAccAndIr(11)`, `ppgRedAndIr(12)`, and
`ppgRedAccAndIr(13)`. Green and red PPG cannot be combined, and IR cannot
be collected alone.

`SensorRawPacket` exposes `type`, `rawType`, optional `sequence` and
`timestampSec`, plus `ppg`, `acc`, `ppgRed`, `ir`, and `sleep` arrays.
`SensorRawDataType` values are `timestamp(0)`, `ppg(1)`, `acc(2)`,
`ppgRed(3)`, `ir(4)`, `sleep(5)`, and `unknown(-1)`.

Raw sensor data can be sampled at up to 100 Hz, and the device typically
stores up to approximately one minute of test data.

Sleep raw packets are pushed automatically. Their mode values are 17=start,
34=end, 1=deep, 2=light, 3=awake, and 4=REM. These values are distinct from
historical sleep `sleepType` values.

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
| **Platform-exclusive methods** | Usually no-op on the inapplicable platform; a call returning without error does not mean the feature was executed, so application logic must branch by platform |

---

## 7. Reconnection & Device Persistence

Recommended approach (see `example/lib/device_store.dart`):

1. When the connection is ready (`onFunctionMenu`): save `{name, mac, uuid}` to local storage and call `iosSetBindedStatus(true)`
2. On the next launch: load the saved device and call `reconnect(savedDevice)`
3. When switching devices: call `iosSetBindedStatus(false)` and clear local storage before entering the scan page
4. On disconnect: only call `disconnect()`; do not clear storage, so reconnection remains available

```dart
import 'dart:io';

// Reconnect
final saved = await DeviceStore.load();
if (saved != null) {
  if (Platform.isIOS) {
    await ring.iosSetBindedStatus(true);
  }
  await ring.reconnect(saved);
}
```

---

## 8. Full Usage Example

```dart
import 'dart:async';

import 'package:rwfit_ble/rwfit_ble.dart';

Future<void> connectAndRead() async {
  final ring = RwfitBle.instance;
  await ring.init();

  // Select the first scan result for brevity. A production app should let the
  // user choose a device.
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

  // All-day heart rate supports only 30- or 60-minute intervals.
  final hr = await ring.getTimedHeartRate();
  await ring.setTimedHeartRate(hr.copyWith(isOpen: true, duration: 30));

  final realtimeSub = ring.onRealtimeData.listen((d) {
    if (d.type == HealthType.hr) print('Heart rate: ${d.value}');
  });
  final completeSub = ring.onRealtimeMeasureComplete.listen((_) {
    print('Measurement complete');
  });
  await ring.startRealtimeMeasure(RealtimeMetric.hr);

  // Release resources when the measurement or page lifecycle ends.
  await ring.stopRealtimeMeasure(RealtimeMetric.hr);
  await realtimeSub.cancel();
  await completeSub.cancel();
  await readySub.cancel();
}
```

---

## Flutter Plugin Revision History

**v0.0.3_20260731** (2026.07.31)

- Improved the Android/iOS bridges and aligned capability keys, events, and error semantics
- Added timed monitoring, health alerts, device controls, and raw sensor data features
- Added real-time measurement completion events and refined health sync and connection-state handling
- Added capability-based gating and related feature pages to the demo
- Documented timed PPG single-dataset retention and prompt synchronization requirements

**v0.0.2_20260729** (2026.07.29)

- Added multi-sport state queries, workout controls, live workout data, and workout report APIs
- Added workout type selection and live workout example pages
- Standardized real-time health timestamps as Unix seconds with `timestampSec`, while retaining the compatible `timestampMs` getter

---

## Contact / Technical Support

developer@dhouse88.com
