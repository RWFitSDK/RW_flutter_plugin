import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../i18n.dart';
import 'workout_types.dart';

/// 实时运动页，对应 Android Demo 的 WorkoutRunningActivity。
class WorkoutRunningPage extends StatefulWidget {
  const WorkoutRunningPage({required this.initialState, super.key});

  final WorkoutState initialState;

  @override
  State<WorkoutRunningPage> createState() => _WorkoutRunningPageState();
}

class _WorkoutRunningPageState extends State<WorkoutRunningPage>
    with WidgetsBindingObserver {
  final _ring = RwfitBle.instance;
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
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${demoTr('类型', 'Type')}: '
                '${workoutTypeName(_state.sportType)} (${_state.sportType})',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              _metric(demoTr('时间', 'Time'), _durationText),
              _metric(demoTr('步数', 'Steps'), '${data?.steps ?? 0}'),
              _metric(
                demoTr('距离', 'Distance'),
                '${((data?.distance ?? 0) / 1000).toStringAsFixed(2)} Km',
              ),
              _metric(
                demoTr('卡路里', 'Calories'),
                '${((data?.calorie ?? 0) / 1000).toStringAsFixed(1)} KCal',
              ),
              _metric(
                demoTr('心率', 'Heart rate'),
                '${data?.heartRate ?? 0} bpm',
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.tonal(
                    onPressed: _busy
                        ? null
                        : () => _control(WorkoutControlType.end),
                    child: Text(demoTr('结束', 'End')),
                  ),
                  if (canPause)
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _control(WorkoutControlType.pause),
                      child: Text(demoTr('暂停', 'Pause')),
                    ),
                  if (canResume)
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _control(WorkoutControlType.resume),
                      child: Text(demoTr('继续', 'Resume')),
                    ),
                ],
              ),
              if (_busy) ...[
                const SizedBox(height: 24),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label, style: Theme.of(context).textTheme.titleMedium),
          ),
          Expanded(
            child: Text(value, style: Theme.of(context).textTheme.titleMedium),
          ),
        ],
      ),
    );
  }
}
