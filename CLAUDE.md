# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A Flutter plugin (`rwfit_ble`) bridging the proprietary RWFit smart-ring native BLE SDKs to Dart. It was ported from an older uni-app native plugin, so the native bridges are deliberately **Java + Objective-C** (not Kotlin/Swift), with method bodies lifted near-verbatim from the uni-app sources. Code comments and the internal design doc are in Chinese.

This public repo is consumed as a **git dependency pinned to a release tag** — the native SDK binaries (Android AAR in `android/repo/`, iOS `DHBleSDK.xcframework` in `ios/Frameworks/`) are committed to git.

## Commands

CI (`.github/workflows/ci.yml`) enforces formatting and analysis only — there are no native builds or device tests in CI:

```shell
flutter pub get
dart format --output=none --set-exit-if-changed .   # CI fails on unformatted code
flutter analyze
```

All tests live in the example app (parsing and i18n unit tests; no root-level `test/`):

```shell
cd example && flutter test                          # all tests
cd example && flutter test test/health_store_test.dart  # single file
cd example && flutter run                           # demo app (needs physical device for BLE)
```

## Architecture

Four layers, top-down:

1. **Dart facade** — `lib/rwfit_ble.dart`: `RwfitBle.instance` singleton, typed `Future`/`Stream` API. Typing happens ONLY here.
2. **Channel infra** — `lib/src/rwfit_channels.dart`: one MethodChannel `rwfit_ble/methods` + one EventChannel `rwfit_ble/events`. `callAsync()` resolves on `code == 0`, else throws `RwfitException`. The event channel is a single broadcast stream; native payloads carry an `event` field (`rwfit:*`, constants in `RwfitEvents`) that `onEvent()` filters on.
3. **Native bridges** — `android/src/main/java/com/rwfit/rwfit_ble/RwfitBlePlugin.java` (giant `switch` in `onMethodCall`) and `ios/rwfit_ble/Sources/rwfit_ble/RwfitBlePlugin.m` (mirroring `if/else` chain). Identical method names, arg shapes, and event payloads on both platforms — any divergence is a bridge bug. Platform-exclusive methods must no-op returning `code == 0` (e.g. `iOSSetBindedStatus` on Android, `pushMessage` on iOS).
4. **Proprietary SDKs** — Android `com.rwfit:blesdk-rwfit` resolved from the local maven repo `android/repo/` (declared in `android/build.gradle.kts`; a duplicate AAR sits in `android/libs/`); iOS vendored via the podspec. The SDK's Java package is `com.example.blesdk`. The upstream SDK distributions (docs, demo apps, release artifacts) live in the local sibling checkouts `../RW_Android_SDK` and `../RW_iOS_SDK` — consult their docs when the bridge contract is unclear, and take new AAR/xcframework builds from there.

Key rule: **no Pigeon, no codegen**. The native boundary intentionally speaks loose `{code, msg, ...}` Maps; stable structures get typed models (`lib/src/rwfit_models.dart`) while genuinely dynamic payloads (`SyncResult.data`, `FunctionMenu.raw`) stay `Map` as escape hatches.

### Native bridge contract (both platforms)

- Errors ride the **success channel** as `{code != 0, msg}` — never call `result.error()`/throw platform errors, or Dart gets `PlatformException` instead of `RwfitException`.
- All EventSink calls and replies must be posted to the main thread (Android `Reply` wrapper / `fireEvent`; iOS `fire:data:` on main queue).
- Android: every payload crossing the codec must pass `toCodecSafe()` (FastJSON `JSONObject`/`JSONArray` → `Map`/`List`).
- Callbacks reach Dart through `RWFitCallbackManager` (Android) and `DHBleConnectDelegate` + `NSNotificationCenter` observers (iOS), both funneling into the shared EventSink.

### Behavioral contract (from the native SDK docs — do not "fix" these)

- `connected` ≠ ready: business commands may only be sent after the `rwfit:functionMenu` event (the function table). Android auto-enables music control at that point; music events arrive as `rwfit:touchEvent` with `action: musicPlay` etc. — there is no separate music event.
- Realtime measurements are mutually exclusive — stop the current one before starting another.
- Alarms are full-replace: `getAlarm` → modify → `setAlarm` with the complete list.
- iOS identifies devices by `uuid` from scan results; `connectDevice` fails unless the device is in the current scan cache. Round-trip the whole `BleDevice`.
- `rwfit:syncProgress` is only ever 100 (completion marker); terminal sync state is `rwfit:syncFinish`/`rwfit:syncError`. Same shape for OTA: `ringOta(path)` returns when the transfer is *submitted*; final state only via `rwfit:otaFinish`.
- Enum values in `lib/src/rwfit_constants.dart` are frozen SDK wire values — never change them to fix a discrepancy; the two platforms' native SDK docs are the authority, and masking one platform's bug with an offset in the other is how regressions happen.

### Design principle: thin plugin

The plugin does no capability gating, no OTA state machine, no orchestration. Capability flags come from the function table; the consuming app decides. `example/lib/demo_controller.dart` (a `ChangeNotifier` owning all subscriptions) is the reference consumer pattern.

## Adding a method end-to-end

Check both native SDK docs → add the case in Android `onMethodCall` and iOS `handleMethodCall` (identical name + payload) → add the typed wrapper in `lib/rwfit_ble.dart` via `callAsync` (new events: constant in `RwfitEvents` + `fireEvent`/`fire:data:` on both platforms) → `dart format` + `flutter analyze` → update `doc/` guides and the example app.

## Release

Conventional commit prefixes (`feat:`, `fix:`, `docs:`, `chore:`, `release: vX.Y.Z`), releases are a `release:` commit + matching `vX.Y.Z` tag. The version lives in **five places that must stay in sync**:

1. `pubspec.yaml`
2. `android/build.gradle.kts` (`version =`)
3. `ios/rwfit_ble.podspec` (`s.version`)
4. `PLUGIN_VERSION` in `RwfitBlePlugin.java`
5. the hardcoded version string in `RwfitBlePlugin.m` (`getPluginVersion` returns `pluginVersion_sdkVersion`)

Also update the git-dep `ref:` example in `README.md`, and the native SDK version note there when the AAR/xcframework is replaced (new binaries come from the sibling SDK repos — see layer 4 above).

## Do not

- Never commit `internal-docs/` or add a `CHANGELOG.md` — both are internal-only material, kept out of this public repo deliberately (`.gitignore` covers `internal-docs/`; `internal-docs/RWFIT_Flutter插件开发文档.md` is the authoritative design/contract spec when present locally).
- Never rename channel methods, payload keys, or `rwfit:*` event names — they are a frozen contract inherited from the uni-app bridge.
- Customer-facing docs (EN/ZH integration guides) live in `doc/`; keep them updated with API changes.
