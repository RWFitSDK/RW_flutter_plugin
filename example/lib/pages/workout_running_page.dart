import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../demo_controller.dart';
import '../demo_theme.dart';
import '../i18n.dart';
import 'workout_types.dart';

/// 实时运动页，对应 Android Demo 的 WorkoutRunningActivity。
class WorkoutRunningPage extends StatefulWidget {
  const WorkoutRunningPage({
    required this.controller,
    required this.initialState,
    super.key,
  });

  final DemoController controller;
  final WorkoutState initialState;

  @override
  State<WorkoutRunningPage> createState() => _WorkoutRunningPageState();
}

class _WorkoutRunningPageState extends State<WorkoutRunningPage>
    with WidgetsBindingObserver {
  RwfitBle get _ring => widget.controller.ring;

  StreamSubscription<WorkoutRealtimeData>? _realtimeSub;
  StreamSubscription<ConnectStateEvent>? _connectSub;

  late WorkoutState _state;
  WorkoutRealtimeData? _data;
  bool _busy = false;
  bool _realtimeEnabled = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _state = widget.initialState;
    WidgetsBinding.instance.addObserver(this);
    _realtimeSub = _ring.onWorkoutRealtimeData.listen((data) {
      if (mounted) setState(() => _data = data);
    });
    _connectSub = _ring.onConnectState.listen((event) {
      if (event.state == ConnectState.disconnected ||
          event.state == ConnectState.failed) {
        _leaveWorkoutFlow();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _setRealtimeEnabled(true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_setRealtimeEnabled(true, showError: false));
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_setRealtimeEnabled(false, showError: false));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _realtimeSub?.cancel();
    _connectSub?.cancel();
    if (_realtimeEnabled) {
      unawaited(_disableRealtimeOnDispose());
    }
    super.dispose();
  }

  Future<void> _disableRealtimeOnDispose() async {
    try {
      await _ring.setWorkoutRealtimeEnabled(false);
    } catch (_) {
      // 页面销毁或设备断开时无需再向 UI 报错。
    }
  }

  void _leaveWorkoutFlow() {
    if (!mounted || _leaving) return;
    _leaving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  Future<void> _setRealtimeEnabled(
    bool enabled, {
    bool showError = true,
  }) async {
    if (_leaving || _realtimeEnabled == enabled) return;
    try {
      await _ring.setWorkoutRealtimeEnabled(enabled);
      if (mounted) setState(() => _realtimeEnabled = enabled);
    } on RwfitException catch (error) {
      if (showError) {
        _showMessage(
          '${demoTr('实时数据开关失败', 'Failed to enable live data')}: '
          '[${error.code}] ${error.message}',
        );
      }
    } catch (error) {
      if (showError) {
        _showMessage(
          '${demoTr('实时数据开关失败', 'Failed to enable live data')}: $error',
        );
      }
    }
  }

  Future<void> _control(WorkoutControlType controlType) async {
    if (_busy || _leaving) return;
    setState(() => _busy = true);
    try {
      await _ring.controlWorkout(_state.sportType, controlType);
      if (controlType == WorkoutControlType.end) {
        await _finishWorkout();
        return;
      }
      final state = await _ring.getWorkoutState();
      if (mounted) setState(() => _state = state);
    } on RwfitException catch (error) {
      _showMessage(
        '${demoTr('运动控制失败', 'Workout control failed')}: '
        '[${error.code}] ${error.message}',
      );
    } catch (error) {
      _showMessage('${demoTr('运动控制失败', 'Workout control failed')}: $error');
    } finally {
      if (mounted && !_leaving) setState(() => _busy = false);
    }
  }

  Future<void> _finishWorkout() async {
    String message;
    try {
      final reports = await _ring.getWorkoutReports();
      message =
          '${demoTr('运动已结束，已同步', 'Workout ended; synced')} '
          '${reports.length} ${demoTr('条历史报告', 'reports')}';
    } on RwfitException catch (error) {
      message =
          '${demoTr('运动已结束，报告同步失败', 'Workout ended; report sync failed')}: '
          '[${error.code}] ${error.message}';
    } catch (error) {
      message =
          '${demoTr('运动已结束，报告同步失败', 'Workout ended; report sync failed')}: '
          '$error';
    }
    if (!mounted || _leaving) return;
    Navigator.of(context).pop(message);
  }

  void _showMessage(String message) {
    if (!mounted || _leaving) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String get _durationText {
    final duration = _data?.duration ?? 0;
    final hours = duration ~/ 3600;
    final minutes = (duration % 3600) ~/ 60;
    final seconds = duration % 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final canPause =
        _state.controlType == WorkoutControlType.start ||
        _state.controlType == WorkoutControlType.resume;
    final canResume = _state.controlType == WorkoutControlType.pause;

    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: Text(demoTr('实时运动数据', 'Live workout data'))),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                _overviewCard(),
                SectionHeading(demoTr('运动数据', 'Workout data')),
                _metricGrid(data),
                SectionHeading(demoTr('运动控制', 'Workout controls')),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        if (canPause)
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _control(WorkoutControlType.pause),
                              icon: const Icon(Icons.pause),
                              label: Text(demoTr('暂停', 'Pause')),
                            ),
                          ),
                        if (canResume)
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () => _control(WorkoutControlType.resume),
                              icon: const Icon(Icons.play_arrow),
                              label: Text(demoTr('继续', 'Resume')),
                            ),
                          ),
                        if (canPause || canResume) const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: DemoColors.danger,
                              side: const BorderSide(color: Color(0x55D84B4B)),
                            ),
                            onPressed: _busy
                                ? null
                                : () => _control(WorkoutControlType.end),
                            icon: const Icon(Icons.stop),
                            label: Text(demoTr('结束', 'End')),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (_busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x33FFFFFF),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _overviewCard() {
    final paused = _state.controlType == WorkoutControlType.pause;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: DemoColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.directions_run,
                    color: DemoColors.primary,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        workoutTypeName(_state.sportType),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${demoTr('运动类型', 'Workout type')} ID ${_state.sportType}',
                        style: const TextStyle(
                          color: DemoColors.secondaryText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (paused ? const Color(0xFFF29B4B) : DemoColors.primary)
                            .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    paused ? demoTr('已暂停', 'Paused') : demoTr('进行中', 'Active'),
                    style: TextStyle(
                      color: paused
                          ? const Color(0xFFD47B20)
                          : DemoColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              _durationText,
              style: const TextStyle(
                color: DemoColors.text,
                fontSize: 38,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              demoTr('运动时长', 'Duration'),
              style: const TextStyle(color: DemoColors.secondaryText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metricGrid(WorkoutRealtimeData? data) => LayoutBuilder(
    builder: (context, constraints) {
      const spacing = 10.0;
      final width = (constraints.maxWidth - spacing) / 2;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          _metricCard(
            width,
            demoTr('步数', 'Steps'),
            '${data?.steps ?? 0}',
            Icons.directions_walk,
          ),
          _metricCard(
            width,
            demoTr('距离', 'Distance'),
            '${((data?.distance ?? 0) / 1000).toStringAsFixed(2)} km',
            Icons.route_outlined,
          ),
          _metricCard(
            width,
            demoTr('卡路里', 'Calories'),
            '${((data?.calorie ?? 0) / 1000).toStringAsFixed(1)} kcal',
            Icons.local_fire_department_outlined,
          ),
          _metricCard(
            width,
            demoTr('心率', 'Heart rate'),
            '${data?.heartRate ?? 0} bpm',
            Icons.favorite_outline,
          ),
        ],
      );
    },
  );

  Widget _metricCard(double width, String label, String value, IconData icon) =>
      SizedBox(
        width: width,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: DemoColors.primary),
                const SizedBox(height: 12),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: const TextStyle(
                    color: DemoColors.secondaryText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
