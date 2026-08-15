import 'dart:io';

import 'package:flutter/material.dart';

import '../demo_controller.dart';
import '../demo_theme.dart';
import '../health_metadata.dart';
import '../health_store.dart';
import '../i18n.dart';
import '../widgets/device_card.dart';
import 'device_page.dart';
import 'health_history_page.dart';
import 'scan_page.dart';
import 'workout_page.dart';

/// 对齐微信小程序 Demo 的首页/设备双导航壳。
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final DemoController _controller;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = DemoController()..addListener(_refreshFromController);
  }

  void _refreshFromController() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_refreshFromController);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openScan() async {
    try {
      if (Platform.isIOS) {
        await _controller.ring.iosSetBindedStatus(false);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${demoTr('准备换绑失败', 'Failed to prepare device switching')}: $error',
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ScanPage()),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(demoTr('RW 健康', 'RW Health')),
      actions: [
        TextButton(
          onPressed: context.toggleLanguage,
          child: Text(
            context.language == DemoLanguage.zh ? 'EN' : '中文',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 4),
      ],
    ),
    body: IndexedStack(
      index: _tabIndex,
      children: [
        _HomeDashboard(
          controller: _controller,
          openScan: _openScan,
          openDevice: () => setState(() => _tabIndex = 1),
        ),
        DevicePage(controller: _controller, openScan: _openScan),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tabIndex,
      onDestinationSelected: (index) => setState(() => _tabIndex = index),
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home),
          label: demoTr('首页', 'Home'),
        ),
        NavigationDestination(
          icon: const Icon(Icons.watch_outlined),
          selectedIcon: const Icon(Icons.watch),
          label: demoTr('设备', 'Device'),
        ),
      ],
    ),
  );
}

class _HomeDashboard extends StatelessWidget {
  const _HomeDashboard({
    required this.controller,
    required this.openScan,
    required this.openDevice,
  });

  final DemoController controller;
  final Future<void> Function() openScan;
  final VoidCallback openDevice;

  @override
  Widget build(BuildContext context) {
    final device = controller.device;
    final supported = demoHealthDefinitions
        .where(
          (definition) => controller.capabilities.has(definition.capabilityKey),
        )
        .toList();
    return RefreshIndicator(
      onRefresh: () => _sync(context),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            sliver: SliverList.list(
              children: [
                if (device != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Center(
                      child: Text(
                        demoTr('下拉可刷新', 'Pull down to refresh'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: DemoColors.secondaryText,
                        ),
                      ),
                    ),
                  ),
                if (device == null)
                  _unboundCard(context)
                else
                  DemoDeviceCard(
                    device: device,
                    connectionState: controller.connectionState,
                    ready: controller.ready,
                    powerLevel: controller.powerLevel,
                    onTap: openDevice,
                  ),
                SectionHeading(
                  demoTr('健康数据', 'Health data'),
                  caption: device == null ? null : _syncCaption(),
                ),
                if (controller.syncing) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: controller.syncProgress,
                      minHeight: 5,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (supported.isEmpty)
                  DemoEmptyCard(
                    title: device == null
                        ? demoTr('绑定后显示健康数据', 'Bind a ring to see health data')
                        : demoTr('暂未获得健康能力', 'No health capabilities yet'),
                    message: device == null
                        ? demoTr(
                            '首页会根据设备功能表展示计步、心率、睡眠、多运动等支持项目。',
                            'Supported health metrics appear here based on the device capability table.',
                          )
                        : demoTr(
                            '请先在设备页重新连接，获取设备功能配置表。',
                            'Reconnect on the Device tab to refresh capabilities.',
                          ),
                    action: device == null
                        ? FilledButton(
                            onPressed: openScan,
                            child: Text(demoTr('添加设备', 'Add device')),
                          )
                        : null,
                  )
                else
                  _healthGrid(context, supported),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _unboundCard(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: openScan,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFE4F4ED),
              ),
              child: const Icon(Icons.add, color: DemoColors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    demoTr('未绑定设备', 'No bound device'),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    demoTr(
                      '点击搜索并连接 RW 智能戒指',
                      'Search for and connect an RW smart ring',
                    ),
                    style: const TextStyle(color: DemoColors.secondaryText),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: DemoColors.secondaryText),
          ],
        ),
      ),
    ),
  );

  Widget _healthGrid(
    BuildContext context,
    List<DemoHealthDefinition> definitions,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 700 ? 3 : 2;
      final spacing = 12.0;
      final width = (constraints.maxWidth - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final definition in definitions)
            SizedBox(
              width: width,
              child: _HealthCard(
                definition: definition,
                record: controller.latestFor(definition.type),
                onTap: () {
                  if (definition.type == HealthTypeId.workout) {
                    if (!controller.connected) {
                      _toast(
                        context,
                        demoTr('请先连接设备', 'Connect the device first'),
                      );
                      return;
                    }
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WorkoutPage(controller: controller),
                      ),
                    );
                    return;
                  }
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HealthHistoryPage(
                        controller: controller,
                        definition: definition,
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      );
    },
  );

  Future<void> _sync(BuildContext context) async {
    if (controller.device == null) {
      _toast(context, demoTr('请先绑定设备', 'Bind a device first'));
      return;
    }
    if (controller.syncing) return;
    try {
      await controller.syncAllHealthData();
      if (context.mounted) {
        _toast(context, demoTr('同步完成', 'Sync complete'));
      }
    } catch (error) {
      if (context.mounted) {
        _toast(context, '${demoTr('同步失败', 'Sync failed')}: $error');
      }
    }
  }

  String? _syncCaption() {
    if (controller.syncing) {
      return demoTr(
        '正在同步 ${(controller.syncProgress * 100).round()}%',
        'Syncing ${(controller.syncProgress * 100).round()}%',
      );
    }
    final time = controller.lastSyncAt;
    if (time == null) return null;
    return demoTr(
      '上次同步 ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
      'Last sync ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
    );
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard({
    required this.definition,
    required this.record,
    required this.onTap,
  });

  final DemoHealthDefinition definition;
  final DemoHealthRecord? record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isWorkout = definition.type == HealthTypeId.workout;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      definition.title,
                      style: const TextStyle(color: DemoColors.secondaryText),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: DemoColors.secondaryText,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                isWorkout
                    ? demoTr('选择运动', 'Choose workout')
                    : record?.valueText ?? demoTr('暂无数据', 'No data'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                isWorkout
                    ? demoTr('点击进入运动页面', 'Open workout page')
                    : record == null
                    ? demoTr('点击查看历史', 'View history')
                    : _relativeTime(record!.measuredAtSec),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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

  String _relativeTime(int timestampSec) {
    if (timestampSec <= 0) return demoTr('点击查看历史', 'View history');
    final value = DateTime.fromMillisecondsSinceEpoch(timestampSec * 1000);
    final difference = DateTime.now().difference(value);
    if (difference.inMinutes < 1) return demoTr('刚刚', 'Just now');
    if (difference.inHours < 1) {
      return demoTr(
        '${difference.inMinutes} 分钟前',
        '${difference.inMinutes} min ago',
      );
    }
    if (difference.inDays < 1) {
      return demoTr(
        '${difference.inHours} 小时前',
        '${difference.inHours} hr ago',
      );
    }
    return '${value.month}/${value.day} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  }
}
