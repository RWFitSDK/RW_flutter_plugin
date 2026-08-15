import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../demo_theme.dart';
import '../i18n.dart';

class DemoDeviceCard extends StatelessWidget {
  const DemoDeviceCard({
    super.key,
    required this.device,
    required this.connectionState,
    required this.ready,
    this.powerLevel,
    this.onTap,
  });

  final BleDevice device;
  final ConnectState connectionState;
  final bool ready;
  final int? powerLevel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final connected = ready && connectionState == ConnectState.connected;
    final stateText = switch (connectionState) {
      ConnectState.connecting => demoTr('连接中', 'Connecting'),
      ConnectState.failed => demoTr('连接失败', 'Connection failed'),
      ConnectState.connected when ready => demoTr('已连接', 'Connected'),
      _ => demoTr('未连接', 'Disconnected'),
    };
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFE4F4ED),
                ),
                child: Center(
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: DemoColors.primary, width: 7),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name.isEmpty
                          ? demoTr('RW 智能戒指', 'RW Smart Ring')
                          : device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: connected
                                ? DemoColors.primary
                                : DemoColors.secondaryText,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          stateText,
                          style: const TextStyle(
                            color: DemoColors.secondaryText,
                            fontSize: 13,
                          ),
                        ),
                        if (powerLevel != null) ...[
                          const SizedBox(width: 10),
                          Text(
                            '$powerLevel%',
                            style: const TextStyle(
                              color: DemoColors.secondaryText,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                const Icon(
                  Icons.chevron_right,
                  color: DemoColors.secondaryText,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
