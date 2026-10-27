import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rwfit_ble/rwfit_ble.dart';
import 'package:rwfit_ble_example/demo_controller.dart';
import 'package:rwfit_ble_example/device_store.dart';
import 'package:rwfit_ble_example/health_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const methods = MethodChannel('rwfit_ble/methods');
  const events = MethodChannel('rwfit_ble/events');
  const savedDevice = BleDevice(
    name: 'RW Ring',
    mac: 'AA:BB:CC:DD:EE:FF',
    rssi: -60,
  );
  late DemoController controller;
  late bool controllerDisposed;
  late List<MethodCall> calls;
  late Future<Map<String, Object>> Function() unbindResult;
  late Future<Map<String, Object>> Function(MethodCall)? handleMethod;

  setUp(() async {
    calls = [];
    controllerDisposed = false;
    handleMethod = null;
    unbindResult = () async => {'code': 0};
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      events,
      (_) async => null,
    );
    binding.defaultBinaryMessenger.setMockMethodCallHandler(methods, (
      call,
    ) async {
      calls.add(call);
      if (handleMethod != null) return handleMethod!(call);
      switch (call.method) {
        case 'getSDKVersion':
          return {'code': 0, 'version': 'test-sdk'};
        case 'getPluginVersion':
          return {'code': 0, 'pluginVersion': 'test-plugin'};
        case 'unbind':
          return unbindResult();
        case 'isBleConnected':
          return {'code': 0, 'connected': false};
        default:
          return {'code': 0};
      }
    });
    SharedPreferences.setMockInitialValues({});
    await DeviceStore.save(savedDevice);
    await DeviceStore.saveCapabilities({'step': true});
    await DeviceStore.saveLastSyncAt(DateTime(2026, 10, 27));
    controller = DemoController();
    if (controller.loadingSavedState) {
      final loaded = Completer<void>();
      void listener() {
        if (!controller.loadingSavedState) {
          controller.removeListener(listener);
          loaded.complete();
        }
      }

      controller.addListener(listener);
      await loaded.future;
    }
  });

  tearDown(() async {
    if (!controllerDisposed) controller.dispose();
    // 等待异步取消事件监听及清理原生订阅后再移除 mock。
    await Future<void>.delayed(Duration.zero);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(methods, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(events, null);
  });

  Future<void> expectLocalBindingCleared() async {
    expect(controller.device, isNull);
    expect(controller.connected, isFalse);
    expect(controller.connectionState, ConnectState.disconnected);
    expect(controller.capabilities.raw, isEmpty);
    expect(controller.healthRecords, isEmpty);
    expect(controller.lastSyncAt, isNull);
    expect(controller.ready, isFalse);
    expect(controller.syncing, isFalse);
    expect(controller.syncProgress, 0);
    expect(controller.firmware, isNull);
    expect(controller.powerLevel, isNull);
    expect(controller.macAddress, isNull);
    expect(controller.deviceInfoError, isNull);
    expect(controller.lastError, isNull);
    expect(controller.latestFor(HealthTypeId.heartRate), isNull);
    expect(await DeviceStore.load(), isNull);
    expect(await DeviceStore.loadCapabilities(), isEmpty);
    expect(await DeviceStore.loadLastSyncAt(), isNull);
  }

  Future<void> emit(Map<String, Object> event) async {
    ServicesBinding.instance.channelBuffers.push(
      'rwfit_ble/events',
      const StandardMethodCodec().encodeSuccessEnvelope(event),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
  }

  Map<String, Object> functionMenu({String? uuid}) => {
    'event': 'rwfit:functionMenu',
    'name': savedDevice.name,
    'mac': savedDevice.mac,
    'uuid': ?uuid,
    'supportMenu': {'step': true},
  };

  test(
    'offline unbind success clears the saved device and cached state',
    () async {
      expect(controller.connected, isFalse);
      expect(controller.device, isNotNull);

      await controller.unbind();

      expect(calls.where((call) => call.method == 'unbind'), hasLength(1));
      await expectLocalBindingCleared();
    },
  );

  test(
    'online unbind waits for native success before clearing the binding',
    () async {
      controller.connectionState = ConnectState.connected;
      controller.ready = true;
      final response = Completer<Map<String, Object>>();
      final requested = Completer<void>();
      unbindResult = () {
        requested.complete();
        return response.future;
      };

      final pending = controller.unbind();
      await requested.future;
      expect(controller.device, isNotNull);
      expect((await DeviceStore.load())?.mac, savedDevice.mac);

      response.complete({'code': 0});
      await pending;
      await expectLocalBindingCleared();
    },
  );

  test('online command failure preserves the binding and its cache', () async {
    controller.connectionState = ConnectState.connected;
    controller.ready = true;
    unbindResult = () async => {'code': 5, 'msg': 'unbind failed'};

    await expectLater(
      controller.unbind(),
      throwsA(isA<RwfitException>().having((error) => error.code, 'code', 5)),
    );

    expect(controller.device?.mac, savedDevice.mac);
    expect(controller.connected, isTrue);
    expect((await DeviceStore.load())?.mac, savedDevice.mac);
    expect(await DeviceStore.loadCapabilities(), {'step': true});
    expect(await DeviceStore.loadLastSyncAt(), isNotNull);
  });

  for (final platform in ['Android', 'iOS']) {
    for (final online in [false, true]) {
      test(
        '$platform ${online ? 'online' : 'offline'} unbind clears all local state',
        () async {
          if (platform == 'iOS') {
            controller.device = const BleDevice(
              name: 'RW Ring',
              mac: '',
              rssi: -60,
              uuid: 'TEST-IOS-UUID',
            );
            await DeviceStore.save(controller.device!);
          }
          controller.connectionState = online
              ? ConnectState.connected
              : ConnectState.disconnected;
          controller.ready = online;
          controller.powerLevel = 80;
          controller.firmware = const FirmwareInfo(
            deviceClazz: 'ring',
            deviceNo: '1.0',
            uiVersion: '1.0',
          );
          controller.deviceInfoError = 'old query error';
          controller.lastError = 'old connection error';
          controller.syncProgress = 1;
          controller.healthRecords = {
            HealthTypeId.heartRate: [
              const DemoHealthRecord(
                type: HealthTypeId.heartRate,
                measuredAtSec: 100,
                values: {'value': 75},
              ),
            ],
          };

          await controller.unbind();
          await expectLocalBindingCleared();

          // 模拟系统稍后才交付的旧连接、失败、功能表及健康数据回调。
          for (final event in <Map<String, Object>>[
            {'event': 'rwfit:connectState', 'state': 'connected'},
            {
              'event': 'rwfit:connectState',
              'state': 'failed',
              'reason': 'MANUAL_DISCONNECT',
            },
            functionMenu(uuid: platform == 'iOS' ? 'TEST-IOS-UUID' : null),
            {
              'event': 'rwfit:syncResult',
              'type': HealthTypeId.heartRate,
              'data': [
                {'time': 100, 'heartRate': 80},
              ],
            },
            {'event': 'rwfit:syncError', 'code': 7},
            {
              'event': 'rwfit:healthData',
              'dataType': HealthType.hr.value,
              'dataValue': 80,
              'time': 100,
            },
          ]) {
            await emit(event);
          }
          await expectLocalBindingCleared();

          // 下一次真正发起连接仍能正常绑定。
          await emit({'event': 'rwfit:connectState', 'state': 'connecting'});
          await emit(
            functionMenu(uuid: platform == 'iOS' ? 'TEST-IOS-UUID' : null),
          );
          expect(controller.connected, isTrue);
          expect((await DeviceStore.load())?.mac, savedDevice.mac);
        },
      );
    }
  }

  test(
    'unbind cancels an in-flight reconnect without restoring failed state',
    () async {
      final requested = Completer<void>();
      handleMethod = (call) async {
        if (call.method == 'isBleConnected') {
          return {'code': 0, 'connected': false};
        }
        if (call.method == 'reconnectDevice') requested.complete();
        return {'code': 0};
      };
      final reconnect = controller.reconnect();
      final reconnectFailure = expectLater(reconnect, throwsStateError);
      await requested.future;
      await controller.unbind();
      await reconnectFailure;
      await expectLocalBindingCleared();
    },
  );

  test(
    'unbind waits for in-flight binding writes and clears SDK binding last',
    () async {
      final bindingWrite = Completer<void>();
      final releaseWrite = Completer<Map<String, Object>>();
      final bindingStates = <bool>[];
      handleMethod = (call) async {
        if (call.method == 'iOSSetBindedStatus') {
          final enabled = (call.arguments as Map)['isBinded'] as bool;
          if (enabled) {
            bindingWrite.complete();
            final result = await releaseWrite.future;
            bindingStates.add(true);
            return result;
          }
          bindingStates.add(false);
        }
        return {'code': 0};
      };
      await emit(functionMenu());
      await bindingWrite.future;

      var completed = false;
      final pending = controller.unbind().then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse);
      releaseWrite.complete({'code': 0});
      await pending;

      expect(bindingStates, [true, false]);
      await expectLocalBindingCleared();
    },
  );

  test('repeated unbind calls share one native request', () async {
    final response = Completer<Map<String, Object>>();
    unbindResult = () => response.future;
    final first = controller.unbind();
    final second = controller.unbind();
    expect(identical(first, second), isTrue);
    response.complete({'code': 0});
    await Future.wait([first, second]);
    expect(calls.where((call) => call.method == 'unbind'), hasLength(1));
    await expectLocalBindingCleared();
  });

  test(
    'unbind still clears saved state if the controller is disposed while waiting',
    () async {
      final response = Completer<Map<String, Object>>();
      unbindResult = () => response.future;
      final pending = controller.unbind();
      controller.dispose();
      controllerDisposed = true;
      response.complete({'code': 0});
      await pending;
      await expectLocalBindingCleared();
    },
  );
}
