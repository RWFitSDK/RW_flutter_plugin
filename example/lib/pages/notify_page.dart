import 'dart:io';

import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../widgets/result_tile.dart';

/// 消息推送 / 通知开关页：
/// - Android: pushMessage（APP 主动推消息到设备）
/// - iOS: setNotificationSwitch / getNotificationSwitch（ANCS 转发开关）
class NotifyPage extends StatefulWidget {
  const NotifyPage({super.key});

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
      '推送消息',
      () => _ring.pushMessage({
        'appId': 'com.rwfit.demo',
        'title': '测试标题',
        'content': '这是一条测试消息',
        'msgType': 1,
      }),
    );
  }

  // ---- iOS 专用 ----

  Future<void> _getSwitch() async {
    await _run('获取通知开关', () async {
      final s = await _ring.getNotificationSwitch();
      return s.toString();
    });
  }

  Future<void> _setSwitch() async {
    // 示例：开启微信、QQ、来电、短信通知
    await _run(
      '设置通知开关',
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
    return Scaffold(
      appBar: AppBar(title: const Text('消息/通知')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAndroid ? '当前平台: Android' : '当前平台: iOS',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  isAndroid
                      ? 'Android 通过 pushMessage 主动推送消息到设备显示'
                      : 'iOS 通过 ANCS 转发系统通知，这里设置哪些 App 的通知转发',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (isAndroid)
                      FilledButton.tonal(
                        onPressed: _pushMessage,
                        child: const Text('推送测试消息'),
                      ),
                    if (!isAndroid) ...[
                      FilledButton.tonal(
                        onPressed: _getSwitch,
                        child: const Text('获取通知开关'),
                      ),
                      FilledButton.tonal(
                        onPressed: _setSwitch,
                        child: const Text('设置通知开关'),
                      ),
                    ],
                    // 两端都可调用对方的方法（no-op 返回成功），演示不会报错
                    FilledButton.tonal(
                      onPressed: () => _run(
                        '跨平台调用(no-op)',
                        isAndroid
                            ? () => _ring.getNotificationSwitch()
                            : () => _ring.pushMessage({
                                'appId': 'test',
                                'title': 'test',
                                'content': 'test',
                              }),
                      ),
                      child: Text(
                        isAndroid ? 'iOS方法(no-op)' : 'Android方法(no-op)',
                      ),
                    ),
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
