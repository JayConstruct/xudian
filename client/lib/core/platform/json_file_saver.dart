import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart';

/// Uses Android's document picker and the desktop system save dialog.
class JsonFileSaver {
  Future<bool> save({required String name, required String text}) async {
    final bytes = utf8.encode(text);
    if (bytes.length > 2 * 1024 * 1024) {
      throw const FormatException('配置文件超过 2 MiB，无法导出');
    }
    if (Platform.isAndroid) {
      return await const MethodChannel('xudian.host/files')
              .invokeMethod<bool>('saveText', {'name': name, 'text': text}) ??
          false;
    }
    final location = await getSaveLocation(suggestedName: name);
    if (location == null) return false;
    await XFile.fromData(
      Uint8List.fromList(bytes),
      mimeType: 'application/json',
    ).saveTo(location.path);
    return true;
  }
}
