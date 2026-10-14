import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ui/native_ui.dart';
import '../ui/ui_component.dart';
import '../ui/ui_design.dart';
import '../ui/ui_icon.dart';
import '../ui/ui_toast.dart';
import 'module_package.dart';
import 'host_dialogs.dart';

const moduleSourcePageLength = 8192;

/// Keep paragraphs bounded, including minified files and escaped JSON strings.
/// Splitting is lossless and never separates a UTF-16 surrogate pair.
List<String> splitModuleSource(String text) {
  if (text.isEmpty) return [''];
  final pages = <String>[];
  var start = 0;
  while (start < text.length) {
    var end = (start + moduleSourcePageLength).clamp(0, text.length);
    if (end < text.length) {
      final newline = text.lastIndexOf('\n', end - 1);
      if (newline >= start + moduleSourcePageLength ~/ 2) {
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

/// Called through compute: decoding and formatting must not block route frames.
Map<String, List<String>> prepareModuleSource(Map<String, Object?> input) => {
  'module.json': splitModuleSource(
    const JsonEncoder.withIndent('  ').convert(input['definition']),
  ),
  for (final file in object(input['files']).entries)
    if (file.key != 'module.json' && file.key != 'package.json')
      file.key: splitModuleSource(utf8.decode(file.value as List<int>)),
};

Map<String, Object?> assembleModuleSource(
  Map<String, List<String>> documents,
) => {
  'definition': object(jsonDecode(documents['module.json']!.join())),
  'files': {
    for (final file in documents.entries)
      if (file.key != 'module.json') file.key: file.value.join(),
  },
};

String _joinSource(List<String> pages) => pages.join();

List<int>? _findSource(Map<String, Object?> input) {
  final pages = input['pages'] as List<String>;
  final text = pages.join();
  final query = input['query'] as String;
  final start = input['start'] as int;
  var index = text.indexOf(query, start.clamp(0, text.length));
  if (index < 0 && start > 0) index = text.indexOf(query);
  if (index < 0) return null;
  var offset = index;
  for (var page = 0; page < pages.length; page++) {
    if (offset < pages[page].length) {
      return [page, offset, index + query.length];
    }
    offset -= pages[page].length;
  }
  return null;
}

class ModuleSourceDialog extends StatefulWidget {
  const ModuleSourceDialog({
    super.key,
    required this.loadDocuments,
    this.findSource,
  });

  final Future<Map<String, List<String>>> Function() loadDocuments;
  @visibleForTesting
  final Future<List<int>?> Function(Map<String, Object?>)? findSource;

  @override
  State<ModuleSourceDialog> createState() => _ModuleSourceDialogState();
}

class _ModuleSourceDialogState extends State<ModuleSourceDialog> {
  final editor = TextEditingController();
  final editorFocus = FocusNode();
  final search = TextEditingController();
  Map<String, List<String>>? documents;
  String selected = 'module.json';
  int page = 0, searchStart = 0, editRevision = 0, searchRequest = 0;
  bool saving = false;
  String? error, searchMessage, copyError;
  bool copying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final loaded = await widget.loadDocuments();
      if (!mounted) return;
      documents = loaded;
      editor.text = loaded[selected]!.first;
      setState(() {});
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  void dispose() {
    editor.dispose();
    editorFocus.dispose();
    search.dispose();
    super.dispose();
  }

  void _store() => documents![selected]![page] = editor.text;

  void _edit(String text) {
    editRevision++;
    searchRequest++;
    searchStart = 0;
    // Preserve even very large pastes, while keeping EditableText's next layout
    // bounded. No maxLength formatter may silently discard pasted source.
    if (text.length <= moduleSourcePageLength * 4) return;
    final fragments = splitModuleSource(text);
    var offset = editor.selection.extentOffset.clamp(0, text.length);
    var fragment = 0;
    while (fragment + 1 < fragments.length &&
        offset > fragments[fragment].length) {
      offset -= fragments[fragment++].length;
    }
    documents![selected]!.replaceRange(page, page + 1, fragments);
    setState(() {
      page += fragment;
      editor.value = TextEditingValue(
        text: fragments[fragment],
        selection: TextSelection.collapsed(offset: offset),
      );
    });
  }

  void _select(String file, int nextPage) {
    searchRequest++;
    _store();
    setState(() {
      selected = file;
      page = nextPage;
      editor.text = documents![selected]![page];
      error = null;
      copyError = null;
      searchMessage = null;
      searchStart = 0;
    });
  }

  Future<void> _save() async {
    _store();
    setState(() {
      saving = true;
      searchRequest++;
      error = null;
    });
    try {
      final result = await compute(assembleModuleSource, documents!);
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) {
        setState(() {
          saving = false;
          error = '模块定义无法解析，请检查 module.json：$e';
        });
      }
    }
  }

  Future<void> _find() async {
    if (search.text.isEmpty) return;
    _store();
    final file = selected, query = search.text, revision = editRevision;
    final request = ++searchRequest;
    final pages = documents![file]!;
    final input = <String, Object?>{
      'pages': pages,
      'query': query,
      'start': searchStart,
    };
    final result =
        await (widget.findSource?.call(input) ?? compute(_findSource, input));
    if (!mounted ||
        file != selected ||
        query != search.text ||
        revision != editRevision ||
        request != searchRequest ||
        !identical(pages, documents![file])) {
      return;
    }
    if (result == null) {
      setState(() => searchMessage = '未找到匹配内容');
      return;
    }
    _select(file, result[0]);
    searchStart = result[2];
    editor.selection = TextSelection(
      baseOffset: result[1],
      extentOffset: (result[1] + query.length).clamp(0, editor.text.length),
    );
    editorFocus.requestFocus();
  }

  Future<void> _fileAction(String action) async {
    _store();
    if (action == 'copy') {
      if (copying) return;
      final file = selected;
      setState(() {
        copying = true;
        copyError = null;
      });
      try {
        final text = await compute(_joinSource, documents![file]!);
        if (!mounted) return;
        await Clipboard.setData(ClipboardData(text: text));
        if (mounted) {
          AppToast.show(context, message: '已复制完整文件', kind: 'success');
        }
      } catch (_) {
        if (mounted) setState(() => copyError = '复制失败，请重试');
      } finally {
        if (mounted) setState(() => copying = false);
      }
    } else if (action == 'delete') {
      final removed = selected;
      _select('module.json', 0);
      setState(() => documents!.remove(removed));
    } else if (action == 'add') {
      final input = await showDialog<Map<String, Object?>>(
        context: context,
        builder: (_) => const HostFormDialog(
          title: '新增源码文件',
          submitLabel: '新增',
          fields: [
            {'key': 'path', 'label': '文件路径，例如 utils.js', 'required': true},
          ],
        ),
      );
      if (!mounted || input == null) return;
      final file = (input['path'] as String).trim();
      if (!safePath(file) ||
          file == 'package.json' ||
          documents!.containsKey(file)) {
        setState(() => error = '文件路径无效、已存在或属于保留文件');
        return;
      }
      documents![file] = [''];
      _select(file, 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = documents != null;
    return UiPackScope(
      defaultOnly: true,
      child: NativeUi(
        child: AlertDialog(
          scrollable: true,
          insetPadding: AppDesign.dialogInsets,
          titlePadding: AppDesign.dialogTitlePadding,
          contentPadding: AppDesign.dialogContentPadding,
          actionsPadding: AppDesign.dialogActionsPadding,
          title: const Text('模块定义与文件源码'),
          content: SizedBox(
            width: 760,
            height: (MediaQuery.sizeOf(context).height * .6).clamp(
              420 * MediaQuery.textScalerOf(context).scale(1).clamp(1, 2),
              840,
            ),
            child: !ready
                ? Center(
                    child: error != null
                        ? Text(error!)
                        : const CircularProgressIndicator(),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('编辑私人模块时须修改 version；保存后进行隔离预览和审核。'),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButton<String>(
                              value: selected,
                              isExpanded: true,
                              icon: const UiIcon(Icons.arrow_drop_down),
                              items: [
                                for (final file in documents!.keys)
                                  DropdownMenuItem(
                                    value: file,
                                    child: Text(
                                      file,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: saving
                                  ? null
                                  : (file) => _select(file!, 0),
                            ),
                          ),
                          PopupMenuButton<String>(
                            enabled: !saving && !copying,
                            tooltip: '文件操作',
                            icon: const UiIcon(Icons.more_vert),
                            onSelected: _fileAction,
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'copy',
                                child: Text('复制完整文件'),
                              ),
                              const PopupMenuItem(
                                value: 'add',
                                child: Text('新增文件'),
                              ),
                              if (selected != 'module.json')
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('删除文件'),
                                ),
                            ],
                          ),
                        ],
                      ),
                      TextField(
                        controller: search,
                        enabled: !saving,
                        onChanged: (_) {
                          searchStart = 0;
                          searchRequest++;
                        },
                        onSubmitted: (_) => _find(),
                        decoration: InputDecoration(
                          hintText: '在当前文件中查找',
                          isDense: true,
                          suffixIcon: IconButton(
                            tooltip: '查找下一处',
                            onPressed: saving ? null : _find,
                            icon: const UiIcon(Icons.search),
                          ),
                        ),
                      ),
                      if (searchMessage != null) Text(searchMessage!),
                      if (copyError != null)
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              copyError!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                            TextButton(
                              onPressed: copying
                                  ? null
                                  : () => _fileAction('copy'),
                              child: const Text('重试复制'),
                            ),
                          ],
                        ),
                      if (error != null)
                        Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      Expanded(
                        child: TextField(
                          key: const ValueKey('module-source-editor'),
                          controller: editor,
                          focusNode: editorFocus,
                          enabled: !saving,
                          expands: true,
                          minLines: null,
                          maxLines: null,
                          onChanged: _edit,
                          autocorrect: false,
                          enableSuggestions: false,
                          keyboardType: TextInputType.multiline,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 13,
                          ),
                          decoration: const InputDecoration(counterText: ''),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            tooltip: '上一片段',
                            onPressed: !saving && page > 0
                                ? () => _select(selected, page - 1)
                                : null,
                            icon: const UiIcon(Icons.chevron_left),
                          ),
                          Flexible(
                            child: Text(
                              '片段 ${page + 1} / ${documents![selected]!.length}',
                              textAlign: TextAlign.center,
                            ),
                          ),
                          IconButton(
                            tooltip: '下一片段',
                            onPressed:
                                !saving &&
                                    page + 1 < documents![selected]!.length
                                ? () => _select(selected, page + 1)
                                : null,
                            icon: const UiIcon(Icons.chevron_right),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: ready && !saving ? _save : null,
              child: Text(saving ? '正在解析…' : '继续审核'),
            ),
          ],
        ),
      ),
    );
  }
}
