import 'package:flutter_test/flutter_test.dart';
import 'package:rwfit_ble/rwfit_ble.dart';
import 'package:rwfit_ble_example/support_menu.dart';

void main() {
  group('DemoCapabilities', () {
    test('maps realtime metrics to their health-data capabilities', () {
      final capabilities = DemoCapabilities({
        DemoCapabilityKey.heartRate: true,
        DemoCapabilityKey.bloodOxygen: false,
      });

      expect(capabilities.supportsRealtime(RealtimeMetric.hr), isTrue);
      expect(capabilities.supportsRealtime(RealtimeMetric.bloodOxy), isFalse);
    });

    test('requires every capability in a sensor combination', () {
      final capabilities = DemoCapabilities({
        DemoCapabilityKey.sensorRawPpg: true,
        DemoCapabilityKey.sensorRawAcc: true,
        DemoCapabilityKey.sensorRawIr: false,
      });

      expect(
        capabilities.supportsSensorSelection(SensorRawSelection.ppgGreen),
        isTrue,
      );
      expect(
        capabilities.supportsSensorSelection(SensorRawSelection.ppgGreenAndAcc),
        isTrue,
      );
      expect(
        capabilities.supportsSensorSelection(
          SensorRawSelection.ppgGreenAccAndIr,
        ),
        isFalse,
      );
    });

    test('enables a grouped page when any contained capability exists', () {
      final capabilities = DemoCapabilities({
        DemoCapabilityKey.temperatureMonitoring: true,
      });

      expect(capabilities.supportsAnyTimedMonitor, isTrue);
      expect(capabilities.supportsAnyHealthData, isFalse);
    });
  });
}
