import '../ui/native_ui.dart';
import '../ui/ui_motion.dart';
import '../ui/script_content_widgets.dart';
import '../ui/script_form_controls.dart';
import '../ui/ui_icon.dart';
import '../ui/ui_icons.dart' show appIconData;

import 'package:flutter/material.dart';

import 'module_package.dart';
import '../ui/ui_component.dart';
import '../ui/temporal_input.dart';
import '../ui/input_validation.dart';
import '../ui/json_review.dart';
import '../../app/design_system.dart';
import '../../features/settings/settings_widgets.dart'
    show SettingsGroupSurface, SettingsSheet;
import 'data_change_review.dart';
import 'review_widgets.dart';
import 'plan_confirmation.dart';

Future<bool> reviewDialog(
  BuildContext context,
  String title,
  Object? details, {
  PlanConfirmation? confirmation,
  bool packageReview = false,
  String Function(String)? moduleName,
}) async {
  // Keep the frozen plan and its field comparisons for this dialog's lifetime.
  final summary = DataChangeSummary.tryParse(details);
  if (!packageReview &&
      (summary != null || confirmation != null ||
          details is Map && (details.containsKey('writes') || details.containsKey('planId')))) {
    var ready = false;
    return await showDialog<bool>(
          context: context,
          barrierColor: AppDesign.modalBarrier(Theme.of(context)),
          animationStyle: AppMotion.dialogStyle(context),
          builder: (context) => UiPackScope(
            defaultOnly: true,
            child: NativeUi(
              child: CompactDialogMotion(
                child: summary == null
                    ? StatefulBuilder(
                        builder: (context, setState) => ReviewDialog(
                          title: '确认变更',
                          confirmLabel: '确认',
                          onConfirm: ready
                              ? () => Navigator.pop(context, true)
                              : null,
                          children: [
                            _reviewContent(
                              details,
                              null,
                              onReadyChanged: (value) =>
                                  setState(() => ready = value),
                            ),
                          ],
                        ),
                      )
                    : confirmation != null
                    ? _CompactPlanReview(
                        confirmation: confirmation,
                        summary: summary,
                      )
                    : _FrozenChangeDialog(
                        summary: summary,
                        moduleName: moduleName,
                      ),
              ),
            ),
          ),
        ) ??
        false;
  }
  var rawReady = false;
  return await showDialog<bool>(
        context: context,
        builder: (context) => UiPackScope(
          defaultOnly: true,
          child: NativeUi(
            child: StatefulBuilder(
              builder: (context, setState) => AlertDialog(
                titlePadding: AppDesign.dialogTitlePadding,
                contentPadding: AppDesign.dialogContentPadding,
                actionsPadding: AppDesign.dialogActionsPadding,
                title: Text(title),
                content: SizedBox(
                  width: 700,
                  child: SingleChildScrollView(
                    child: _reviewContent(
                      details,
                      summary,
                      onReadyChanged: (ready) =>
                          setState(() => rawReady = ready),
                    ),
                  ),
                ),
                actions: [
                  NativeUi(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消'),
                    ),
                  ),
                  NativeUi(
                    child: FilledButton(
                      onPressed: summary != null || rawReady
                          ? () => Navigator.pop(context, true)
                          : null,
                      child: const Text('确认'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ) ??
      false;
}

class _FrozenChangeDialog extends StatelessWidget {
  const _FrozenChangeDialog({required this.summary, this.moduleName});
  final DataChangeSummary summary;
  final String Function(String)? moduleName;

  @override
  Widget build(BuildContext context) {
    final changes = summary.records.where(
      (record) => record.kind != DataChangeKind.unchanged,
    );
    final counts = <String, int>{};
    for (final record in changes) {
      counts.update(record.action, (value) => value + 1, ifAbsent: () => 1);
    }
    final names = summary.moduleIds.map((id) => moduleName?.call(id) ?? id);
    return ReviewDialog(
      title: '确认变更',
      confirmLabel: '确认变更',
      onConfirm: () => Navigator.pop(context, true),
      children: [
        ReviewSubject(
          title: names.isEmpty ? '本次操作' : names.join('、'),
          subtitle: counts.isEmpty
              ? '没有实际数据变化'
              : counts.entries.map((e) => '${e.key} ${e.value} 项').join(' · '),
          icon: Icons.edit_note_outlined,
        ),
        if (changes.isNotEmpty)
          ReviewFacts(
            title: '受影响的记录',
            emphasizedTitle: '删除',
            items: [
              for (final record in changes.take(20))
                (title: record.action, subtitle: record.label),
              if (changes.length > 20)
                (title: '其他记录', subtitle: '${changes.length - 20} 项'),
            ],
          ),
      ],
    );
  }
}

class _CompactPlanReview extends StatefulWidget {
  const _CompactPlanReview({required this.confirmation, required this.summary});
  final PlanConfirmation confirmation;
  final DataChangeSummary summary;
  @override
  State<_CompactPlanReview> createState() => _CompactPlanReviewState();
}

class _CompactPlanReviewState extends State<_CompactPlanReview> {
  bool acknowledged = false;
  @override
  Widget build(BuildContext context) {
    final options = widget.confirmation;
    final deletions = widget.summary.count(DataChangeKind.delete);
    final dialog = ReviewDialog(
      title: options.title,
      confirmLabel: options.confirmLabel,
      onConfirm: options.acknowledgement != null && !acknowledged
          ? null
          : () => Navigator.pop(context, true),
      children: [
        if (options.subject != null)
          ReviewSubject(
            title: options.subject!,
            subtitle: options.message,
            icon: appIconData(options.icon) ?? Icons.event_note_outlined,
          )
        else
          Text(options.message),
        if (options.items.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: ReviewFacts(title: options.section, items: options.items),
          ),
        if (options.section != null && options.items.isEmpty)
          ReviewNotice(options.section!),
        if (options.notice != null)
          ReviewNotice(options.notice!, icon: Icons.info_outline),
        if (deletions > 0)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              '将删除 $deletions 条记录，请核对后确认。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (options.acknowledgement != null)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(options.acknowledgement!),
            value: acknowledged,
            onChanged: (value) => setState(() => acknowledged = value == true),
          ),
      ],
    );
    return dialog;
  }
}

Widget _reviewContent(
  Object? details,
  DataChangeSummary? summary, {
  required ValueChanged<bool> onReadyChanged,
}) {
  if (summary != null) return DataChangeReview(summary: summary);
  return Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (details is Map && details.containsKey('writes'))
        const Text('无法生成可靠的数据摘要，请核对以下原始详情。'),
      JsonReviewContent(value: details, onReadyChanged: onReadyChanged),
    ],
  );
}

class HostFormDialog extends StatefulWidget {
  const HostFormDialog({
    super.key,
    required this.title,
    required this.fields,
    this.description,
    this.submitLabel = '继续',
    this.presentation,
    this.fullWidthActions = false,
  });
  final String title;
  final String? description, presentation;
  final String submitLabel;
  final bool fullWidthActions;
  final List<Map<String, Object?>> fields;
  @override
  State<HostFormDialog> createState() => _HostFormDialogState();
}

class _HostFormDialogState extends State<HostFormDialog> {
  final controllers = <String, TextEditingController>{};
  final selections = <String, String?>{};
  final booleans = <String, bool>{};
  final multiples = <String, Set<String>>{};
  final errors = <String, String>{};
  final ranges = <String, Object?>{};
  bool get instantSelection =>
      widget.fields.length == 1 &&
      widget.fields.single['type'] == 'select' &&
      widget.fields.single['presentation'] == 'grid' &&
      widget.fields.single['submitOnSelect'] == true;
  @override
  void initState() {
    super.initState();
    for (final field in widget.fields) {
      final key = field['key'] as String;
      if (field['type'] == 'select') {
        final value = field['value'];
        selections[key] =
            (field['options'] as List? ?? []).any(
              (o) => object(o)['value'] == value,
            )
            ? value as String?
            : null;
      } else if (field['type'] == 'boolean') {
        booleans[key] = field['value'] == true;
      } else if (field['type'] == 'multiSelect') {
        multiples[key] = (field['value'] is List ? field['value'] as List : [])
            .cast<String>()
            .toSet();
      } else if (field['type'] == 'dateRange') {
        ranges[key] = field['value'];
      } else {
        controllers[key] = TextEditingController(
          text: '${field['value'] ?? ''}',
        );
      }
    }
  }

  @override
  void dispose() {
    for (final c in controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void submit() {
    final result = <String, Object?>{
      ...selections,
      ...booleans,
      ...ranges,
      for (final e in multiples.entries) e.key: e.value.toList(),
    };
    errors.clear();
    for (final field in widget.fields) {
      final key = field['key'] as String, type = field['type'];
      final text = controllers[key]?.text;
      if (text != null) result[key] = text;
      if (field['normalizeToMonday'] == true && type == 'date') {
        final date = parseInputDate(text);
        if (date != null) {
          result[key] = formatInputDate(
            date.subtract(Duration(days: date.weekday - DateTime.monday)),
          );
        }
      }
      if (field['required'] == true &&
          (result[key] == null ||
              result[key] == '' ||
              result[key] is List && (result[key] as List).isEmpty)) {
        errors[key] = '请填写此项';
      }
      if (type == 'number') {
        final value = num.tryParse(text ?? '');
        final error = validateNumberInput(
          text ?? '',
          integer: field['integer'] == true,
          min: field['min'] as num?,
          max: field['max'] as num?,
        );
        if (value == null || error != null) {
          errors[key] = error ?? '请输入有效数字';
        } else {
          result[key] = value;
        }
      }
      if (_temporalKind(type) case final kind?) {
        final error = validateTemporalInput(
          kind,
          result[key],
          minDate: field['minDate'] as String?,
          maxDate: field['maxDate'] as String?,
          legacyDateTime: true,
        );
        if (error != null) errors[key] = error;
      }
      if (field['maxLength'] is int &&
          (text?.length ?? 0) > (field['maxLength'] as int)) {
        errors[key] = '内容超过长度限制';
      }
    }
    if (errors.isNotEmpty) {
      setState(() {});
      return;
    }
    Navigator.pop(context, result);
  }

  TemporalInputKind? _temporalKind(Object? type) => switch (type) {
    'date' => TemporalInputKind.date,
    'time' => TemporalInputKind.time,
    'datetime' => TemporalInputKind.dateTime,
    'dateRange' => TemporalInputKind.dateRange,
    _ => null,
  };

  Widget _selectList(Map<String, Object?> field, String key) {
    final options = (field['options'] as List? ?? []).map(object);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (field['label'] case final String label when label.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label, style: Theme.of(context).textTheme.labelMedium),
          ),
        SettingsGroupSurface(
          children: [
            for (final option in options)
              ListTile(
                leading: switch (appIconData(option['icon'])) {
                  final icon? => ScriptGlyph(
                    icon: icon,
                    tone: 'muted',
                    surface: true,
                    surfaceSize: 34,
                  ),
                  null => null,
                },
                title: Text('${option['label']}'),
                subtitle: switch (option['subtitle']) {
                  final String subtitle => Text(subtitle),
                  _ => null,
                },
                trailing: selections[key] == option['value']
                    ? UiIcon(
                        Icons.check_rounded,
                        color: scheme.primary,
                        size: 18,
                      )
                    : null,
                selected: selections[key] == option['value'],
                selectedColor: scheme.onSurface,
                onTap: () => setState(() {
                  selections[key] = option['value'] as String;
                  errors.remove(key);
                }),
              ),
          ],
        ),
        if (errors[key] case final String error)
          Text(error, style: TextStyle(color: scheme.error)),
      ],
    );
  }

  Widget _field(Map<String, Object?> field) {
    final key = field['key'] as String;
    final label = '${field['label']}';
    final labeled = field['presentation'] == 'labeled';
    InputDecoration decoration() =>
        (labeled
                ? AppDesign.outlinedField(context)
                : InputDecoration(labelText: label))
            .copyWith(
              errorText: errors[key],
              helperText: field['helperText'] as String?,
              helperMaxLines: 3,
            );
    if (_temporalKind(field['type']) case final kind?) {
      return TemporalInput(
        kind: kind,
        label: label,
        controller: controllers[key],
        value: ranges[key],
        errorText: errors[key],
        clearable: field['clearable'] != false,
        editable: field['editable'] != false,
        helperText: field['helperText'] as String?,
        minDate: field['minDate'] as String?,
        maxDate: field['maxDate'] as String?,
        legacyDateTime: true,
        externalLabel: labeled,
        onChanged: (value) => setState(() {
          if (kind == TemporalInputKind.dateRange) ranges[key] = value;
          if (kind == TemporalInputKind.date &&
              field['normalizeToMonday'] == true) {
            final date = parseInputDate(value);
            if (date != null) {
              controllers[key]!.text = formatInputDate(
                date.subtract(Duration(days: date.weekday - DateTime.monday)),
              );
            }
          }
          errors.remove(key);
        }),
      );
    }
    if (field['type'] == 'boolean') {
      return CheckboxListTile(
        title: Text(label),
        value: booleans[key] ?? false,
        onChanged: (value) => setState(() => booleans[key] = value == true),
      );
    }
    if (field['type'] == 'multiSelect') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in (field['options'] as List? ?? []).map(
                object,
              ))
                NativeUi(
                  child: FilterChip(
                    label: Text('${option['label']}'),
                    selected: multiples[key]!.contains(option['value']),
                    onSelected: (selected) => setState(() {
                      final value = option['value'] as String;
                      if (selected) {
                        multiples[key]!.add(value);
                      } else {
                        multiples[key]!.remove(value);
                      }
                      errors.remove(key);
                    }),
                  ),
                ),
            ],
          ),
          if (errors[key] != null)
            Text(
              errors[key]!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      );
    }
    if (field['type'] == 'select') {
      if (field['presentation'] == 'list') return _selectList(field, key);
      if (field['presentation'] == 'grid') {
        final options = (field['options'] as List? ?? []).map(object).toList();
        final style = Theme.of(context).textTheme.labelLarge!;
        final scaler = MediaQuery.textScalerOf(context);
        var cellWidth = 48.0;
        var cellHeight = 48.0;
        for (final option in options) {
          final painter = TextPainter(
            text: TextSpan(text: '${option['label']}', style: style),
            textDirection: Directionality.of(context),
            textScaler: scaler,
          )..layout();
          cellWidth = cellWidth < painter.width + 24
              ? painter.width + 24
              : cellWidth;
          cellHeight = cellHeight < painter.height + 24
              ? painter.height + 24
              : cellHeight;
          painter.dispose();
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final columns = ((constraints.maxWidth + 8) / (cellWidth + 8))
                .floor()
                .clamp(1, 7);
            final width = (constraints.maxWidth - 8 * (columns - 1)) / columns;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in options)
                      SizedBox(
                        width: width,
                        height: cellHeight,
                        child: Semantics(
                          label: '$label ${option['label']}',
                          selected: selections[key] == option['value'],
                          child: NativeUi(
                            child: FilledButton.tonal(
                              style: FilledButton.styleFrom(
                                padding: EdgeInsets.zero,
                                shape: AppDesign.smoothShape(radius: 14),
                                backgroundColor:
                                    selections[key] == option['value']
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest,
                                foregroundColor:
                                    selections[key] == option['value']
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                              onPressed: () {
                                setState(() {
                                  selections[key] = option['value'] as String;
                                  errors.remove(key);
                                });
                                if (instantSelection) submit();
                              },
                              child: Text('${option['label']}'),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (errors[key] != null)
                  Text(
                    errors[key]!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            );
          },
        );
      }
      final dropdown = DropdownButtonFormField<String>(
        borderRadius: AppDesign.selectionBorderRadius,
        initialValue: selections[key],
        isExpanded: true,
        decoration: decoration(),
        items: [
          for (final option in (field['options'] as List? ?? []).map(object))
            DropdownMenuItem(
              value: option['value'] as String,
              child: Text(
                '${option['label']}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (value) => setState(() {
          selections[key] = value;
          errors.remove(key);
        }),
      );
      return labeled
          ? ScriptFieldLabel(label: label, child: dropdown)
          : dropdown;
    }
    final multiline = field['type'] == 'multiline';
    final maxLines = multiline
        ? (field['maxLines'] as int? ?? 10).clamp(1, 10)
        : 1;
    final input = TextField(
      controller: controllers[key],
      readOnly: field['editable'] == false,
      obscureText: field['type'] == 'secret',
      enableSuggestions: field['type'] != 'secret',
      autocorrect: field['type'] != 'secret',
      minLines: multiline
          ? (field['minLines'] as int? ?? 3).clamp(1, maxLines)
          : 1,
      maxLines: maxLines,
      keyboardType: field['type'] == 'number'
          ? TextInputType.numberWithOptions(
              decimal: field['integer'] != true,
              signed: true,
            )
          : null,
      decoration: decoration(),
      onChanged: (_) => setState(() => errors.remove(key)),
    );
    return labeled ? ScriptFieldLabel(label: label, child: input) : input;
  }

  Iterable<Widget> _fieldRows({required double spacing}) sync* {
    final fields = widget.fields;
    for (var i = 0; i < fields.length; i++) {
      final field = fields[i];
      if (field['summary'] case {
        'title': final String title,
        'subtitle': final String subtitle,
        'icon': final String icon,
      }) {
        yield ReviewSubject(
          title: title,
          subtitle: subtitle,
          icon: appIconData(icon) ?? Icons.info_outline,
        );
      }
      if (field['section'] case final String section) {
        yield Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            section,
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(color: AppDesign.muted(context)),
          ),
        );
      }
      Widget control = _fieldWrap(field, _field(field));
      if (field['row'] is String &&
          i + 1 < fields.length &&
          fields[i + 1]['row'] == field['row'] &&
          fields[i + 1]['section'] == null &&
          fields[i + 1]['summary'] == null) {
        final second = fields[++i];
        final left = control, right = _fieldWrap(second, _field(second));
        control = LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth <
                MediaQuery.textScalerOf(context).scale(235)) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  left,
                  SizedBox(height: spacing),
                  right,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: left),
                const SizedBox(width: 10),
                Expanded(child: right),
              ],
            );
          },
        );
      }
      yield Padding(
        padding: EdgeInsets.only(bottom: spacing),
        child: control,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final native = AlertDialog(
      titlePadding: AppDesign.dialogTitlePadding,
      contentPadding: AppDesign.dialogContentPadding,
      actionsPadding: AppDesign.dialogActionsPadding,
      title: Text(widget.title),
      content: SizedBox(
        width: 540,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.description != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: Text(widget.description!),
                ),
              ..._fieldRows(spacing: 14),
            ],
          ),
        ),
      ),
      actions: [
        NativeUi(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
        ),
        if (!instantSelection)
          NativeUi(
            child: FilledButton(
              onPressed: submit,
              child: Text(widget.submitLabel),
            ),
          ),
      ],
    );
    final cancel = NativeUi(
      child: OutlinedButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
    );
    final confirm = NativeUi(
      child: FilledButton(onPressed: submit, child: Text(widget.submitLabel)),
    );
    if (widget.presentation == 'sheet') {
      final expanded = widget.fullWidthActions && !instantSelection;
      return SettingsSheet(
        title: Text(widget.title),
        content: native.content!,
        expandedActions: expanded,
        showClose: expanded,
        actions: expanded ? [cancel, confirm] : native.actions!,
      );
    }
    if (widget.presentation == 'page') {
      return Dialog.fullscreen(
        child: DetailPage(
          title: widget.title,
          maxBodyWidth: 740,
          minHeaderHeight: widget.fullWidthActions ? 65 : null,
          settingsStyle: widget.fullWidthActions,
          leading: IconButton(
            tooltip: '取消',
            icon: const UiIcon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    widget.fullWidthActions ? 4 : 20,
                    20,
                    16,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (widget.description != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: Text(widget.description!),
                        ),
                      ..._fieldRows(spacing: widget.fullWidthActions ? 12 : 20),
                    ],
                  ),
                ),
              ),
              if (widget.fullWidthActions) const Divider(height: 1),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  10,
                  20,
                  widget.fullWidthActions ? 12 : 20,
                ),
                child: widget.fullWidthActions
                    ? Row(
                        spacing: 10,
                        children: [
                          Expanded(child: cancel),
                          Expanded(child: confirm),
                        ],
                      )
                    : confirm,
              ),
            ],
          ),
        ),
      );
    }
    final form = UiComponent(
      ref: 'ui.page.form@1',
      props: {'title': widget.title},
      slots: {
        'fields': native.content!,
        'actions': Wrap(spacing: 8, children: native.actions!),
      },
      fallback: native,
    );
    final dialog = UiComponent(
      ref: 'ui.dialog@1',
      props: {'title': widget.title},
      slots: {'content': form},
      fallback: form,
    );
    return widget.presentation == 'compact'
        ? CompactDialogMotion(child: dialog)
        : dialog;
  }

  Widget _fieldWrap(Map<String, Object?> field, Widget native) {
    final ref = switch (field['type']) {
      'boolean' => 'ui.checkbox@1',
      'select' => 'ui.select@1',
      'multiSelect' => 'ui.multiSelect@1',
      'number' => 'ui.numberInput@1',
      'date' => 'ui.dateInput@1',
      'datetime' => 'ui.dateTimeInput@1',
      'time' => 'ui.timeInput@1',
      'dateRange' => 'ui.dateRangeInput@1',
      _ => 'ui.input@1',
    };
    return UiComponent(
      key: ValueKey(field['key']),
      ref: ref,
      props: {'label': field['label'], 'key': field['key']},
      slots: {'control': native},
      fallback: native,
      defaultOnly: field['type'] == 'secret',
    );
  }
}
