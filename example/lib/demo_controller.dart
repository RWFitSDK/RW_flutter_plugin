import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import 'device_store.dart';
import 'health_store.dart';
import 'support_menu.dart';

/// Example 应用的轻量状态层，集中维护绑定、连接和健康数据状态。
class DemoController extends ChangeNotifier {
  DemoController() {
    _subscribe();
    unawaited(_loadSavedState());
    unawaited(_loadVersions());
  }

  final RwfitBle ring = RwfitBle.instance;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final List<Completer<void>> _readyWaiters = [];
  final Set<String> _receivedSyncTypes = {};
  Completer<void>? _syncWaiter;

  BleDevice? device;
  DemoCapabilities capabilities = const DemoCapabilities.empty();
  ConnectState connectionState = ConnectState.disconnected;
  bool ready = false;
  bool loadingSavedState = true;
  bool syncing = false;
  double syncProgress = 0;
  int? powerLevel;
  FirmwareInfo? firmware;
  String? sdkVersion;
  String? pluginVersion;
  DateTime? lastSyncAt;
  String? lastError;
  Map<String, List<DemoHealthRecord>> healthRecords = {};
  final Map<String, DemoHealthRecord> _realtimeRecords = {};

  bool get connected => ready && connectionState == ConnectState.connected;

  String? get deviceId => device == null ? null : (device!.uuid ?? device!.mac);

  void _subscribe() {
    _subscriptions.add(
      ring.onConnectState.listen((event) {
        connectionState = event.state;
        if (event.state == ConnectState.disconnected ||
            event.state == ConnectState.failed) {
          ready = false;
          _realtimeRecords.clear();
          _failSyncWaiter(
            StateError(
              event.reason ??
                  (event.state == ConnectState.failed
                      ? 'Connection failed during sync'
                      : 'Device disconnected during sync'),
            ),
          );
        }
        if (event.state == ConnectState.failed) {
          lastError = event.reason;
          _completeReadyWaiters(
            StateError(event.reason ?? 'Connection failed'),
          );
        }
        notifyListeners();
      }),
    );
    _subscriptions.add(
      ring.onFunctionMenu.listen((menu) async {
        final connectedDevice = BleDevice(
          name: menu.name,
          mac: menu.mac,
          rssi: 0,
          uuid: menu.uuid,
        );
        final previousId = deviceId;
        device = connectedDevice;
        capabilities = DemoCapabilities(
          Map<String, dynamic>.unmodifiable(menu.raw),
        );
        connectionState = ConnectState.connected;
        ready = true;
        lastError = null;
        await DeviceStore.save(connectedDevice);
        await DeviceStore.saveCapabilities(menu.raw);
        await ring.iosSetBindedStatus(true);
        if (previousId != deviceId) {
          _realtimeRecords.clear();
          healthRecords = {};
          lastSyncAt = null;
          await DeviceStore.clearLastSyncAt();
        }
        _completeReadyWaiters();
        notifyListeners();
        unawaited(refreshDeviceInfo(silent: true));
      }),
    );
    _subscriptions.add(
      ring.onSyncResult.listen((result) {
        final parsed = DemoHealthStore.parseSyncResult(result);
        _appendHealthRecords(result.type, parsed);
        _receivedSyncTypes.add(result.type);
        final supportedCount = _supportedSyncTypeCount();
        final receivedCount = _receivedSyncTypes
            .where((type) => _syncTypes.contains(type))
            .length;
        syncProgress = supportedCount == 0
            ? 0.1
            : (receivedCount / supportedCount).clamp(0.08, 0.95);
        notifyListeners();
      }),
    );
    _subscriptions.add(
      ring.onSyncProgress.listen((progress) {
        if (syncing && progress >= 100) syncProgress = 0.98;
        notifyListeners();
      }),
    );
    _subscriptions.add(
      ring.onSyncFinish.listen((_) async {
        syncing = false;
        syncProgress = 1;
        lastSyncAt = DateTime.now();
        await DeviceStore.saveLastSyncAt(lastSyncAt!);
        final waiter = _syncWaiter;
        _syncWaiter = null;
        if (waiter != null && !waiter.isCompleted) waiter.complete();
        notifyListeners();
      }),
    );
    _subscriptions.add(
      ring.onSyncError.listen((error) {
        lastError = 'code=${error['code']}';
        _failSyncWaiter(StateError(lastError!));
        notifyListeners();
      }),
    );
    _subscriptions.add(
      ring.onRealtimeData.listen((data) {
        final record = DemoHealthStore.parseRealtime(data);
        if (record == null) return;
        _realtimeRecords[record.type] = record;
        notifyListeners();
      }),
    );
  }

  static const _syncTypes = <String>{
    HealthTypeId.step,
    HealthTypeId.sleep,
    HealthTypeId.heartRate,
    HealthTypeId.bloodOxygen,
    HealthTypeId.bloodPressure,
    HealthTypeId.hrv,
    HealthTypeId.pressure,
    HealthTypeId.bloodSugar,
    HealthTypeId.temperature,
    HealthTypeId.muslimCount,
  };

  Future<void> _loadSavedState() async {
    final savedDevice = await DeviceStore.load();
    final savedCapabilities = await DeviceStore.loadCapabilities();
    final savedLastSyncAt = await DeviceStore.loadLastSyncAt();
    if (!ready) {
      device = savedDevice;
      capabilities = DemoCapabilities(savedCapabilities);
      lastSyncAt = savedLastSyncAt;
      healthRecords = {};
    }
    loadingSavedState = false;
    notifyListeners();
  }

