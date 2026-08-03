import 'dart:io';

import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../support_menu.dart';
import '../i18n.dart';
import '../widgets/result_tile.dart';

/// 消息推送 / 通知开关页：
/// - Android: pushMessage（APP 主动推消息到设备）
/// - iOS: setNotificationSwitch / getNotificationSwitch（ANCS 转发开关）
class NotifyPage extends StatefulWidget {
  const NotifyPage({super.key, required this.capabilities});

  final DemoCapabilities capabilities;

  @override
  State<NotifyPage> createState() => _NotifyPageState();
}

class _NotifyPageState extends State<NotifyPage> {
  final _ring = RwfitBle.instance;
  final _results = <String>[];

  void _log(String s) => setState(() => _results.insert(0, s));

  Future<void> _run(String label, Future<dynamic> Function() fn) async {
    try {
      final r = await fn();
      _log('$label ✓ ${r ?? ''}');
    } on RwfitException catch (e) {
      _log('$label ✗ [${e.code}] ${e.message}');
    } catch (e) {
      _log('$label ✗ $e');
    }
  }

  // ---- Android 专用 ----

  Future<void> _pushMessage() async {
    await _run(
      demoTr('推送消息', 'Send message'),
      () => _ring.pushMessage({
        'appId': 'com.rwfit.demo',
        'title': demoTr('测试标题', 'Test title'),
        'content': demoTr('这是一条测试消息', 'This is a test message'),
        'msgType': 1,
      }),
    );
  }

  // ---- iOS 专用 ----

  Future<void> _getSwitch() async {
    await _run(demoTr('获取通知开关', 'Get notification settings'), () async {
      final s = await _ring.getNotificationSwitch();
      return s.toString();
    });
  }

  Future<void> _setSwitch() async {
    // 示例：开启微信、QQ、来电、短信通知
    await _run(
      demoTr('设置通知开关', 'Set notification settings'),
      () => _ring.setNotificationSwitch({
        'isCall': true,
        'isSMS': true,
        'isQQ': true,
        'isWechat': true,
        'isWhatsapp': false,
        'isFacebook': false,
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid = Platform.isAndroid;
    final supported = widget.capabilities.has(
      isAndroid
          ? DemoCapabilityKey.pushMessage
          : DemoCapabilityKey.pushMessageSwitch,
    );
    return Scaffold(
      appBar: AppBar(title: Text(demoTr('消息/通知', 'Messages / notifications'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${demoTr('当前平台', 'Platform')}: '
                  '${isAndroid ? 'Android' : 'iOS'}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  isAndroid
                      ? demoTr(
                          'Android 通过 pushMessage 主动推送消息到设备显示',
                          'Android uses pushMessage to send messages to the device.',
                        )
                      : demoTr(
                          'iOS 通过 ANCS 转发系统通知，这里设置哪些 App 的通知转发',
                          'iOS forwards system notifications through ANCS; configure the enabled apps here.',
                        ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (isAndroid)
                      FilledButton.tonal(
                        onPressed: supported ? _pushMessage : null,
                        child: Text(
                          supported
                              ? demoTr('推送测试消息', 'Send test message')
                              : '${demoTr('推送测试消息', 'Send test message')} '
                                    '(${demoTr('不支持', 'Unsupported')})',
                        ),
                      ),
                    if (!isAndroid) ...[
                      FilledButton.tonal(
                        onPressed: supported ? _getSwitch : null,
                        child: Text(
                          supported
                              ? demoTr('获取通知开关', 'Get notification settings')
                              : '${demoTr('获取通知开关', 'Get notification settings')} '
                                    '(${demoTr('不支持', 'Unsupported')})',
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: supported ? _setSwitch : null,
                        child: Text(
                          demoTr('设置通知开关', 'Set notification settings'),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(child: ResultList(results: _results)),
        ],
      ),
    );
  }
}
