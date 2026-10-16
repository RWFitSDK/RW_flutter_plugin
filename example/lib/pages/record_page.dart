import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:rwfit_ble/rwfit_ble.dart';

import '../demo_controller.dart';
import '../demo_theme.dart';
import '../i18n.dart';

/// 录音测试页，演示原生 Android Demo RecordingActivity 对应的接口：
/// 录音状态/开关、存储格式化、设备文件列表、下载（进度）、本地文件管理。
/// 下载与 Opus 转换由桥接层完成，完成后文件落在 App 专属 Recording 目录。
class RecordPage extends StatefulWidget {
  const RecordPage({super.key, required this.controller});

  final DemoController controller;

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  RwfitBle get _ring => widget.controller.ring;

  final _subs = <StreamSubscription>[];
  RecordStatus? _status;
  List<RecordFileItem> _deviceFiles = const [];
  List<LocalRecordFile> _localFiles = const [];

  /// fileId → 本地文件，build 中按 tile 查询，避免 O(n·m) 扫描。
  Map<int, LocalRecordFile> _localByFileId = const {};
  bool _loadingList = false;
  bool _controlling = false;
  bool _statusKnown = false;
  bool _queryingStatus = false;
  int _statusRequest = 0;
  late int _connectionGeneration;
  late bool _wasConnected;
  int? _downloadingFileId;
  double _progress = 0;
  String? _transferNote;

  @override
  void initState() {
    super.initState();
    _connectionGeneration = widget.controller.connectionGeneration;
    _wasConnected = widget.controller.connected;
    widget.controller.addListener(_onControllerChanged);
    _subs.add(
      _ring.onRecordStatus.listen((status) {
        if (!mounted || !widget.controller.connected) return;
        // 主动推送比尚未完成的查询更新，忽略旧查询的后续回执。
        _statusRequest++;
        setState(() {
          _status = status;
          _statusKnown = true;
          _queryingStatus = false;
        });
      }),
    );
    _subs.add(
      _ring.onRecordTransfer.listen((transfer) {
        if (!mounted) return;
        // 断连后桥接层仍可能完成本地落盘，本地列表不依赖 BLE 会话。
        if (transfer.complete) _refreshLocalFiles();
        if (!widget.controller.connected) return;
        if (transfer.errorCode != null) {
          setState(() {
            _downloadingFileId = null;
            _progress = 0;
            _transferNote = demoTr(
              '下载失败 code=${transfer.errorCode}',
              'Transfer failed code=${transfer.errorCode}',
            );
          });
          return;
        }
        if (!transfer.complete) {
          setState(() {
            _downloadingFileId ??= transfer.fileId;
            _progress = transfer.progress;
            _transferNote = '${transfer.received}/${transfer.fileSize} B';
          });
          return;
        }
        setState(() {
          _downloadingFileId = null;
          _progress = 1;
          _transferNote = transfer.filePath;
        });
      }),
    );
    _refreshStatus();
    _loadFileList();
  }

