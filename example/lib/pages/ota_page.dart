import 'dart:async';

import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../demo_controller.dart';
import '../demo_theme.dart';
import '../i18n.dart';

/// OTA 升级页：选固件路径 → 升级 → 进度/完成事件监听。
class OtaPage extends StatefulWidget {
  const OtaPage({super.key, required this.controller});

  final DemoController controller;

  @override
  State<OtaPage> createState() => _OtaPageState();
}

class _OtaPageState extends State<OtaPage> {
  RwfitBle get _ring => widget.controller.ring;

  final _subs = <StreamSubscription>[];
  final _results = <_OtaLogEntry>[];
  final _pathController = TextEditingController();
  double _progress = 0;
  bool _upgrading = false;

  @override
  void initState() {
    super.initState();
    _subs.add(
      _ring.onOtaProgress.listen((p) {
        if (!mounted) return;
        setState(() => _progress = p);
      }),
    );
    _subs.add(
      _ring.onOtaFinish.listen((r) {
        if (!mounted) return;
        setState(() {
          _upgrading = false;
          if (r.success) _progress = 1;
        });
        if (r.success) {
          _log('${demoTr('OTA 升级成功', 'OTA upgrade succeeded')} ✓');
        } else {
          _log(
            '${demoTr('OTA 升级失败', 'OTA upgrade failed')}: code=${r.code}',
            isError: true,
          );
        }
      }),
    );
  }

  void _log(String message, {bool isError = false}) {
    if (!mounted) return;
    setState(
      () =>
          _results.insert(0, _OtaLogEntry(message: message, isError: isError)),
    );
  }

  Future<void> _startOta() async {
    if (!widget.controller.connected) {
      _log(demoTr('请先连接设备', 'Connect the device first'), isError: true);
      return;
    }
    final path = _pathController.text.trim();
    if (path.isEmpty) {
      _log(demoTr('请输入固件文件路径', 'Enter a firmware file path'), isError: true);
      return;
    }
    setState(() {
      _upgrading = true;
      _progress = 0;
    });
    try {
      await _ring.ringOta(path);
      _log(demoTr('OTA 指令已发送...', 'OTA command sent...'));
    } on RwfitException catch (e) {
      setState(() => _upgrading = false);
      _log(
        '${demoTr('OTA 失败', 'OTA failed')}: [${e.code}] ${e.message}',
        isError: true,
      );
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(demoTr('固件升级', 'Firmware upgrade'))),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        SectionHeading(
          demoTr('固件文件', 'Firmware file'),
          caption: demoTr('使用本地文件路径', 'Use a local file path'),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _pathController,
                  enabled: !_upgrading,
                  decoration: InputDecoration(
                    labelText: demoTr('固件文件路径', 'Firmware file path'),
                    hintText: '/sdcard/Download/firmware.bin',
                    prefixIcon: const Icon(Icons.description_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  demoTr(
                    'Demo 不负责导入文件，请由客户集成时提供有效路径。',
                    'File importing is handled by the integrating app. Provide a valid local path here.',
                  ),
                  style: const TextStyle(
                    color: DemoColors.secondaryText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
        SectionHeading(demoTr('升级状态', 'Upgrade status')),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _upgrading
                            ? demoTr('正在升级', 'Upgrading')
                            : demoTr('等待开始', 'Ready to start'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      '${(_progress * 100).clamp(0, 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        color: DemoColors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: _progress.clamp(0, 1),
                    minHeight: 7,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _upgrading ? null : _startOta,
                  icon: const Icon(Icons.system_update_alt),
                  label: Text(
                    _upgrading
                        ? demoTr('升级中...', 'Upgrading...')
                        : demoTr('开始 OTA', 'Start OTA'),
                  ),
                ),
              ],
            ),
          ),
        ),
        SectionHeading(demoTr('操作记录', 'Activity')),
        if (_results.isEmpty)
          DemoEmptyCard(
            title: demoTr('暂无升级记录', 'No upgrade activity'),
            message: demoTr(
              '填写固件路径并开始升级后，结果会显示在这里。',
              'Upgrade events will appear here after the process starts.',
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (var index = 0; index < _results.length; index++) ...[
                  _resultTile(_results[index]),
                  if (index != _results.length - 1)
                    const Divider(height: 1, indent: 52),
                ],
              ],
            ),
          ),
      ],
    ),
  );

  Widget _resultTile(_OtaLogEntry entry) => ListTile(
    dense: true,
    leading: Icon(
      entry.isError ? Icons.error_outline : Icons.check_circle_outline,
      color: entry.isError ? DemoColors.danger : DemoColors.primary,
    ),
    title: Text(
      entry.message,
      style: TextStyle(
        color: entry.isError ? DemoColors.danger : DemoColors.text,
      ),
    ),
  );
}

class _OtaLogEntry {
  const _OtaLogEntry({required this.message, required this.isError});

  final String message;
  final bool isError;
}
