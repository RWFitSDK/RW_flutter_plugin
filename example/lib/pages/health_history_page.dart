import 'dart:async';

import 'package:flutter/material.dart';

import '../demo_controller.dart';
import '../demo_theme.dart';
import '../health_metadata.dart';
import '../health_store.dart';
import '../i18n.dart';

class HealthHistoryPage extends StatefulWidget {
  const HealthHistoryPage({
    super.key,
    required this.controller,
    required this.definition,
  });

  final DemoController controller;
  final DemoHealthDefinition definition;

  @override
  State<HealthHistoryPage> createState() => _HealthHistoryPageState();
}

class _HealthHistoryPageState extends State<HealthHistoryPage> {
  StreamSubscription<void>? _completeSubscription;
  bool _measuring = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _completeSubscription = widget.controller.ring.onRealtimeMeasureComplete
        .listen((_) {
          if (mounted) setState(() => _measuring = false);
        });
  }

  Future<void> _toggleMeasurement() async {
    final metric = widget.definition.realtimeMetric;
    if (metric == null || _busy) return;
    setState(() => _busy = true);
    try {
      if (_measuring) {
        await widget.controller.ring.stopRealtimeMeasure(metric);
      } else {
        await widget.controller.ring.startRealtimeMeasure(metric);
      }
      if (mounted) setState(() => _measuring = !_measuring);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _completeSubscription?.cancel();
    final metric = widget.definition.realtimeMetric;
    if (_measuring && metric != null) {
      unawaited(widget.controller.ring.stopRealtimeMeasure(metric));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.definition.title)),
    body: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final records = widget.controller.recordsFor(widget.definition.type);
        final latest = widget.controller.latestFor(widget.definition.type);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: LinearGradient(
                  colors: [
                    widget.definition.color,
                    widget.definition.color.withValues(alpha: 0.76),
                  ],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    demoTr(
                      '最近一次${widget.definition.title}',
                      'Latest ${widget.definition.title}',
                    ),
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    latest?.valueText ?? '--',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    latest == null
                        ? demoTr('暂无数据', 'No data')
                        : _formatDateTime(latest.measuredAtSec),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            if (widget.definition.realtimeMetric != null) ...[
              SectionHeading(demoTr('实时检测', 'Real-time measurement')),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  demoTr(
                                    '${widget.definition.title}实时检测',
                                    'Live ${widget.definition.title}',
                                  ),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  _measuring
                                      ? demoTr(
                                          '检测中，最新结果会显示在上方',
                                          'Measuring; the latest result appears above',
                                        )
                                      : demoTr(
                                          '由设备开始单次实时测量',
                                          'Start a one-time measurement on the device',
                                        ),
                                  style: const TextStyle(
                                    color: DemoColors.secondaryText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Chip(
                            label: Text(
                              _measuring
                                  ? demoTr('检测中', 'Measuring')
                                  : demoTr('未开始', 'Idle'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: !widget.controller.connected || _busy
                              ? null
                              : _toggleMeasurement,
                          child: Text(
                            _measuring
                                ? demoTr('结束检测', 'Stop measurement')
                                : demoTr('开始检测', 'Start measurement'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            SectionHeading(
              demoTr('历史记录', 'History'),
              caption: demoTr(
                '同步 ${records.length} 条',
                '${records.length} synced',
              ),
            ),
            if (records.isEmpty)
              DemoEmptyCard(
                title: demoTr(
                  '暂无${widget.definition.title}记录',
                  'No ${widget.definition.title} history',
                ),
                message: demoTr(
                  '请回到首页下拉同步，设备中的历史数据会显示在这里。',
                  'Pull down on Home to sync history from the device.',
                ),
              )
            else
              Card(
                child: Column(
                  children: [
                    for (var index = 0; index < records.length; index++) ...[
                      _historyTile(records[index]),
                      if (index != records.length - 1)
                        const Divider(height: 1, indent: 56),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );

  Widget _historyTile(DemoHealthRecord record) {
    final leading = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: widget.definition.color,
      ),
    );
    final trailing = Text(
      _formatDateTime(record.measuredAtSec),
      textAlign: TextAlign.right,
      style: const TextStyle(color: DemoColors.secondaryText, fontSize: 12),
    );
    final segments = record.sleepSegments;
    if (widget.definition.type != HealthTypeId.sleep || segments.isEmpty) {
      return ListTile(
        leading: leading,
        title: Text(
          record.valueText,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: record.summary.isEmpty ? null : Text(record.summary),
        trailing: trailing,
      );
    }
    return ExpansionTile(
      leading: leading,
      title: Text(
        record.valueText,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(record.summary),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          trailing,
          const SizedBox(width: 5),
          const Icon(Icons.expand_more),
        ],
      ),
      children: [
        for (var index = 0; index < segments.length; index++)
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.only(left: 56, right: 20),
            leading: Text('${index + 1}'),
            title: Text(segments[index].label),
            trailing: Text(
              demoTr(
                '${segments[index].minutes} 分钟',
                '${segments[index].minutes} min',
              ),
            ),
          ),
      ],
    );
  }

  String _formatDateTime(int timestampSec) {
    if (timestampSec <= 0) return '--';
    final value = DateTime.fromMillisecondsSinceEpoch(timestampSec * 1000);
    final now = DateTime.now();
    final time =
        '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    if (value.year == now.year &&
        value.month == now.month &&
        value.day == now.day) {
      return '${demoTr('今天', 'Today')}\n$time';
    }
    return '${value.month}/${value.day}\n$time';
  }
}
