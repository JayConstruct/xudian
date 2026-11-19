import 'dart:io';

import 'package:flutter/material.dart';

import '../module_catalog/module_catalog.dart';
import '../ui/native_ui.dart';
import '../ui/ui_design.dart';
import 'module_package.dart';

class ModuleDownloadDialog extends StatefulWidget {
  const ModuleDownloadDialog({
    super.key,
    required this.client,
    required this.modules,
    this.offline = false,
  });
  final ModuleCatalogClient client;
  final List<ResolvedCatalogModule> modules;
  final bool offline;
  @override
  State<ModuleDownloadDialog> createState() => _ModuleDownloadDialogState();
}

class _ModuleDownloadDialogState extends State<ModuleDownloadDialog> {
  DownloadCancellation cancellation = DownloadCancellation();
  final packages = <ScriptPackage>[];
  String? failure;
  ResolvedCatalogModule? current;
  ModuleDownloadStage stage = ModuleDownloadStage.preparing;
  int received = 0, total = 0;
  bool running = true;
  bool attemptActive = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(download);
  }

  @override
  void dispose() {
    cancellation.cancel();
    super.dispose();
  }

  Future<void> download() async {
    if (!mounted || attemptActive) return;
    attemptActive = true;
    final token = DownloadCancellation();
    setState(() {
      running = true;
      failure = null;
      cancellation = token;
    });
    try {
      for (final item in widget.modules.skip(packages.length)) {
        if (!mounted || token.isCancelled) return;
        setState(() {
          current = item;
          stage = ModuleDownloadStage.preparing;
          received = 0;
          total = item.release?.size ?? 0;
        });
        final package = await item.loadPackage(
          widget.client,
          cancellation: token,
          offline: widget.offline,
          onStage: (value) {
            if (mounted && !token.isCancelled) {
              setState(() => stage = value);
            }
          },
          onProgress: (count, size) {
            if (mounted && !token.isCancelled) {
              setState(() {
                received = count;
                total = size;
              });
            }
          },
        );
        if (!mounted || token.isCancelled) return;
        setState(() => packages.add(package));
      }
      if (mounted && !token.isCancelled) Navigator.pop(context, packages);
    } catch (error) {
      if (mounted && !token.isCancelled) {
        setState(() {
          failure =
              error is SocketException &&
                  error.message.contains('Failed host lookup')
              ? '无法解析下载服务器地址，请检查网络或 DNS 后重试。\n$error'
              : '$error';
          running = false;
        });
      }
    } finally {
      attemptActive = false;
    }
  }

  String get stageLabel => switch (stage) {
    ModuleDownloadStage.preparing => '准备下载',
    ModuleDownloadStage.downloading => '下载中',
    ModuleDownloadStage.retrying => '网络连接失败，正在等待自动重试…',
    ModuleDownloadStage.verifying => '校验中',
    ModuleDownloadStage.saving => '保存已验证模块',
    ModuleDownloadStage.ready => '准备安装',
  };

  // This measures package bytes, not verification or the install transaction.
  double? get overallProgress {
    if (widget.modules.isEmpty ||
        widget.modules.any((item) => (item.release?.size ?? 0) <= 0)) {
      return null;
    }
    final size = widget.modules.fold<int>(
      0,
      (sum, item) => sum + item.release!.size,
    );
    final complete = widget.modules
        .take(packages.length)
        .fold<int>(0, (sum, item) => sum + item.release!.size);
    return ((complete +
                (packages.length < widget.modules.length ? received : 0)) /
            size)
        .clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !running,
    child: NativeUi(
      child: AlertDialog(
        titlePadding: AppDesign.dialogTitlePadding,
        contentPadding: AppDesign.dialogContentPadding,
        actionsPadding: AppDesign.dialogActionsPadding,
        title: const Text('下载并验证模块'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  failure == null ? stageLabel : '下载或校验失败',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (current != null) Text(current!.name),
                const SizedBox(height: 8),
                if (running)
                  NativeUi(
                    child: LinearProgressIndicator(
                      value:
                          stage == ModuleDownloadStage.downloading && total > 0
                          ? (received / total).clamp(0.0, 1.0)
                          : null,
                      semanticsLabel: '当前模块：$stageLabel',
                    ),
                  ),
                const SizedBox(height: 8),
                if (stage == ModuleDownloadStage.downloading || failure != null)
                  Text(
                    total > 0
                        ? '${_readableBytes(received)} / ${_readableBytes(total)}'
                        : '已下载 ${_readableBytes(received)}',
                  ),
                Text('已完成 ${packages.length}/${widget.modules.length} 个模块'),
                if (overallProgress case final progress?) ...[
                  const SizedBox(height: 8),
                  Text('整体下载进度 ${(progress * 100).floor()}%'),
                  NativeUi(
                    child: LinearProgressIndicator(
                      value: progress,
                      semanticsLabel: '整体下载进度',
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Text('全部模块包验证完成后，将统一确认安装和权限。'),
                if (failure != null) ...[
                  const SizedBox(height: 8),
                  SelectableText(
                    failure!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const Text('已完成的模块会保留，重试将从当前模块继续。'),
                ],
                NativeUi(
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('模块与下载来源'),
                    children: [
                      for (final item in widget.modules)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${item.name} · ${item.version}'),
                              Text(item.description),
                              SelectableText(
                                item.release?.url.toString() ?? '本地已验证模块包',
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          NativeUi(
            child: TextButton(
              onPressed: () {
                cancellation.cancel();
                Navigator.pop(context);
              },
              child: Text(running ? '取消下载' : '关闭'),
            ),
          ),
          if (!running)
            NativeUi(
              child: FilledButton(onPressed: download, child: const Text('重试')),
            ),
        ],
      ),
    ),
  );
}

String _readableBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
