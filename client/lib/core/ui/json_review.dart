import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'native_ui.dart';
import 'ui_icon.dart';

const jsonReviewPageLength = 8192;

/// A bounded probe, not a full traversal of a possibly large review payload.
/// Large values are encoded by the worker only when their view is opened.
String? smallJsonReviewText(Object? value, {int limit = 600}) {
  var remaining = limit;
  bool visit(Object? item, int depth) {
    if (depth > 32 || --remaining < 0) return false;
    if (item is String) {
      remaining -= item.length;
    } else if (item is Map) {
      for (final entry in item.entries) {
        if (!visit(entry.key, depth + 1) || !visit(entry.value, depth + 1)) {
          return false;
        }
      }
    } else if (item is List) {
      for (final child in item) {
        if (!visit(child, depth + 1)) return false;
      }
    } else if (item != null && item is! num && item is! bool) {
      return false;
    }
    return remaining >= 0;
  }

  if (!visit(value, 0)) return null;
  final text = const JsonEncoder.withIndent('  ').convert(value);
  return text.length <= limit ? text : null;
}

/// Encoding and splitting run together in compute for large inputs. Every page
/// is bounded, even for a single long JSON string. Joining is lossless.
List<String> prepareJsonReview(Object? value) {
  final text = const JsonEncoder.withIndent('  ').convert(value);
  final pages = <String>[];
  for (var start = 0; start < text.length;) {
    var end = (start + jsonReviewPageLength).clamp(0, text.length);
    if (end < text.length) {
      final newline = text.lastIndexOf('\n', end - 1);
      if (newline >= start + jsonReviewPageLength ~/ 2) {
        end = newline + 1;
      } else if (text.codeUnitAt(end - 1) >= 0xd800 &&
          text.codeUnitAt(end - 1) <= 0xdbff &&
          text.codeUnitAt(end) >= 0xdc00 &&
          text.codeUnitAt(end) <= 0xdfff) {
        end--;
      }
    }
    pages.add(text.substring(start, end));
    start = end;
  }
  return pages;
}

String _joinJsonReview(List<String> pages) => pages.join();

/// The value is a review snapshot. Once prepared, display and full copy use the
/// same pages; rebuilding, folding or selecting a page never encodes it again.
class JsonReviewContent extends StatefulWidget {
  const JsonReviewContent({
    super.key,
    required this.value,
    this.prepare,
    this.onReadyChanged,
  });
  final Object? value;
  final ValueChanged<bool>? onReadyChanged;
  @visibleForTesting
  final Future<List<String>> Function(Object?)? prepare;

  @override
  State<JsonReviewContent> createState() => _JsonReviewContentState();
}

class _JsonReviewContentState extends State<JsonReviewContent> {
  List<String>? pages;
  int page = 0, generation = 0;
  bool copying = false;
  String? error, copyMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant JsonReviewContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.value, widget.value) ||
        oldWidget.prepare != widget.prepare) {
      _load();
    }
  }

  Future<void> _load() async {
    final request = ++generation;
    pages = null;
    page = 0;
    copying = false;
    error = null;
    copyMessage = null;
    _reportReady(false, request);
    try {
      if (widget.prepare == null) {
        final short = smallJsonReviewText(widget.value, limit: 4096);
        if (short != null) {
          pages = [short];
          _reportReady(true, request);
          return;
        }
      }
      final prepared =
          await (widget.prepare?.call(widget.value) ??
              compute(prepareJsonReview, widget.value));
      if (!mounted || request != generation) return;
      setState(() => pages = List.unmodifiable(prepared));
      _reportReady(true, request);
    } catch (_) {
      if (mounted && request == generation) {
        setState(() => error = '无法显示完整详情，请重试。');
      }
    }
  }

  void _reportReady(bool ready, int request) {
    if (widget.onReadyChanged == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && request == generation) widget.onReadyChanged?.call(ready);
    });
  }

  Future<void> _copy() async {
    if (copying || pages == null) return;
    final request = generation, snapshot = pages!;
    setState(() {
      copying = true;
      copyMessage = null;
    });
    try {
      final text = snapshot.length == 1
          ? snapshot.single
          : await compute(_joinJsonReview, snapshot);
      if (!mounted || request != generation) return;
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted && request == generation) {
        setState(() => copyMessage = '已复制完整详情');
      }
    } catch (_) {
      if (mounted && request == generation) {
        setState(() => copyMessage = '复制失败，请重试');
      }
    } finally {
      if (mounted && request == generation) setState(() => copying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(error!),
          TextButton(
            onPressed: () => setState(() {
              _load();
            }),
            child: const Text('重试加载详情'),
          ),
        ],
      );
    }
    if (pages == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('正在准备完整详情…'),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            TextButton.icon(
              onPressed: copying ? null : _copy,
              icon: const UiIcon(Icons.copy_all_rounded, size: 16),
              label: Text(copying ? '正在复制…' : '复制完整详情'),
            ),
            if (copyMessage != null) Text(copyMessage!),
          ],
        ),
        if (pages!.length > 1)
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('第 ${page + 1} / ${pages!.length} 段'),
              TextButton(
                onPressed: page == 0 ? null : () => setState(() => page--),
                child: const Text('上一段'),
              ),
              TextButton(
                onPressed: page + 1 == pages!.length
                    ? null
                    : () => setState(() => page++),
                child: const Text('下一段'),
              ),
            ],
          ),
        SelectableText(
          pages![page],
          key: ValueKey(page),
          scrollPhysics: const NeverScrollableScrollPhysics(),
        ),
      ],
    );
  }
}

class JsonReviewSection extends StatefulWidget {
  const JsonReviewSection({
    super.key,
    required this.title,
    required this.value,
    this.prepare,
  });
  final String title;
  final Object? value;
  @visibleForTesting
  final Future<List<String>> Function(Object?)? prepare;

  @override
  State<JsonReviewSection> createState() => _JsonReviewSectionState();
}

class _JsonReviewSectionState extends State<JsonReviewSection> {
  bool opened = false, expanded = false;

  @override
  void didUpdateWidget(covariant JsonReviewSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!expanded && !identical(oldWidget.value, widget.value)) opened = false;
  }

  @override
  Widget build(BuildContext context) => NativeUi(
    child: ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: Text(widget.title),
      maintainState: true,
      onExpansionChanged: (value) {
        expanded = value;
        if (expanded && !opened) setState(() => opened = true);
      },
      children: [
        if (opened)
          JsonReviewContent(value: widget.value, prepare: widget.prepare),
      ],
    ),
  );
}
