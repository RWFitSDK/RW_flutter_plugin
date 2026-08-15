import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../demo_controller.dart';
import '../demo_theme.dart';
import '../i18n.dart';
import 'workout_running_page.dart';
import 'workout_types.dart';

/// 多运动类型页，对应 Android Demo 的 WorkoutTypeActivity。
class WorkoutPage extends StatefulWidget {
  const WorkoutPage({super.key, required this.controller});

  final DemoController controller;

  @override
  State<WorkoutPage> createState() => _WorkoutPageState();
}

class _WorkoutPageState extends State<WorkoutPage> {
  RwfitBle get _ring => widget.controller.ring;

  StreamSubscription<ConnectStateEvent>? _connectSub;

  bool _busy = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _connectSub = _ring.onConnectState.listen((event) {
      if (event.state == ConnectState.disconnected ||
          event.state == ConnectState.failed) {
        _leaveWorkoutFlow();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openCurrentWorkout();
    });
  }

  @override
  void dispose() {
    _connectSub?.cancel();
    super.dispose();
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

  Future<void> _openCurrentWorkout() async {
    if (_busy || _leaving) return;
    if (!widget.controller.connected) {
      _showMessage(demoTr('请先连接设备', 'Connect the device first'));
      return;
    }
    setState(() => _busy = true);
    try {
      final state = await _ring.getWorkoutState();
      if (state.isRunning) {
        await _openRunningPage(state);
      }
    } on RwfitException catch (error) {
      _showMessage(
        '${demoTr('查询运动状态失败', 'Failed to get workout state')}: '
        '[${error.code}] ${error.message}',
      );
    } finally {
      if (mounted && !_leaving) setState(() => _busy = false);
    }
  }

  Future<void> _selectWorkout(int sportType) async {
    if (_busy || _leaving) return;
    if (!widget.controller.connected) {
      _showMessage(demoTr('请先连接设备', 'Connect the device first'));
      return;
    }
    setState(() => _busy = true);
    try {
      var state = await _ring.getWorkoutState();
      if (!state.isRunning) {
        await _ring.controlWorkout(sportType, WorkoutControlType.start);
        state = await _ring.getWorkoutState();
      }
      if (!state.isRunning) {
        throw StateError(
          demoTr('设备未进入运动状态', 'The device did not enter workout mode'),
        );
      }
      await _openRunningPage(state);
    } on RwfitException catch (error) {
      _showMessage(
        '${demoTr('开始运动失败', 'Failed to start workout')}: '
        '[${error.code}] ${error.message}',
      );
    } catch (error) {
      _showMessage('${demoTr('开始运动失败', 'Failed to start workout')}: $error');
    } finally {
      if (mounted && !_leaving) setState(() => _busy = false);
    }
  }

  Future<void> _openRunningPage(WorkoutState state) async {
    if (!mounted || _leaving) return;
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => WorkoutRunningPage(
          controller: widget.controller,
          initialState: state,
        ),
      ),
    );
    if (message != null && mounted && !_leaving) {
      _showMessage(message);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(demoTr('选择运动类型', 'Choose workout type')),
        actions: [
          IconButton(
            onPressed: _busy ? null : _openCurrentWorkout,
            tooltip: demoTr('查询当前运动', 'Get current workout'),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            itemCount: workoutTypeNames.length + 2,
            itemBuilder: (context, index) {
              if (index == 0) return _introCard();
              if (index == 1) {
                return SectionHeading(
                  demoTr('运动类型', 'Workout types'),
                  caption: demoTr(
                    '${workoutTypeNames.length} 项',
                    '${workoutTypeNames.length} available',
                  ),
                );
              }
              final workoutIndex = index - 2;
              final sportType = workoutTypeStart + workoutIndex;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 3,
                    ),
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: DemoColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.directions_run,
                        color: DemoColors.primary,
                        size: 21,
                      ),
                    ),
                    title: Text(
                      workoutTypeNames[workoutIndex],
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'ID $sportType',
                      style: const TextStyle(
                        color: DemoColors.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: DemoColors.secondaryText,
                    ),
                    enabled: !_busy,
                    onTap: _busy ? null : () => _selectWorkout(sportType),
                  ),
                ),
              );
            },
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _introCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
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
                  demoTr('选择一项运动开始记录', 'Choose a workout to begin'),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Text(
                  demoTr(
                    '运动由戒指记录，进行中可暂停、继续或结束。',
                    'The ring records your workout. Pause, resume, or end it at any time.',
                  ),
                  style: const TextStyle(
                    color: DemoColors.secondaryText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
