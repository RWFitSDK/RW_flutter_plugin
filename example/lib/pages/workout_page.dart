import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import 'workout_running_page.dart';
import 'workout_types.dart';

/// 多运动类型页，对应 Android Demo 的 WorkoutTypeActivity。
class WorkoutPage extends StatefulWidget {
  const WorkoutPage({super.key});

  @override
  State<WorkoutPage> createState() => _WorkoutPageState();
}

class _WorkoutPageState extends State<WorkoutPage> {
  final _ring = RwfitBle.instance;
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
    setState(() => _busy = true);
    try {
      final state = await _ring.getWorkoutState();
      if (state.isRunning) {
        await _openRunningPage(state);
      }
    } on RwfitException catch (error) {
      _showMessage('查询运动状态失败：[${error.code}] ${error.message}');
    } finally {
      if (mounted && !_leaving) setState(() => _busy = false);
    }
  }

  Future<void> _selectWorkout(int sportType) async {
    if (_busy || _leaving) return;
    setState(() => _busy = true);
    try {
      var state = await _ring.getWorkoutState();
      if (!state.isRunning) {
        await _ring.controlWorkout(sportType, WorkoutControlType.start);
        state = await _ring.getWorkoutState();
      }
      if (!state.isRunning) {
        throw StateError('设备未进入运动状态');
      }
      await _openRunningPage(state);
    } on RwfitException catch (error) {
      _showMessage('开始运动失败：[${error.code}] ${error.message}');
    } catch (error) {
      _showMessage('开始运动失败：$error');
    } finally {
      if (mounted && !_leaving) setState(() => _busy = false);
    }
  }

  Future<void> _openRunningPage(WorkoutState state) async {
    if (!mounted || _leaving) return;
    final message = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => WorkoutRunningPage(initialState: state),
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
        title: const Text('选择运动类型'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _openCurrentWorkout,
            tooltip: '查询当前运动',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView.separated(
            itemCount: workoutTypeNames.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final sportType = workoutTypeStart + index;
              return ListTile(
                leading: CircleAvatar(child: Text('$sportType')),
                title: Text(workoutTypeNames[index]),
                trailing: const Icon(Icons.chevron_right),
                enabled: !_busy,
                onTap: _busy ? null : () => _selectWorkout(sportType),
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
}
