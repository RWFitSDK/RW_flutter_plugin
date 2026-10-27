import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

const _archiveName = 'rwfit_sdk_log.zip';

/// 在后台 isolate 中收集、压缩日志；插件目录需先在主 isolate 获取。
Future<File?> exportSdkLogArchive({
  required Directory logDirectory,
  required Directory temporaryDirectory,
  required String prefix,
  required String extension,
}) => Isolate.run(() {
  final exports = Directory(p.join(temporaryDirectory.path, 'rwfit_sdk_logs'))
    ..createSync(recursive: true);
  final cutoff = DateTime.now().subtract(const Duration(days: 1));
  _cleanExpiredArchives(exports, cutoff);
  // 同时清理旧版直接放在临时目录下的导出包。
  _cleanExpiredArchives(temporaryDirectory, cutoff, legacy: true);

  if (!logDirectory.existsSync()) return null;
  final files = logDirectory
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => p.extension(file.path) == extension)
      .toList();
  if (files.isEmpty) return null;

  // 随机目录隔离每次导出，即使并发或同一秒调用也不会覆盖文件。
  final destination = exports.createTempSync('export_');
  final zip = File(p.join(destination.path, _archiveName));
  try {
    final output = OutputFileStream(zip.path);
    try {
      final encoder = ZipEncoder()..startEncode(output);
      for (final file in files) {
        final input = InputFileStream(file.path);
        try {
          final relative = p.relative(file.path, from: logDirectory.path);
          final name = '$prefix${p.posix.fromUri(p.toUri(relative))}';
          final entry = ArchiveFile.stream(name, input)
            ..lastModTime =
                file.lastModifiedSync().millisecondsSinceEpoch ~/ 1000;
          encoder.add(entry, autoClose: false);
        } finally {
          input.closeSync();
        }
      }
      encoder.endEncode();
    } finally {
      output.closeSync();
    }
    return zip;
  } catch (_) {
    // 失败时不保留半成品，清理失败也不覆盖原始导出异常。
    try {
      destination.deleteSync(recursive: true);
    } on FileSystemException {
      // 留给后续过期清理重试。
    }
    rethrow;
  }
});

void _cleanExpiredArchives(
  Directory directory,
  DateTime cutoff, {
  bool legacy = false,
}) {
  try {
    for (final entity in directory.listSync(followLinks: false)) {
      try {
        final FileSystemEntity archive;
        if (legacy) {
          if (entity is! File ||
              !RegExp(
                r'^rwfit_sdk_log_\d{8}_\d{6}\.zip$',
              ).hasMatch(p.basename(entity.path))) {
            continue;
          }
          archive = entity;
        } else {
          if (entity is! Directory ||
              !p.basename(entity.path).startsWith('export_')) {
            continue;
          }
          final zip = File(p.join(entity.path, _archiveName));
          archive = zip.existsSync() ? zip : entity;
        }
        if (archive.statSync().modified.isBefore(cutoff)) {
          entity.deleteSync(recursive: true);
        }
      } on FileSystemException {
        // 清理尽力执行，单个旧包删除失败不影响本次分享。
      }
    }
  } on FileSystemException {
    // 清理目录暂不可读时，下次导出重试。
  }
}
