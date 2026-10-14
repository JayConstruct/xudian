import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/ui_design.dart';

import 'collection_store.dart';

/// Trusted host appearance; module arguments cannot override native chrome.
class HostBrowserAppearance {
  HostBrowserAppearance.fromTheme(ThemeData theme)
    : values = {
        'dark': theme.brightness == Brightness.dark,
        'canvas': theme.scaffoldBackgroundColor.toARGB32(),
        'surface': theme.colorScheme.surface.toARGB32(),
        'text': theme.colorScheme.onSurface.toARGB32(),
        'muted': theme.colorScheme.onSurfaceVariant.toARGB32(),
        'primary': theme.colorScheme.primary.toARGB32(),
        'onPrimary': theme.colorScheme.onPrimary.toARGB32(),
        'input': theme.colorScheme.surfaceContainerLow.toARGB32(),
        'outline': theme.colorScheme.outlineVariant.toARGB32(),
        'error': theme.colorScheme.error.toARGB32(),
        'controlRadius': AppDesign.controlRadius,
        'dialogRadius': AppDesign.floatingRadius,
      };

  final Map<String, Object> values;
}

/// A visible, user-operated browser. Capture scripts return data, never writes.
class HostBrowser {
  HostBrowser({MethodChannel? channel, bool? available})
    : channel = channel ?? const MethodChannel('xudian.host/browser'),
      available = available ?? Platform.isAndroid;

  final MethodChannel channel;
  final bool available;
  ModuleActor? _caller;

  static Map<String, Object?> validate(Map<String, Object?> args) {
    final url = args['url'];
    final uri = url is String ? Uri.tryParse(url) : null;
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        url is! String ||
        url.length > 4096) {
      throw const FormatException('请输入有效的 HTTP 或 HTTPS 教务网址');
    }
    final script = args['script'];
    if (script is! String ||
        script.trim().isEmpty ||
        utf8.encode(script).length > 256 * 1024) {
      throw const FormatException('采集脚本为空或超过256 KiB');
    }
    return {'url': uri.toString(), 'script': script};
  }

  Future<Object?> capture(
    ModuleActor caller,
    Map<String, Object?> args, {
    HostBrowserAppearance? appearance,
  }) async {
    final request = validate(args);
    if (!available) {
      throw UnsupportedError('当前平台暂不支持内置教务浏览器，请使用拾光 JSON 文件导入');
    }
    if (_caller != null) throw StateError('另一个采集窗口尚未关闭');
    _caller = caller;
    try {
      final raw = await channel.invokeMethod<String>('capture', {
        ...request,
        'moduleId': caller.moduleId,
        if (appearance != null) 'appearance': appearance.values,
      });
      if (raw == null) return null;
      if (utf8.encode(raw).length > 2 * 1024 * 1024) {
        throw const FormatException('采集结果超过2 MiB');
      }
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic>) {
        throw const FormatException('采集结果需为 JSON 对象');
      }
      return value;
    } finally {
      _caller = null;
    }
  }

  Future<void> revoke(ModuleActor caller) async {
    if (identical(_caller, caller)) await channel.invokeMethod<void>('cancel');
  }

  Future<void> close() async {
    if (_caller != null) await channel.invokeMethod<void>('cancel');
  }
}