  @override
  void didUpdateWidget(covariant RecordPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _wasConnected = false;
      _connectionGeneration = -1;
      _onControllerChanged();
    }
  }

  void _onControllerChanged() {
    final connected = widget.controller.connected;
    final generation = widget.controller.connectionGeneration;
    final changed =
        generation != _connectionGeneration || connected != _wasConnected;
    if (!mounted || !changed) return;
    setState(() {
      _connectionGeneration = generation;
      _wasConnected = connected;
      _statusRequest++;
      _status = null;
      _statusKnown = false;
      _queryingStatus = false;
      _deviceFiles = const [];
      _loadingList = false;
      _controlling = false;
      _downloadingFileId = null;
      _progress = 0;
      _transferNote = null;
    });
    if (connected) {
      _refreshStatus();
      _loadFileList();
    }
  }

  bool _isCurrentSession(int generation) =>
      mounted &&
      widget.controller.connected &&
      generation == widget.controller.connectionGeneration;

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    if (!mounted || !widget.controller.connected || _queryingStatus) return;
    final generation = _connectionGeneration;
    final request = ++_statusRequest;
    setState(() => _queryingStatus = true);
    try {
      final status = await widget.controller.runDeviceCommand(
        _ring.getRecordStatus,
      );
      if (!_isCurrentSession(generation) || request != _statusRequest) return;
      setState(() {
        _status = status;
        _statusKnown = true;
      });
    } on Exception catch (e) {
      // 两端业务错误均通过 {code, msg} 转为 RwfitException。
      // 保留上次数据，但将状态标为未知，不能据此决定开始或停止。
      if (!_isCurrentSession(generation) || request != _statusRequest) return;
      setState(() => _statusKnown = false);
      _toast(
        '${demoTr('查询录音状态失败', 'Failed to query record status')}: ${_errText(e)}',
      );
    } finally {
      if (_isCurrentSession(generation) && request == _statusRequest) {
        setState(() => _queryingStatus = false);
      }
    }
  }

  Future<void> _toggleRecording() async {
    if (!mounted ||
        !widget.controller.connected ||
        _controlling ||
        _queryingStatus ||
        !_statusKnown ||
        _status == null) {
      return;
    }
    final generation = _connectionGeneration;
    final start = !_status!.recording;
    _statusRequest++;
    setState(() {
      _controlling = true;
      _statusKnown = false;
    });
    try {
      await widget.controller.runDeviceCommand(
        () => _ring.recordControl(start),
      );
      if (!_isCurrentSession(generation)) return;
      await _refreshStatus();
    } on Exception catch (e) {
      if (!_isCurrentSession(generation)) return;
      _toast('${demoTr('录音操作失败', 'Record control failed')}: ${_errText(e)}');
      await _refreshStatus();
    } finally {
      if (_isCurrentSession(generation)) setState(() => _controlling = false);
    }
  }

  Future<void> _loadFileList() async {
    if (_loadingList) return;
    if (!mounted) return;
    if (!widget.controller.connected) {
      await _refreshLocalFiles();
      return;
    }
    final generation = _connectionGeneration;
    setState(() => _loadingList = true);
    try {
      final results = await Future.wait([
        widget.controller.runDeviceCommand(_ring.getRecordFileList),
        _ring.getLocalRecordFileList(),
      ]);
      if (!_isCurrentSession(generation)) return;
      setState(() {
        _deviceFiles = results[0] as List<RecordFileItem>;
        _setLocalFiles(results[1] as List<LocalRecordFile>);
      });
    } on Exception catch (e) {
      if (!_isCurrentSession(generation)) return;
      _toast(
        '${demoTr('获取文件列表失败', 'Failed to load file list')}: ${_errText(e)}',
      );
    } finally {
      if (_isCurrentSession(generation)) setState(() => _loadingList = false);
    }
  }

  /// 只刷新本地文件段（下载完成/删除本地文件后），省一次设备端文件表查询。
  Future<void> _refreshLocalFiles() async {
    try {
      final files = await _ring.getLocalRecordFileList();
      if (!mounted) return;
      setState(() => _setLocalFiles(files));
    } on Exception {
      // 静默失败：本地列表刷新失败不影响已有数据，下次整体刷新会补齐。
    }
  }

  void _setLocalFiles(List<LocalRecordFile> files) {
    _localFiles = files;
    // 列表按修改时间从新到旧；同一 fileId 保留首个（最新）副本，重复下载后不指向旧文件。
    _localByFileId = {};
    for (final file in files) {
      final fileId = file.fileId;
      if (fileId != null) _localByFileId.putIfAbsent(fileId, () => file);
    }
  }

  Future<void> _download(RecordFileItem item) async {
    if (!mounted || !widget.controller.connected) return;
    final generation = _connectionGeneration;
    if (_downloadingFileId != null) {
      _toast(demoTr('已有文件在下载中', 'A download is already in progress'));
      return;
    }
    setState(() {
      _downloadingFileId = item.fileId;
      _progress = 0;
      _transferNote = demoTr(
        '开始下载 ID=${item.fileId}',
        'Starting ID=${item.fileId}',
      );
    });
    try {
      // Future 在桥接层转换并落盘后完成；进度经 onRecordTransfer 事件刷新。
      final filePath = await _ring.transferRecordFile(item.fileId);
      if (!_isCurrentSession(generation)) return;
      setState(() => _transferNote = filePath);
      _toast('${demoTr('已保存', 'Saved')}: ${_baseName(filePath)}');
    } on Exception catch (e) {
      if (!_isCurrentSession(generation)) return;
      setState(() {
        _downloadingFileId = null;
        _progress = 0;
      });
      _toast('${demoTr('下载失败', 'Transfer failed')}: ${_errText(e)}');
    }
  }

  Future<void> _deleteDeviceFile(RecordFileItem item) async {
    if (!mounted || !widget.controller.connected) return;
    final generation = _connectionGeneration;
    final confirmed = await demoConfirm(
      context,
      demoTr('从设备删除', 'Delete from device'),
      demoTr(
        '将永久删除设备文件 ID:${item.fileId}，未下载的文件无法恢复。',
        'Permanently delete device file ID:${item.fileId}? Files that have not been downloaded cannot be recovered.',
      ),
    );
    if (!confirmed || !_isCurrentSession(generation)) return;
    try {
      final result = await widget.controller.runDeviceCommand(
        () => _ring.deleteRecordFile(item.fileId),
      );
      if (!_isCurrentSession(generation)) return;
      if (result != 0) {
        _toast('${demoTr('删除失败', 'Delete failed')}: status=$result');
        return;
      }
      _toast(demoTr('已删除设备文件', 'Deleted from device'));
      _loadFileList();
    } on Exception catch (e) {
      if (!_isCurrentSession(generation)) return;
      _toast('${demoTr('删除失败', 'Delete failed')}: ${_errText(e)}');
    }
  }

  Future<void> _deleteLocalFile(LocalRecordFile file) async {
    final confirmed = await demoConfirm(
      context,
      demoTr('删除本地文件', 'Delete local file'),
      file.name,
    );
    if (!confirmed || !mounted) return;
    try {
      await File(file.path).delete();
      _toast('${demoTr('已删除', 'Deleted')}: ${file.name}');
    } catch (error) {
      _toast('${demoTr('删除失败', 'Delete failed')}: $error');
      return;
    }
    _refreshLocalFiles();
  }

  Future<void> _formatStorage() async {
    if (!mounted || !widget.controller.connected) return;
    final generation = _connectionGeneration;
    final confirmed = await demoConfirm(
      context,
      demoTr('格式化存储', 'Format storage'),
      demoTr(
        '将删除设备上全部录音文件',
        'All recording files on the device will be deleted',
      ),
    );
    if (!confirmed || !_isCurrentSession(generation)) return;
    try {
      final result = await widget.controller.runDeviceCommand(
        _ring.formatRecordStorage,
      );
      if (!_isCurrentSession(generation)) return;
      if (result != 0) {
        _toast('${demoTr('格式化失败', 'Format failed')}: status=$result');
        return;
      }
      _toast(demoTr('格式化成功', 'Format succeeded'));
      await _loadFileList();
      if (!_isCurrentSession(generation)) return;
      _refreshStatus();
    } on Exception catch (e) {
      if (!_isCurrentSession(generation)) return;
      _toast('${demoTr('格式化失败', 'Format failed')}: ${_errText(e)}');
    }
  }

  void _showDeviceFileActions(RecordFileItem item) {
    if (!widget.controller.connected) return;
    final generation = _connectionGeneration;
    final local = _localFileFor(item.fileId);
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Text(
                '${demoTr('设备文件', 'Device file')} ID:${item.fileId}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (local != null)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(demoTr('查看本地文件', 'Show local file')),
                subtitle: Text(
                  local.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _transferNote = local.path);
                },
              ),
            ListTile(
              leading: const Icon(Icons.download_outlined),
              title: Text(
                local == null
                    ? demoTr('下载文件', 'Download file')
                    : demoTr('重新下载', 'Download again'),
              ),
              onTap: () {
                Navigator.pop(context);
                if (!_isCurrentSession(generation)) return;
                _download(item);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: DemoColors.danger,
              ),
              title: Text(demoTr('从设备删除', 'Delete from device')),
              onTap: () {
                Navigator.pop(context);
                if (!_isCurrentSession(generation)) return;
                _deleteDeviceFile(item);
              },
            ),
          ],
        ),
      ),
    );
  }

  LocalRecordFile? _localFileFor(int fileId) => _localByFileId[fileId];

  String _errText(Object error) =>
      error is RwfitException ? '[${error.code}] ${error.message}' : '$error';

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.controller.connected;
    final status = _statusKnown ? _status : null;
    final recording = status?.recording ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(demoTr('录音', 'Recording'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          SectionHeading(
            demoTr('录音状态', 'Record status'),
            caption: connected
                ? null
                : demoTr('需连接设备', 'Connect the device first'),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        recording
                            ? Icons.fiber_manual_record
                            : Icons.stop_circle_outlined,
                        size: 18,
                        color: recording
                            ? DemoColors.danger
                            : DemoColors.secondaryText,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          !_statusKnown
                              ? demoTr('状态未知', 'Status unknown')
                              : recording
                              ? demoTr('录音中', 'Recording')
                              : demoTr('空闲', 'Idle'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: demoTr('刷新录音状态', 'Refresh recording status'),
                        onPressed:
                            connected && !_queryingStatus && !_controlling
                            ? _refreshStatus
                            : null,
                        icon: const Icon(Icons.refresh),
                      ),
                      Text(
                        status == null
                            ? '--'
                            : status.recording && status.startTime > 0
                            ? _deviceTime(status.startTime)
                            : '',
                        style: const TextStyle(
                          color: DemoColors.secondaryText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  if (recording && (status?.duration ?? 0) > 0) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${demoTr('已录', 'Duration')}: ${status!.duration}s'
                      '${status.startTime > 0 ? '  ·  ${_deviceTime(status.startTime)}' : ''}',
                      style: const TextStyle(
                        color: DemoColors.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    status == null
                        ? '--'
                        : '${demoTr('剩余空间', 'Storage')}: '
                              '${_fileSize(status.remainingCapacity)} / '
                              '${_fileSize(status.totalCapacity)}',
                    style: const TextStyle(
                      color: DemoColors.secondaryText,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed:
                              connected &&
                                  _statusKnown &&
                                  !_queryingStatus &&
                                  !_controlling
                              ? _toggleRecording
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: recording
                                ? DemoColors.danger
                                : null,
                          ),
                          icon: Icon(
                            recording ? Icons.stop : Icons.fiber_manual_record,
                          ),
                          label: Text(
                            !_statusKnown
                                ? demoTr('请先刷新状态', 'Refresh status first')
                                : recording
                                ? demoTr('停止录音', 'Stop recording')
                                : demoTr('开始录音', 'Start recording'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: connected ? _formatStorage : null,
                          icon: const Icon(Icons.delete_sweep_outlined),
                          label: Text(demoTr('格式化', 'Format')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SectionHeading(
            demoTr('文件列表', 'Files'),
            trailing: TextButton.icon(
              onPressed: !_loadingList ? _loadFileList : null,
              icon: _loadingList
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh),
              label: Text(demoTr('刷新', 'Refresh')),
            ),
          ),
          // 进度条只在下载中显示；提示文本（失败原因/保存路径）任何状态都要可见。
          if (_downloadingFileId != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: _progress.clamp(0, 1),
                minHeight: 7,
              ),
            ),
            const SizedBox(height: 6),
          ],
          if (_transferNote != null) ...[
            Text(
              _transferNote!,
              style: const TextStyle(
                color: DemoColors.secondaryText,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Card(
            child: Column(
              children: [
                _sectionLabel(
                  demoTr(
                    '设备录音文件 (${_deviceFiles.length})',
                    'Device record files (${_deviceFiles.length})',
                  ),
                ),
                if (_deviceFiles.isEmpty)
                  _emptyRow(demoTr('暂无设备文件', 'No device files'))
                else
                  for (var index = 0; index < _deviceFiles.length; index++) ...[
                    _deviceFileTile(_deviceFiles[index]),
                    if (index != _deviceFiles.length - 1)
                      const Divider(height: 1, indent: 52),
                  ],
                const Divider(height: 1),
                _sectionLabel(
                  demoTr(
                    '本地录音文件 (${_localFiles.length})',
                    'Local recording files (${_localFiles.length})',
                  ),
                ),
                if (_localFiles.isEmpty)
                  _emptyRow(
                    demoTr(
                      '下载完成后保存在 App 录音目录',
                      'Saved to the app Recording directory after download',
                    ),
                  )
                else
                  for (var index = 0; index < _localFiles.length; index++) ...[
                    _localFileTile(_localFiles[index]),
                    if (index != _localFiles.length - 1)
                      const Divider(height: 1, indent: 52),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          color: DemoColors.secondaryText,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    ),
  );

  Widget _emptyRow(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(color: DemoColors.secondaryText, fontSize: 13),
      ),
    ),
  );

  Widget _deviceFileTile(RecordFileItem item) {
    final downloading = _downloadingFileId == item.fileId;
    return ListTile(
      dense: true,
      leading: Icon(
        downloading ? Icons.downloading : Icons.graphic_eq,
        color: downloading ? DemoColors.primary : DemoColors.secondaryText,
      ),
      title: Text(
        'ID:${item.fileId}  ${_deviceTime(item.timestamp)}',
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${_fileSize(item.fileSize)}  ·  ${item.duration}s'
        '${_localFileFor(item.fileId) != null ? '  ·  ${demoTr('已下载', 'downloaded')}' : ''}',
        style: const TextStyle(fontSize: 12),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        color: DemoColors.secondaryText,
      ),
      onTap: widget.controller.connected
          ? () => _showDeviceFileActions(item)
          : null,
    );
  }

  Widget _localFileTile(LocalRecordFile file) => ListTile(
    dense: true,
    leading: const Icon(Icons.audio_file_outlined, color: DemoColors.primary),
    title: Text(
      file.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      // lastModified 两端桥接均为毫秒，与设备端秒级时间戳分开格式化。
      '${_fileSize(file.fileSize)}  ·  ${_localTime(file.lastModified)}',
      style: const TextStyle(fontSize: 12),
    ),
    trailing: IconButton(
      tooltip: demoTr('删除本地文件', 'Delete local file'),
      icon: const Icon(Icons.delete_outline, color: DemoColors.danger),
      onPressed: () => _deleteLocalFile(file),
    ),
  );

  String _deviceTime(int timestampSec) {
    if (timestampSec <= 0) return '-';
    return _formatDateTime(
      DateTime.fromMillisecondsSinceEpoch(timestampSec * 1000),
    );
  }

  String _localTime(int timestampMs) {
    if (timestampMs <= 0) return '-';
    return _formatDateTime(DateTime.fromMillisecondsSinceEpoch(timestampMs));
  }

  String _formatDateTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}:${two(value.second)}';
  }

  String _fileSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${bytes}B';
  }

  String _baseName(String path) {
    final index = path.lastIndexOf(Platform.pathSeparator);
    return index < 0 ? path : path.substring(index + 1);
  }
}
