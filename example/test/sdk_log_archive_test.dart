import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rwfit_ble_example/sdk_log_archive.dart';

void main() {
  late Directory sandbox;
  late Directory logs;
  late Directory temporary;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('sdk_log_archive_test_');
    logs = Directory(p.join(sandbox.path, 'logs'))..createSync();
    temporary = Directory(p.join(sandbox.path, 'cache'))..createSync();
  });

  tearDown(() => sandbox.deleteSync(recursive: true));

  Future<File?> export({
    String extension = '.log',
    String prefix = 'logger/',
  }) => exportSdkLogArchive(
    logDirectory: logs,
    temporaryDirectory: temporary,
    prefix: prefix,
    extension: extension,
  );

  File write(String root, String name, String contents) {
    final file = File(p.join(root, name));
    file.parent.createSync(recursive: true);
    return file..writeAsStringSync(contents);
  }

  test('exports nested Android logs and preserves bytes and paths', () async {
    final text = '蓝牙连接成功\n${'SDK log data\n' * 10000}';
    write(logs.path, 'devices/2026-10-27.log', text);
    final bytes = List<int>.generate(4096, (index) => index % 256);
    final product = File(p.join(logs.path, 'product', 'raw.log'));
    product.parent.createSync();
    product.writeAsBytesSync(bytes);
    write(logs.path, 'ignored.txt', 'skip');

    final zip = (await export())!;
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    expect(
      archive.map((file) => file.name),
      unorderedEquals([
        'logger/devices/2026-10-27.log',
        'logger/product/raw.log',
      ]),
    );
    expect(
      utf8.decode(archive.findFile('logger/devices/2026-10-27.log')!.content),
      text,
    );
    expect(archive.findFile('logger/product/raw.log')!.content, bytes);
    expect(await product.readAsBytes(), bytes);
  });

  test('exports iOS text logs with the SDK prefix', () async {
    write(logs.path, '2026-10-27.txt', 'iOS SDK 日志');
    write(logs.path, 'ignored.log', 'skip');

    final zip = (await export(extension: '.txt', prefix: 'sdk_logs/'))!;
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    expect(archive.single.name, 'sdk_logs/2026-10-27.txt');
    expect(utf8.decode(archive.single.content), 'iOS SDK 日志');
  });

  test('returns null for missing, empty, or nonmatching logs', () async {
    expect(await export(), isNull);
    write(logs.path, 'ignored.txt', 'skip');
    expect(await export(), isNull);
    logs.deleteSync(recursive: true);
    expect(await export(), isNull);
    expect(
      Directory(p.join(temporary.path, 'rwfit_sdk_logs')).listSync(),
      isEmpty,
    );
  });

  test('concurrent exports have distinct paths and complete ZIPs', () async {
    write(logs.path, '2026-10-27.log', 'SDK log');

    final results = await Future.wait([export(), export(), export()]);
    expect(results.map((file) => file!.path).toSet(), hasLength(3));
    for (final zip in results) {
      final archive = ZipDecoder().decodeBytes(await zip!.readAsBytes());
      expect(utf8.decode(archive.single.content), 'SDK log');
    }
  });

  test(
    'expires old exports and legacy ZIPs while preserving recent files',
    () async {
      final exports = p.join(temporary.path, 'rwfit_sdk_logs');
      final expired = write(exports, 'export_old/rwfit_sdk_log.zip', 'expired');
      final recent = write(
        exports,
        'export_recent/rwfit_sdk_log.zip',
        'recent',
      );
      final unrelated = write(exports, 'other.zip', 'keep');
      final legacy = write(
        temporary.path,
        'rwfit_sdk_log_20261020_120000.zip',
        'old',
      );
      final recentLegacy = write(
        temporary.path,
        'rwfit_sdk_log_20261027_120000.zip',
        'recent',
      );
      final otherCache = write(temporary.path, 'other_cache.zip', 'keep');
      final oldDate = DateTime.now().subtract(const Duration(days: 2));
      for (final file in [expired, legacy, unrelated, otherCache]) {
        file.setLastModifiedSync(oldDate);
      }

      // 没有新日志时也应执行清理。
      expect(await export(), isNull);
      expect(expired.parent.existsSync(), isFalse);
      expect(legacy.existsSync(), isFalse);
      for (final file in [recent, unrelated, recentLegacy, otherCache]) {
        expect(file.existsSync(), isTrue, reason: file.path);
      }
    },
  );
}
