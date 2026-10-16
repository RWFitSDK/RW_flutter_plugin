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
  int _connectionGeneration = 0;
  bool _disposed = false;
  Future<void>? _infoRefresh;
  int? _infoRefreshGeneration;

  /// 同一设备重连也属于新会话，异步查询不得写回上一次连接的结果。
  int get connectionGeneration => _connectionGeneration;

  BleDevice? device;
  DemoCapabilities capabilities = const DemoCapabilities.empty();
  ConnectState connectionState = ConnectState.disconnected;
  bool ready = false;
  bool loadingSavedState = true;
  bool syncing = false;
  double syncProgress = 0;
  int? powerLevel;
  FirmwareInfo? firmware;
  String? macAddress;
  String? deviceInfoError;
  String? sdkVersion;
  String? pluginVersion;
  DateTime? lastSyncAt;
  String? lastError;
  Map<String, List<DemoHealthRecord>> healthRecords = {};
  final Map<String, DemoHealthRecord> _realtimeRecords = {};

  bool get connected => ready && connectionState == ConnectState.connected;

  static String? _identity(String? uuid, String? mac) {
    final value = uuid?.isNotEmpty == true ? uuid : mac;
    return value?.isNotEmpty == true ? value!.toUpperCase() : null;
  }

  String? get deviceId => _identity(device?.uuid, device?.mac);

  bool _isCurrentSession(int generation) =>
      !_disposed && connected && generation == _connectionGeneration;

  void _subscribe() {
    _subscriptions.add(
      ring.onConnectState.listen((event) {
        if (_disposed) return;
        connectionState = event.state;
        if (event.state != ConnectState.connected) {
          _connectionGeneration++;
          ready = false;
        }
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
    _subscriptions.add(ring.onFunctionMenu.listen(_handleFunctionMenu));
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
        if (_disposed || !connected || !syncing) return;
        final generation = _connectionGeneration;
        syncing = false;
        syncProgress = 1;
        lastSyncAt = DateTime.now();
        final waiter = _syncWaiter;
        _syncWaiter = null;
        if (waiter != null && !waiter.isCompleted) waiter.complete();
        notifyListeners();
        try {
          await DeviceStore.saveLastSyncAt(lastSyncAt!);
        } catch (error) {
          if (!_isCurrentSession(generation)) return;
          lastError = '$error';
          notifyListeners();
        }
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

  Future<void> _handleFunctionMenu(FunctionMenu menu) async {
    if (_disposed) return;
    final incomingId = _identity(menu.uuid, menu.mac);
    try {
      final previousDevice = device;
      final changedDevice = deviceId != incomingId;
      final mac = menu.mac.isNotEmpty
          ? menu.mac
          : (!changedDevice ? previousDevice?.mac ?? '' : '');
      final uuid = menu.uuid?.isNotEmpty == true ? menu.uuid : null;
      final unchanged =
          !changedDevice &&
          previousDevice != null &&
          previousDevice.name == menu.name &&
          previousDevice.mac == mac &&
          previousDevice.uuid == uuid;
      if (!connected || changedDevice) _connectionGeneration++;
      device = unchanged
          ? previousDevice
          : BleDevice(name: menu.name, mac: mac, rssi: 0, uuid: uuid);
      macAddress = mac.isEmpty ? null : mac;
      deviceInfoError = null;
      capabilities = DemoCapabilities(
        Map<String, dynamic>.unmodifiable(menu.raw),
      );
      connectionState = ConnectState.connected;
      ready = true;
      lastError = null;
      if (changedDevice) {
        _failSyncWaiter(StateError('Device changed during sync'));
        _realtimeRecords.clear();
        healthRecords = {};
        lastSyncAt = null;
        powerLevel = null;
        firmware = null;
      }
      _completeReadyWaiters();
      notifyListeners();
      // 收到功能表后按原有方式分项保存，不因同一设备断连而中断保存。
      final connectedDevice = device!;
      try {
        await DeviceStore.save(connectedDevice);
        await DeviceStore.saveCapabilities(menu.raw);
        if (changedDevice) await DeviceStore.clearLastSyncAt();
        await ring.iosSetBindedStatus(true);
      } catch (error) {
        if (_disposed || deviceId != incomingId) return;
        lastError = '$error';
        notifyListeners();
      }
      if (!_disposed && connected && deviceId == incomingId) {
        unawaited(refreshDeviceInfo(silent: true));
      }
    } catch (error) {
      if (_disposed) return;
      lastError = '$error';
      notifyListeners();
    }
  }

  /// 确认当前设备就绪后调用，命令排队和超时由 SDK 处理。
  Future<T> runDeviceCommand<T>(Future<T> Function() command) async {
    if (!_isCurrentSession(_connectionGeneration)) {
      throw RwfitException(-1, 'device session changed');
    }
    return command();
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
    final generation = _connectionGeneration;
    try {
      final savedDevice = await DeviceStore.load();
      final savedCapabilities = await DeviceStore.loadCapabilities();
      final savedLastSyncAt = await DeviceStore.loadLastSyncAt();
      if (_disposed) return;
      if (!ready && generation == _connectionGeneration && device == null) {
        device = savedDevice;
        macAddress = savedDevice?.mac.isNotEmpty == true
            ? savedDevice!.mac
            : null;
        capabilities = DemoCapabilities(savedCapabilities);
        lastSyncAt = savedLastSyncAt;
        healthRecords = {};
      }
    } catch (error) {
      if (_disposed) return;
      lastError = '$error';
    }
    if (_disposed) return;
    loadingSavedState = false;
    notifyListeners();
  }

  Future<void> _loadVersions() async {
    try {
      final values = await Future.wait([
        ring.getSdkVersion(),
        ring.getPluginVersion(),
      ]);
      if (_disposed) return;
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
    if (_disposed) throw StateError('Demo controller disposed');
    final savedDevice = device;
    if (savedDevice == null) throw StateError('No saved device');
    if (connected || await ring.isConnected()) {
      if (ready) return;
    }
    if (_disposed) throw StateError('Demo controller disposed');
    connectionState = ConnectState.connecting;
    _connectionGeneration++;
    ready = false;
    lastError = null;
    notifyListeners();
    final waiter = Completer<void>();
    _readyWaiters.add(waiter);
    try {
      await Future.wait<void>([
        () async {
          await ring.iosSetBindedStatus(true);
          if (_disposed) return;
          await ring.reconnect(savedDevice);
        }(),
        waiter.future.timeout(const Duration(seconds: 20)),
      ], eagerError: true);
    } catch (error) {
      if (!_disposed && !connected) {
        connectionState = ConnectState.failed;
        lastError = '$error';
        notifyListeners();
      }
      rethrow;
    } finally {
      _readyWaiters.remove(waiter);
    }
  }

  void _closeConnection() {
    _connectionGeneration++;
    ready = false;
    connectionState = ConnectState.disconnected;
    _realtimeRecords.clear();
    _completeReadyWaiters(StateError('Connection closed'));
    _failSyncWaiter(StateError('Connection closed during sync'));
    notifyListeners();
  }

  Future<void> disconnect() async {
    await ring.disconnect();
    if (!_disposed) _closeConnection();
  }

  Future<void> unbind() async {
    final unboundId = deviceId;
    await ring.unbind();
    if (_disposed || deviceId != unboundId) return;
    _closeConnection();
    device = null;
    capabilities = const DemoCapabilities.empty();
    healthRecords = {};
    firmware = null;
    powerLevel = null;
    macAddress = null;
    deviceInfoError = null;
    lastSyncAt = null;
    notifyListeners();
    try {
      await ring.iosSetBindedStatus(false);
    } finally {
      await DeviceStore.clear();
    }
  }

  Future<void> syncAllHealthData() async {
    if (device == null) throw StateError('No bound device');
    if (syncing) {
      await _syncWaiter?.future;
      return;
    }
    if (!connected) await reconnect();
    if (_disposed) throw StateError('Demo controller disposed');
    final generation = _connectionGeneration;
    syncing = true;
    syncProgress = 0.05;
    healthRecords = {};
    _receivedSyncTypes.clear();
    lastError = null;
    final waiter = Completer<void>();
    _syncWaiter = waiter;
    notifyListeners();
    try {
      await Future.wait<void>([
        ring.syncAllHealthData(),
        waiter.future.timeout(const Duration(minutes: 3)),
      ], eagerError: true);
    } catch (_) {
      if (!_disposed && generation == _connectionGeneration) {
        syncing = false;
        if (identical(_syncWaiter, waiter)) _syncWaiter = null;
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<void> refreshDeviceInfo({bool silent = false}) async {
    if (_disposed || !connected) {
      if (silent) return;
      throw StateError('Device is not connected');
    }
    final generation = _connectionGeneration;
    var task = _infoRefresh;
    if (task == null || _infoRefreshGeneration != generation) {
      task = _refreshDeviceInfo(generation);
      _infoRefresh = task;
      _infoRefreshGeneration = generation;
    }
    try {
      await task;
    } catch (error) {
      if (_isCurrentSession(generation)) {
        deviceInfoError = '$error';
        lastError = '$error';
        notifyListeners();
      }
      if (!silent) rethrow;
    } finally {
      if (identical(_infoRefresh, task)) _infoRefresh = null;
    }
  }

  Future<void> _refreshDeviceInfo(int generation) async {
    // SDK 已有串行队列，Demo 可同时提交，分别应用成功的查询结果。
    await Future.wait<void>([
      () async {
        final power = await runDeviceCommand(ring.getPower);
        if (!_isCurrentSession(generation)) return;
        powerLevel = power;
        notifyListeners();
      }(),
      () async {
        final version = await runDeviceCommand(ring.getFirmwareVersion);
        if (!_isCurrentSession(generation)) return;
        firmware = version;
        notifyListeners();
      }(),
      () async {
        final mac = await runDeviceCommand(ring.getMacAddress);
        if (!_isCurrentSession(generation)) return;
        final currentDevice = device;
        final changed =
            mac.isNotEmpty && currentDevice != null && mac != currentDevice.mac;
        if (mac.isNotEmpty) macAddress = mac;
        if (changed) {
          device = BleDevice(
            name: currentDevice.name,
            mac: mac,
            rssi: currentDevice.rssi,
            uuid: currentDevice.uuid,
          );
        }
        notifyListeners();
        if (changed) await DeviceStore.save(device!);
      }(),
    ]);
    if (!_isCurrentSession(generation)) return;
    deviceInfoError = null;
    notifyListeners();
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
    _disposed = true;
    _connectionGeneration++;
    ready = false;
    unawaited(_removeHealthDataCallback());
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _completeReadyWaiters(StateError('Demo controller disposed'));
    _failSyncWaiter(StateError('Demo controller disposed'));
    super.dispose();
  }
}
