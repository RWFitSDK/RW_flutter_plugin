import 'package:flutter_test/flutter_test.dart';
import 'package:rwfit_ble/rwfit_ble.dart';
import 'package:rwfit_ble_example/health_metadata.dart';
import 'package:rwfit_ble_example/health_store.dart';
import 'package:rwfit_ble_example/i18n.dart';

void main() {
  tearDown(() => setDemoLanguage(DemoLanguage.zh));

  test('parses daily and measurement sync records for health cards', () {
    final steps = DemoHealthStore.parseSyncResult(
      const SyncResult(
        type: HealthTypeId.step,
        data: [
          {
            'time': 100,
            'totalSteps': 4321,
            'totalDistance': 2800,
            'totalCalorie': 123000,
          },
        ],
      ),
    );
    final temperature = DemoHealthStore.parseSyncResult(
      const SyncResult(
        type: HealthTypeId.temperature,
        data: [
          {
            'time': 100,
            'items': [
              {'time': 120, 'temp': 365},
            ],
          },
        ],
      ),
    );

    expect(steps.single.valueText, '4321 步');
    expect(steps.single.summary, '2800 m · 123 kcal');
    expect(temperature.single.valueText, '36.5 ℃');
    expect(temperature.single.measuredAtSec, 120);

    setDemoLanguage(DemoLanguage.en);
    expect(steps.single.valueText, '4321 steps');
  });

  test('formats realtime blood pressure with diastolic value', () {
    final record = DemoHealthStore.parseRealtime(
      const RealtimeData.fromSeconds(
        type: HealthType.bloodBp,
        value: 120,
        diastolic: 80,
        timestampSec: 200,
      ),
    );

    expect(record?.type, HealthTypeId.bloodPressure);
    expect(record?.valueText, '120/80 mmHg');
    expect(record?.summary, '实时检测');

    setDemoLanguage(DemoLanguage.en);
    expect(record?.summary, 'Real-time measurement');
  });

  test('parses realtime muslim count for the live header', () {
    final record = DemoHealthStore.parseRealtime(
      const RealtimeData.fromSeconds(
        type: HealthType.muslimCount,
        value: 123,
        timestampSec: 200,
      ),
    );

    expect(record?.type, HealthTypeId.muslimCount);
    expect(record?.valueText, '123 次');
    expect(record?.summary, '实时检测');
  });

  test('parses normalized realtime temperature for the live header', () {
    final record = DemoHealthStore.parseRealtime(
      const RealtimeData.fromSeconds(
        type: HealthType.temperature,
        value: 36.5,
        timestampSec: 200,
      ),
    );

    expect(record?.type, HealthTypeId.temperature);
    expect(record?.valueText, '36.5 ℃');
    expect(
      healthDefinitionFor(HealthTypeId.temperature).realtimeMetric,
      RealtimeMetric.temperature,
    );
  });

  test('hides manual measurement for steps, sleep and muslim count', () {
    for (final type in const [
      HealthTypeId.step,
      HealthTypeId.sleep,
      HealthTypeId.muslimCount,
    ]) {
      expect(healthDefinitionFor(type).realtimeMetric, isNull);
    }
    expect(
      healthDefinitionFor(HealthTypeId.heartRate).realtimeMetric,
      RealtimeMetric.hr,
    );
  });

  test('keeps structured sleep segments for localized history details', () {
    final records = DemoHealthStore.parseSyncResult(
      const SyncResult(
        type: HealthTypeId.sleep,
        data: [
          {
            'time': 100,
            'duration': 90,
            'beginTime': 100,
            'endTime': 200,
            'items': [
              {'len': 30, 'sleepType': 1},
              {'len': 60, 'sleepType': 2},
            ],
          },
        ],
      ),
    );

    expect(records.single.sleepSegments, hasLength(2));
    expect(records.single.sleepSegments.first.label, '浅睡');
    expect(records.single.valueText, '1 小时 30 分');

    setDemoLanguage(DemoLanguage.en);
    expect(records.single.sleepSegments.first.label, 'Light sleep');
    expect(records.single.valueText, '1 h 30 min');
  });

  test('keeps every synchronized measurement item', () {
    final records = DemoHealthStore.parseSyncResult(
      const SyncResult(
        type: HealthTypeId.heartRate,
        data: [
          {
            'time': 100,
            'items': [
              {'time': 300, 'hr': 62},
              {'time': 300, 'hr': 62},
              {'time': 301, 'hr': 78},
            ],
          },
        ],
      ),
    );

    expect(records, hasLength(3));
  });

  test('keeps step total and every hourly item separately', () {
    final records = DemoHealthStore.parseSyncResult(
      const SyncResult(
        type: HealthTypeId.step,
        data: [
          {
            'time': 100,
            'totalSteps': 300,
            'totalDistance': 210,
            'totalCalorie': 12000,
            'items': [
              {
                'time': 100,
                'index': 0,
                'steps': 100,
                'distance': 70,
                'calorie': 4000,
              },
              {
                'time': 3700,
                'index': 1,
                'steps': 200,
                'distance': 140,
                'calorie': 8000,
              },
            ],
          },
        ],
      ),
    );

    expect(records, hasLength(3));
    expect(records.first.isDailySummary, isTrue);
    expect(records.first.valueText, '300 步');
    expect(records.skip(1).every((record) => !record.isDailySummary), isTrue);
    expect(records[1].valueText, '100 步');
    expect(records[2].valueText, '200 步');
    expect(records[2].measuredAtSec, 3700);
  });

  test('keeps muslim count total and every synchronized item separately', () {
    final records = DemoHealthStore.parseSyncResult(
      const SyncResult(
        type: HealthTypeId.muslimCount,
        data: [
          {
            'time': 100,
            'totalCount': 60,
            'items': [
              {'time': 200, 'count': 20},
              {'time': 300, 'count': 40},
            ],
          },
        ],
      ),
    );

    expect(records, hasLength(3));
    expect(records.first.isDailySummary, isTrue);
    expect(records.first.valueText, '60 次');
    expect(records.skip(1).every((record) => !record.isDailySummary), isTrue);
    expect(records[1].valueText, '20 次');
    expect(records[2].valueText, '40 次');
    expect(records[2].measuredAtSec, 300);
  });
}
