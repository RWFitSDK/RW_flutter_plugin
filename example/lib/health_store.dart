import 'package:rwfit_ble/rwfit_ble.dart';

import 'i18n.dart';

/// Demo 首页和历史页使用的内存健康记录。
class DemoHealthRecord {
  const DemoHealthRecord({
    required this.type,
    required this.measuredAtSec,
    required this.values,
  });

  final String type;
  final int measuredAtSec;
  final Map<String, dynamic> values;

  bool get isDailySummary => values['dailySummary'] == true;

  String get valueText => switch (type) {
    HealthTypeId.step => demoTr(
      '${_integer(values['steps'])} 步',
      '${_integer(values['steps'])} steps',
    ),
    HealthTypeId.sleep => _formatDuration(_integer(values['durationMinutes'])),
    HealthTypeId.muslimCount => demoTr(
      '${_integer(values['count'])} 次',
      '${_integer(values['count'])} times',
    ),
    HealthTypeId.bloodPressure =>
      '${_integer(values['systolic'])}/${_integer(values['diastolic'])} mmHg',
    _ => '${_compact(_number(values['value']))}${_unit(type)}',
  };

  String get summary {
    if (values['realtime'] == true) {
      return demoTr('实时检测', 'Real-time measurement');
    }
    return switch (type) {
      HealthTypeId.step =>
        '${_integer(values['distanceMeters'])} m · '
            '${_formatCalories(values['calories'])}',
      HealthTypeId.sleep => _sleepSummary,
      _ => '',
    };
  }

  List<DemoSleepSegment> get sleepSegments {
    final rawSegments = values['segments'] as List? ?? const [];
    return rawSegments
        .whereType<Map>()
        .map(
          (segment) => DemoSleepSegment(
            minutes: _integer(segment['minutes']),
            type: _integer(segment['type']),
          ),
        )
        .toList(growable: false);
  }

  String get _sleepSummary {
    final begin = _formatClock(_integer(values['beginTime']));
    final end = _formatClock(_integer(values['endTime']));
    final totals = <int, int>{};
    for (final segment in sleepSegments) {
      totals.update(
        segment.type,
        (value) => value + segment.minutes,
        ifAbsent: () => segment.minutes,
      );
    }
    final parts = <String>[
      demoTr('入睡 $begin · 醒来 $end', 'Asleep $begin · Awake $end'),
      if ((totals[2] ?? 0) > 0)
        demoTr('深睡 ${totals[2]} 分', 'Deep ${totals[2]} min'),
      if ((totals[1] ?? 0) > 0)
        demoTr('浅睡 ${totals[1]} 分', 'Light ${totals[1]} min'),
      if ((totals[3] ?? 0) > 0) 'REM ${totals[3]} min',
    ];
    return parts.join(' · ');
  }
}

class DemoSleepSegment {
  const DemoSleepSegment({required this.minutes, required this.type});

  final int minutes;
  final int type;

  String get label => switch (type) {
    0 => demoTr('清醒', 'Awake'),
    1 => demoTr('浅睡', 'Light sleep'),
    2 => demoTr('深睡', 'Deep sleep'),
    3 => 'REM',
    _ => demoTr('未知', 'Unknown'),
  };
}

abstract final class HealthTypeId {
  static const step = 'step';
  static const heartRate = 'hr';
  static const sleep = 'sleep';
  static const workout = 'workout';
  static const bloodOxygen = 'bo';
  static const hrv = 'hrv';
  static const pressure = 'pressure';
  static const bloodPressure = 'bp';
  static const bloodSugar = 'bloodSugar';
  static const temperature = 'temp';
  static const muslimCount = 'muslimCount';
}

class DemoHealthStore {
  DemoHealthStore._();

