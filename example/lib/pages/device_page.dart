import 'dart:io';

import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../demo_controller.dart';
import '../demo_theme.dart';
import '../i18n.dart';
import '../widgets/device_card.dart';
import '../widgets/device_settings_list.dart';
import 'ota_page.dart';

class DevicePage extends StatelessWidget {
  const DevicePage({
    super.key,
    required this.controller,
    required this.openScan,
  });

  final DemoController controller;
  final Future<void> Function() openScan;

  @override
  Widget build(BuildContext context) {
    final device = controller.device;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 36),
      children: [
        Text(
          demoTr('我的设备', 'My device'),
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        Text(
          demoTr(
            '管理连接、设备信息与支持功能',
            'Manage connection, device information, and features',
          ),
          style: const TextStyle(color: DemoColors.secondaryText),
        ),
        const SizedBox(height: 20),
        if (device == null)
          _UnboundDeviceCard(onTap: openScan)
        else ...[
          DemoDeviceCard(
            device: device,
            connectionState: controller.connectionState,
            ready: controller.ready,
            powerLevel: controller.powerLevel,
          ),
          const SizedBox(height: 12),
          _connectionActions(context),
          SectionHeading(demoTr('设备信息', 'Device information')),
          _deviceInformation(context),
          SectionHeading(
            demoTr('设备功能', 'Device features'),
            caption: demoTr('按功能表显示', 'Based on capability table'),
          ),
          DeviceSettingsList(controller: controller),
        ],
        if (device == null) ...[
          const SizedBox(height: 28),
          DemoEmptyCard(
            title: demoTr('还没有绑定戒指', 'No ring is bound'),
            message: demoTr(
              '绑定后这里会根据功能配置表展示设备支持的全部设置。',
              'Supported settings appear here after a ring is connected.',
            ),
            action: FilledButton(
              onPressed: openScan,
              child: Text(demoTr('搜索设备', 'Search devices')),
            ),
          ),
        ],
      ],
    );
  }

  Widget _connectionActions(BuildContext context) => Row(
    children: [
      Expanded(
        child: controller.connected
            ? OutlinedButton(
                onPressed: () => _run(
                  context,
                  controller.disconnect,
                  success: demoTr('已断开连接', 'Disconnected'),
                ),
                child: Text(demoTr('断开连接', 'Disconnect')),
              )
            : FilledButton(
                onPressed: controller.connectionState == ConnectState.connecting
                    ? null
                    : () => _run(
                        context,
                        controller.reconnect,
                        success: demoTr('连接成功', 'Connected'),
                      ),
                child: Text(
                  controller.connectionState == ConnectState.connecting
                      ? demoTr('连接中', 'Connecting')
                      : demoTr('重新连接', 'Reconnect'),
                ),
              ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: DemoColors.danger,
            side: const BorderSide(color: Color(0x55D84B4B)),
          ),
          onPressed: () => _confirmUnbind(context),
          child: Text(demoTr('解除绑定', 'Unbind')),
        ),
      ),
    ],
  );

  Widget _deviceInformation(BuildContext context) {
    final firmware = controller.firmware;
    return Card(
      child: Column(
        children: [
          _InfoTile(
            title: demoTr('设备电量', 'Battery'),
            subtitle: demoTr('点击刷新设备信息', 'Tap to refresh'),
            value: controller.powerLevel == null
                ? '--'
                : '${controller.powerLevel}%',
            onTap: controller.connected
                ? () => _run(context, controller.refreshDeviceInfo)
                : null,
          ),
          const Divider(height: 1, indent: 16),
          _InfoTile(
            title: demoTr('设备型号', 'Device model'),
            value: firmware?.deviceClazz.isNotEmpty == true
                ? firmware!.deviceClazz
                : '--',
          ),
          const Divider(height: 1, indent: 16),
          _InfoTile(
            title: demoTr('固件版本', 'Firmware version'),
            value: firmware?.deviceNo.isNotEmpty == true
                ? firmware!.deviceNo
                : '--',
          ),
          const Divider(height: 1, indent: 16),
          _InfoTile(
            title: demoTr('SDK 版本', 'SDK version'),
            value: controller.sdkVersion ?? '--',
          ),
          const Divider(height: 1, indent: 16),
          _InfoTile(
            title: demoTr('插件版本', 'Plugin version'),
            value: controller.pluginVersion ?? '--',
          ),
          const Divider(height: 1, indent: 16),
          _InfoTile(
            title: demoTr('固件升级', 'Firmware upgrade'),
            subtitle: demoTr(
              '由客户提供固件本地路径',
              'Provide a local firmware path in your integration',
            ),
            value: controller.connected
                ? demoTr('可操作', 'Available')
                : demoTr('需连接', 'Connect first'),
            onTap: controller.connected
                ? () => _push(context, OtaPage(controller: controller))
                : null,
          ),
        ],
      ),
    );
  }

  Future<void> _confirmUnbind(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(demoTr('解除绑定', 'Unbind device')),
        content: Text(
          demoTr(
            '解除后将同时清除 Demo 当前显示的健康记录。',
            'This also clears health records currently shown in the Demo.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(demoTr('取消', 'Cancel')),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: DemoColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(demoTr('解除', 'Unbind')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await controller.unbind();
      if (!context.mounted) return;
      if (Platform.isIOS) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(demoTr('请解除系统配对', 'Remove system pairing')),
            content: Text(
              demoTr(
                '请前往 iPhone“设置 → 蓝牙”，找到该设备并选择“忽略此设备”。',
                'Open iPhone Settings → Bluetooth, find the ring, and choose Forget This Device.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(demoTr('知道了', 'OK')),
              ),
            ],
          ),
        );
      } else {
        _toast(context, demoTr('已解除绑定', 'Device unbound'));
      }
    } catch (error) {
      if (context.mounted) _toast(context, '$error');
    }
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action, {
    String? success,
  }) async {
    try {
      await action();
      if (context.mounted && success != null) _toast(context, success);
    } catch (error) {
      if (context.mounted) _toast(context, '$error');
    }
  }

  void _push(BuildContext context, Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _UnboundDeviceCard extends StatelessWidget {
  const _UnboundDeviceCard({required this.onTap});

  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
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
                    demoTr('点击搜索并连接智能戒指', 'Search for and connect a ring'),
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
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.title,
    required this.value,
    this.subtitle,
    this.onTap,
  });

  final String title;
  final String value;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 130),
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: DemoColors.secondaryText),
          ),
        ),
        if (onTap != null) const Icon(Icons.chevron_right),
      ],
    ),
    onTap: onTap,
  );
}
