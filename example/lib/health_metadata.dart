import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import 'health_store.dart';
import 'i18n.dart';
import 'support_menu.dart';

class DemoHealthDefinition {
  const DemoHealthDefinition({
    required this.type,
    required this.titleZh,
    required this.titleEn,
    required this.color,
    required this.capabilityKey,
    this.realtimeMetric,
  });

  final String type;
  final String titleZh;
  final String titleEn;
  final Color color;
  final String capabilityKey;
  final RealtimeMetric? realtimeMetric;

  String get title => demoTr(titleZh, titleEn);
}

const demoHealthDefinitions = <DemoHealthDefinition>[
  DemoHealthDefinition(
    type: HealthTypeId.step,
    titleZh: '计步',
    titleEn: 'Steps',
    color: Color(0xFF32A874),
    capabilityKey: DemoCapabilityKey.step,
  ),
  DemoHealthDefinition(
    type: HealthTypeId.heartRate,
    titleZh: '心率',
    titleEn: 'Heart rate',
    color: Color(0xFFE75B67),
    capabilityKey: DemoCapabilityKey.heartRate,
    realtimeMetric: RealtimeMetric.hr,
  ),
  DemoHealthDefinition(
    type: HealthTypeId.sleep,
    titleZh: '睡眠',
    titleEn: 'Sleep',
    color: Color(0xFF6C72C9),
    capabilityKey: DemoCapabilityKey.sleep,
  ),
  DemoHealthDefinition(
    type: HealthTypeId.workout,
    titleZh: '多运动',
    titleEn: 'Workouts',
    color: Color(0xFFF29B4B),
    capabilityKey: DemoCapabilityKey.workout,
  ),
  DemoHealthDefinition(
    type: HealthTypeId.bloodOxygen,
    titleZh: '血氧',
    titleEn: 'Blood oxygen',
    color: Color(0xFF3D91D7),
    capabilityKey: DemoCapabilityKey.bloodOxygen,
    realtimeMetric: RealtimeMetric.bloodOxy,
  ),
  DemoHealthDefinition(
    type: HealthTypeId.hrv,
    titleZh: 'HRV',
    titleEn: 'HRV',
    color: Color(0xFF9B68C7),
    capabilityKey: DemoCapabilityKey.hrv,
    realtimeMetric: RealtimeMetric.hrv,
  ),
  DemoHealthDefinition(
    type: HealthTypeId.pressure,
    titleZh: '压力',
    titleEn: 'Stress',
    color: Color(0xFFDE8D37),
    capabilityKey: DemoCapabilityKey.pressure,
    realtimeMetric: RealtimeMetric.pressure,
  ),
  DemoHealthDefinition(
    type: HealthTypeId.bloodPressure,
    titleZh: '血压',
    titleEn: 'Blood pressure',
    color: Color(0xFFDC6475),
    capabilityKey: DemoCapabilityKey.bloodPressure,
    realtimeMetric: RealtimeMetric.bloodPressure,
  ),
  DemoHealthDefinition(
    type: HealthTypeId.bloodSugar,
    titleZh: '血糖',
    titleEn: 'Blood sugar',
    color: Color(0xFFB68145),
    capabilityKey: DemoCapabilityKey.bloodSugar,
    realtimeMetric: RealtimeMetric.bloodSugar,
  ),
  DemoHealthDefinition(
    type: HealthTypeId.temperature,
    titleZh: '体温',
    titleEn: 'Temperature',
    color: Color(0xFFE27350),
    capabilityKey: DemoCapabilityKey.bodyTemperature,
    realtimeMetric: RealtimeMetric.temperature,
  ),
  DemoHealthDefinition(
    type: HealthTypeId.muslimCount,
    titleZh: '赞念计数',
    titleEn: 'Prayer count',
    color: Color(0xFF4A9B8E),
    capabilityKey: DemoCapabilityKey.muslimCountData,
  ),
];

DemoHealthDefinition healthDefinitionFor(String type) =>
    demoHealthDefinitions.firstWhere((definition) => definition.type == type);