  Future<void> _loadVersions() async {
    try {
      final values = await Future.wait([
        ring.getSdkVersion(),
        ring.getPluginVersion(),
      ]);
      sdkVersion = values[0];
      pluginVersion = values[1];
      notifyListeners();
    } catch (_) {
      // 版本信息不影响设备连接和业务操作。
    }
  }

  List<DemoHealthRecord> recordsFor(String type) {
    final records = healthRecords[type] ?? const [];
    if (type != HealthTypeId.step && type != HealthTypeId.muslimCount) {
      return List.unmodifiable(records);
    }
    return List.unmodifiable(records.where((record) => !record.isDailySummary));
  }

  DemoHealthRecord? latestFor(String type) {
    final realtime = _realtimeRecords[type];
    if (realtime != null) return realtime;
    final records = healthRecords[type];
    if (records == null) return null;
    if (type == HealthTypeId.step || type == HealthTypeId.muslimCount) {
      for (final record in records) {
        if (record.isDailySummary) return record;
      }
    }
    return records.firstOrNull;
  }

  void _appendHealthRecords(String type, List<DemoHealthRecord> incoming) {
    final sorted = [...?healthRecords[type], ...incoming]
      ..sort((a, b) => b.measuredAtSec.compareTo(a.measuredAtSec));
    healthRecords = {...healthRecords, type: sorted};
  }

  int _supportedSyncTypeCount() {
    final keys = <String>[
      DemoCapabilityKey.step,
      DemoCapabilityKey.sleep,
      DemoCapabilityKey.heartRate,
      DemoCapabilityKey.bloodOxygen,
      DemoCapabilityKey.bloodPressure,
      DemoCapabilityKey.hrv,
      DemoCapabilityKey.pressure,
      DemoCapabilityKey.bloodSugar,
      DemoCapabilityKey.bodyTemperature,
      DemoCapabilityKey.muslimCountData,
    ];
    return keys.where(capabilities.has).length;
  }

  Future<void> reconnect() async {
    final savedDevice = device;
    if (savedDevice == null) throw StateError('No saved device');
    if (connected || await ring.isConnected()) {
      if (ready) return;
    }
    connectionState = ConnectState.connecting;
    lastError = null;
    notifyListeners();
    final waiter = Completer<void>();
    _readyWaiters.add(waiter);
    try {
      await ring.iosSetBindedStatus(true);
      await ring.reconnect(savedDevice);
      await waiter.future.timeout(const Duration(seconds: 20));
    } finally {
      _readyWaiters.remove(waiter);
    }
  }

  Future<void> disconnect() async {
    await ring.disconnect();
    ready = false;
    connectionState = ConnectState.disconnected;
    _realtimeRecords.clear();
    notifyListeners();
  }

  Future<void> unbind() async {
    await ring.unbind();
    await ring.iosSetBindedStatus(false);
    await DeviceStore.clear();
    device = null;
    capabilities = const DemoCapabilities.empty();
    healthRecords = {};
    _realtimeRecords.clear();
    firmware = null;
    powerLevel = null;
    ready = false;
    connectionState = ConnectState.disconnected;
    lastSyncAt = null;
    notifyListeners();
  }

  Future<void> syncAllHealthData() async {
    if (device == null) throw StateError('No bound device');
    if (syncing) {
      await _syncWaiter?.future;
      return;
    }
    if (!connected) await reconnect();
    syncing = true;
    syncProgress = 0.05;
    healthRecords = {};
    _receivedSyncTypes.clear();
    lastError = null;
    final waiter = Completer<void>();
    _syncWaiter = waiter;
    notifyListeners();
    try {
      await ring.syncAllHealthData();
      await waiter.future.timeout(const Duration(minutes: 3));
    } catch (_) {
      syncing = false;
      if (identical(_syncWaiter, waiter)) _syncWaiter = null;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> refreshDeviceInfo({bool silent = false}) async {
    if (!connected) {
      if (silent) return;
      throw StateError('Device is not connected');
    }
    try {
      final values = await Future.wait<Object>([
        ring.getPower(),
        ring.getFirmwareVersion(),
      ]);
      powerLevel = values[0] as int;
      firmware = values[1] as FirmwareInfo;
      notifyListeners();
    } catch (_) {
      if (!silent) rethrow;
    }
  }

  void _completeReadyWaiters([Object? error]) {
    for (final waiter in List<Completer<void>>.of(_readyWaiters)) {
      if (waiter.isCompleted) continue;
      if (error == null) {
        waiter.complete();
      } else {
        waiter.completeError(error);
      }
    }
  }

  void _failSyncWaiter(Object error) {
    syncing = false;
    syncProgress = 0;
    final waiter = _syncWaiter;
    _syncWaiter = null;
    if (waiter != null && !waiter.isCompleted) {
      waiter.completeError(error);
    }
  }

  Future<void> _removeHealthDataCallback() async {
    try {
      await ring.removeHealthDataCallback();
    } catch (_) {
      // Controller 销毁阶段只做回调清理，不再向 UI 报错。
    }
  }

  @override
  void dispose() {
    unawaited(_removeHealthDataCallback());
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _completeReadyWaiters(StateError('Demo controller disposed'));
    _failSyncWaiter(StateError('Demo controller disposed'));
    super.dispose();
  }
}
