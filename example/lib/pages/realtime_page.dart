import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

/// 实时测量页：演示 HR/BO/HRV/压力/血糖/血压（同一时间只能开一种）。
class RealtimePage extends StatefulWidget {
  const RealtimePage({super.key});

  @override
  State<RealtimePage> createState() => _RealtimePageState();
}

class _RealtimePageState extends State<RealtimePage> {
  final _ring = RwfitBle.instance;
  StreamSubscription? _sub;
  RealtimeMetric? _active;
  final _data = <String>[];

  @override
  void initState() {
    super.initState();
    _sub = _ring.onRealtimeData.listen((d) {
      final typeStr = d.type?.name ?? 'unknown';
      final extra = d.diastolic != null ? ' 舒张压=${d.diastolic}' : '';
      setState(() => _data.insert(0, '[$typeStr] ${d.value}$extra'));
      if (_data.length > 50) _data.removeLast();
    });
  }

  Future<void> _start(RealtimeMetric metric) async {
    // 互斥：先关当前
    if (_active != null && _active != metric) {
      await _ring.stopRealtimeMeasure(_active!);
    }
    try {
      await _ring.startRealtimeMeasure(metric);
      setState(() => _active = metric);
    } on RwfitException catch (e) {
      _showError('开启失败: ${e.message}');
    }
  }

  Future<void> _stop() async {
    if (_active == null) return;
    try {
      await _ring.stopRealtimeMeasure(_active!);
      setState(() => _active = null);
    } on RwfitException catch (e) {
      _showError('关闭失败: ${e.message}');
    }
  }

  void _showError(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    if (_active != null) _ring.stopRealtimeMeasure(_active!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('实时测量')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _active != null ? '当前测量: ${_active!.name}' : '未开启测量',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in RealtimeMetric.values)
                ChoiceChip(
                  label: Text(m.name),
                  selected: _active == m,
                  onSelected: (_) => _start(m),
                ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _active != null ? _stop : null,
            child: const Text('停止测量'),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: _data.length,
              itemBuilder: (_, i) =>
                  ListTile(dense: true, title: Text(_data[i])),
            ),
          ),
        ],
      ),
    );
  }
}