  static List<DemoHealthRecord> parseSyncResult(SyncResult result) {
    final records = <DemoHealthRecord>[];
    for (final day in result.data) {
      final dayTime = _integer(day['time']);
      if (result.type == HealthTypeId.step) {
        records.add(
          DemoHealthRecord(
            type: result.type,
            measuredAtSec: dayTime,
            values: {
              'steps': _integer(day['totalSteps']),
              'distanceMeters': _integer(day['totalDistance']),
              'calories': _number(day['totalCalorie']),
              'dailySummary': true,
            },
          ),
        );
        final items = day['items'] as List? ?? const [];
        for (final rawItem in items) {
          if (rawItem is! Map) continue;
          records.add(
            DemoHealthRecord(
              type: result.type,
              measuredAtSec: _positiveOrFallback(rawItem['time'], dayTime),
              values: {
                'steps': _integer(rawItem['steps']),
                'distanceMeters': _integer(rawItem['distance']),
                'calories': _number(rawItem['calorie']),
              },
            ),
          );
        }
        continue;
      }
      if (result.type == HealthTypeId.sleep) {
        final endTime = _positiveOrFallback(day['endTime'], dayTime);
        final items = day['items'] as List? ?? const [];
        records.add(
          DemoHealthRecord(
            type: result.type,
            measuredAtSec: endTime,
            values: {
              'durationMinutes': _integer(day['duration']),
              'beginTime': _integer(day['beginTime']),
              'endTime': _integer(day['endTime']),
              'segments': [
                for (final rawItem in items)
                  if (rawItem is Map)
                    {
                      'minutes': _integer(rawItem['len']),
                      'type': _integer(rawItem['sleepType']),
                    },
              ],
            },
          ),
        );
        continue;
      }
      if (result.type == HealthTypeId.muslimCount) {
        records.add(
          DemoHealthRecord(
            type: result.type,
            measuredAtSec: dayTime,
            values: {
              'count': _integer(day['totalCount']),
              'dailySummary': true,
            },
          ),
        );
        final items = day['items'] as List? ?? const [];
        for (final rawItem in items) {
          if (rawItem is! Map) continue;
          records.add(
            DemoHealthRecord(
              type: result.type,
              measuredAtSec: _positiveOrFallback(rawItem['time'], dayTime),
              values: {'count': _integer(rawItem['count'])},
            ),
          );
        }
        continue;
      }

      final items = day['items'] as List? ?? const [];
      for (final rawItem in items) {
        final item = (rawItem as Map).cast<String, dynamic>();
        records.add(_measurementRecord(result.type, item, dayTime));
      }
    }
    return records.where((record) => record.measuredAtSec > 0).toList();
  }

  static DemoHealthRecord? parseRealtime(RealtimeData data) {
    final type = switch (data.type) {
      HealthType.hr => HealthTypeId.heartRate,
      HealthType.bloodOxy => HealthTypeId.bloodOxygen,
      HealthType.bloodBp => HealthTypeId.bloodPressure,
      HealthType.pressure => HealthTypeId.pressure,
      HealthType.bloodSugar => HealthTypeId.bloodSugar,
      HealthType.muslimCount => HealthTypeId.muslimCount,
      HealthType.temperature => HealthTypeId.temperature,
      HealthType.hrv => HealthTypeId.hrv,
      null => null,
    };
    if (type == null) return null;
    return DemoHealthRecord(
      type: type,
      measuredAtSec: data.timestampSec,
      values: switch (type) {
        HealthTypeId.bloodPressure => {
          'systolic': data.value,
          'diastolic': data.diastolic ?? 0,
          'realtime': true,
        },
        HealthTypeId.muslimCount => {'count': data.value, 'realtime': true},
        _ => {'value': data.value, 'realtime': true},
      },
    );
  }

  static DemoHealthRecord _measurementRecord(
    String type,
    Map<String, dynamic> item,
    int fallbackTime,
  ) {
    final timestamp = _positiveOrFallback(item['time'], fallbackTime);
    if (type == HealthTypeId.bloodPressure) {
      return DemoHealthRecord(
        type: type,
        measuredAtSec: timestamp,
        values: {
          'systolic': _integer(item['systolic']),
          'diastolic': _integer(item['diastolic']),
        },
      );
    }
    final key = switch (type) {
      HealthTypeId.heartRate => 'hr',
      HealthTypeId.bloodOxygen => 'bloodOxy',
      HealthTypeId.hrv => 'hrv',
      HealthTypeId.pressure => 'pressure',
      HealthTypeId.bloodSugar => 'bloodSugar',
      HealthTypeId.temperature => 'temp',
      _ => '',
    };
    var value = _number(item[key]);
    if (type == HealthTypeId.temperature) value /= 10;
    return DemoHealthRecord(
      type: type,
      measuredAtSec: timestamp,
      values: {'value': value},
    );
  }
}

int _integer(Object? value) => (value as num?)?.toInt() ?? 0;

double _number(Object? value) => (value as num?)?.toDouble() ?? 0;

int _positiveOrFallback(Object? value, int fallback) {
  final parsed = _integer(value);
  return parsed > 0 ? parsed : fallback;
}

String _compact(num value) =>
    value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(1);

String _unit(String type) => switch (type) {
  HealthTypeId.heartRate => ' bpm',
  HealthTypeId.bloodOxygen => '%',
  HealthTypeId.hrv => ' ms',
  HealthTypeId.bloodSugar => ' mmol/L',
  HealthTypeId.temperature => ' ℃',
  _ => '',
};

String _formatCalories(Object? value) =>
    '${_compact(_number(value) / 1000)} kcal';

String _formatDuration(int minutes) => demoTr(
  '${minutes ~/ 60} 小时 ${minutes % 60} 分',
  '${minutes ~/ 60} h ${minutes % 60} min',
);

String _formatClock(int timestampSec) {
  if (timestampSec <= 0) return '--:--';
  final date = DateTime.fromMillisecondsSinceEpoch(timestampSec * 1000);
  return '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
}
