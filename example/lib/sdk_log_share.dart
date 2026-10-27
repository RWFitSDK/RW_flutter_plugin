import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'sdk_log_archive.dart';

/// RW SDK 日志导出：收集两端 SDK 落盘日志 → zip → 系统分享面板。
///
/// 路径为固定文件系统事实（path_provider 直拼），不经原生桥接：
///   iOS      {Documents}/DeviceLog/yyyy-MM-dd.txt
///   Android  {filesDir}/logger/**/yyyy-MM-dd.log
///
/// 与 SDK 日志开关无关：未开日志/没连过设备时目录为空，返回 null，
/// 由调用方提示「暂无日志」。
class SdkLogShare {
  SdkLogShare._();

  /// 收集日志打成 zip 写入临时目录；无任何日志文件返回 null。
  static Future<File?> exportZip() async {
    final Directory root;
    final String prefix;
    final String extension;
    if (Platform.isIOS) {
      final docs = await getApplicationDocumentsDirectory();
      root = Directory(p.join(docs.path, 'DeviceLog'));
      prefix = 'sdk_logs/';
      extension = '.txt';
    } else if (Platform.isAndroid) {
      // Android 上 getApplicationSupportDirectory 即 Context.getFilesDir()
      final files = await getApplicationSupportDirectory();
      root = Directory(p.join(files.path, 'logger'));
      prefix = 'logger/';
      extension = '.log';
    } else {
      return null;
    }
    final tmp = await getTemporaryDirectory();
    return exportSdkLogArchive(
      logDirectory: root,
      temporaryDirectory: tmp,
      prefix: prefix,
      extension: extension,
    );
  }

  /// 导出并拉起系统分享；返回 false = 无日志。用户取消分享不算失败。
  static Future<bool> share() async {
    final zip = await exportZip();
    if (zip == null) return false;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(zip.path, mimeType: 'application/zip')],
        title: 'RW SDK log',
      ),
    );
    return true;
  }
}
