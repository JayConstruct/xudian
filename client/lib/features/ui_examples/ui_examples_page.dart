import 'package:flutter/material.dart';

import '../../app/design_system.dart';
import '../../core/ui/ui_annotation.dart';

enum _ExampleSection { tasks, inputs, feedback, dialogs }

class UiExamplesPage extends StatefulWidget {
  const UiExamplesPage({super.key, this.onOpenComposition});

  final void Function(BuildContext context)? onOpenComposition;

  @override
  State<UiExamplesPage> createState() => _UiExamplesPageState();
}

class _UiExamplesPageState extends State<UiExamplesPage> {
  static const _tasks = [
    (id: 'plan', title: '规划周末出行', subtitle: '计划今天 · 高优先级'),
    (id: 'read', title: '阅读一章新书', subtitle: '学习 · 普通优先级'),
    (id: 'done', title: '整理桌面', subtitle: '日常整理 · 普通优先级'),
  ];
  final _title = TextEditingController(text: '准备一次周末出行');
  final _notes = TextEditingController(text: '输入、选择和提交都只用于演示。');
  final _formKey = GlobalKey<FormState>();
  final _completed = <String>{'done'};
  final _tags = <String>{'学习'};
  _ExampleSection _section = _ExampleSection.tasks;
  bool _onlyPending = false;
  bool _enabled = false;
  int _priority = 1;
  int _feedback = 0;
  double _progress = 0.4;
  DateTime? _plannedDate;
  String _lastAction = '尚未操作';
  int _resetCount = 0;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _reset() {
    _formKey.currentState?.reset();
    _title.text = '准备一次周末出行';
    _notes.text = '输入、选择和提交都只用于演示。';
    setState(() {
      _completed
        ..clear()
        ..add('done');
      _tags
        ..clear()
        ..add('学习');
      _section = _ExampleSection.tasks;
      _onlyPending = false;
      _enabled = false;
      _priority = 1;
      _feedback = 0;
      _progress = 0.4;
      _plannedDate = null;
      _lastAction = '尚未操作';
      _resetCount++;
    });
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _surface(String title, Widget child) => UiAnnotation(
    id: 'app.ui.examples.${_section.name}.$title',
    name: title,
    moduleId: 'app.ui.examples',
    purpose: '本地交互示例',
    child: ContentSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          child,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListView(
    key: const ValueKey('ui-examples-list'),
    padding: EdgeInsets.fromLTRB(
      16,
      8,
      16,
      WorkspaceContentInsets.bottomOf(context) + 24,
    ),
    children: [
      SectionHeading(
        title: '交互组件示例',
        action: TextButton.icon(
          onPressed: _reset,
          icon: const Icon(Icons.restart_alt_rounded),
          label: const Text('重置示例'),
        ),
      ),
      const ContentSurface(
        padding: EdgeInsets.all(18),
        child: Text(
          '点击控件体验交互，所有操作只修改本页演示数据，不影响真实任务。'
          '\n这是客户端组件示例，不代表声明式模块已支持全部控件。',
        ),
      ),
      const SizedBox(height: 16),
      if (widget.onOpenComposition != null)
        OutlinedButton.icon(
          onPressed: () => widget.onOpenComposition!(context),
          icon: const Icon(Icons.account_tree_outlined),
          label: const Text('页面槽位与跨模块嵌套示例'),
        ),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final section in _ExampleSection.values)
            ChoiceChip(
              label: Text(switch (section) {
                _ExampleSection.tasks => '任务卡片',
                _ExampleSection.inputs => '输入控件',
                _ExampleSection.feedback => '状态反馈',
                _ExampleSection.dialogs => '弹窗操作',
              }),
              selected: section == _section,
              onSelected: (_) => setState(() => _section = section),
            ),
        ],
      ),
      const SizedBox(height: 16),
      switch (_section) {
        _ExampleSection.tasks => _taskExamples(),
        _ExampleSection.inputs => _inputExamples(),
        _ExampleSection.feedback => _feedbackExamples(),
        _ExampleSection.dialogs => _dialogExamples(),
      },
    ],
  );

  Widget _taskExamples() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _surface(
        '任务概览',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TaskSummary(total: _tasks.length, completed: _completed.length),
            LinearProgressIndicator(
              value: _completed.length / _tasks.length,
              minHeight: 8,
              borderRadius: BorderRadius.circular(AppDesign.compactRadius),
            ),
            const SizedBox(height: 12),
            FilterChip(
              label: const Text('只看未完成'),
              selected: _onlyPending,
              onSelected: (value) => setState(() => _onlyPending = value),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      for (final task in _tasks)
        if (!_onlyPending || !_completed.contains(task.id)) ...[
          TaskObjectTile(
            key: ValueKey('example-task-${task.id}'),
            title: task.title,
            subtitle: Text(task.subtitle),
            completed: _completed.contains(task.id),
            onCompleted: (value) => setState(() {
              if (value == true) {
                _completed.add(task.id);
              } else {
                _completed.remove(task.id);
              }
            }),
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(task.title),
                content: Text('${task.subtitle}\n这是示例详情，不会打开或修改真实任务。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      if (_onlyPending && _completed.length == _tasks.length)
        _surface('示例任务已完成', const Text('关闭筛选或重置示例，可继续体验任务卡片。')),
    ],
  );

  Widget _inputExamples() => _surface(
    '表单与选择',
    Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _control(
            'title_input',
            '示例标题输入',
            TextFormField(
              key: const ValueKey('example-title'),
              controller: _title,
              decoration: const InputDecoration(labelText: '示例标题'),
              validator: (value) =>
                  value == null || value.trim().isEmpty ? '请输入示例标题' : null,
            ),
          ),
          const SizedBox(height: 16),
          _control(
            'notes_input',
            '多行备注输入',
            TextFormField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(labelText: '多行备注'),
            ),
          ),
          const SizedBox(height: 16),
          _control(
            'priority_select',
            '优先级选择',
            DropdownButtonFormField<int>(
              key: ValueKey('example-priority-$_resetCount'),
              initialValue: _priority,
              decoration: const InputDecoration(labelText: '单项选择'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('低优先级')),
                DropdownMenuItem(value: 1, child: Text('普通优先级')),
                DropdownMenuItem(value: 2, child: Text('高优先级')),
              ],
              onChanged: (value) => setState(() => _priority = value ?? 1),
            ),
          ),
          const SizedBox(height: 16),
          Text('多项选择', style: Theme.of(context).textTheme.labelLarge),
          Wrap(
            spacing: 8,
            children: [
              for (final tag in ['学习', '工作', '生活'])
                FilterChip(
                  label: Text(tag),
                  selected: _tags.contains(tag),
                  onSelected: (value) => setState(() {
                    if (value) {
                      _tags.add(tag);
                    } else {
                      _tags.remove(tag);
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _chooseDate,
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(
              _plannedDate == null
                  ? '选择计划日'
                  : '计划日：${_plannedDate!.year}-'
                        '${_plannedDate!.month.toString().padLeft(2, '0')}-'
                        '${_plannedDate!.day.toString().padLeft(2, '0')}',
            ),
          ),
          _control(
            'demo_switch',
            '演示开关',
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('演示开关'),
              subtitle: const Text('只切换本页状态，不发送提醒'),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
          ),
          Text('示例进度：${(_progress * 100).round()}%'),
          _control(
            'progress_slider',
            '示例进度调节',
            Slider(
              value: _progress,
              divisions: 10,
              label: '${(_progress * 100).round()}%',
              onChanged: (value) => setState(() => _progress = value),
            ),
          ),
          const SizedBox(height: 8),
          _control(
            'validate_button',
            '验证示例表单',
            FilledButton.icon(
              key: const ValueKey('example-submit'),
              onPressed: () {
                if (_formKey.currentState!.validate()) {
                  _message('示例表单已验证，未写入真实任务。');
                }
              },
              icon: const Icon(Icons.check_rounded),
              label: const Text('验证示例表单'),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _control(String id, String name, Widget child) => UiAnnotation(
    id: 'app.ui.examples.$id',
    name: name,
    moduleId: 'app.ui.examples',
    pagePath: 'app.ui.examples.page',
    purpose: '本地控件交互演示，不读写真实任务',
    child: child,
  );

  Future<void> _chooseDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _plannedDate ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (selected != null && mounted) {
      setState(() => _plannedDate = selected);
    }
  }

  Widget _feedbackExamples() => _surface(
    '页面状态',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          children: [
            for (final entry in ['空状态', '加载中', '错误', '成功'].asMap().entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: _feedback == entry.key,
                onSelected: (_) => setState(() => _feedback = entry.key),
              ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 280,
          child: WorkspaceContentInsets(
            bottom: 0,
            child: switch (_feedback) {
              0 => const WorkspaceEmptyState(
                title: '暂无示例内容',
                subtitle: '空状态应告诉用户当前情况和下一步操作。',
              ),
              1 => const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('加载动画演示，不执行网络请求'),
                  ],
                ),
              ),
              2 => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 36),
                    const SizedBox(height: 12),
                    const Text('示例加载失败'),
                    TextButton(
                      onPressed: () => setState(() => _feedback = 3),
                      child: const Text('重试示例'),
                    ),
                  ],
                ),
              ),
              _ => const WorkspaceEmptyState(
                icon: Icons.check_circle_outline_rounded,
                title: '示例操作成功',
                subtitle: '这是成功反馈，不代表真实任务已保存。',
              ),
            },
          ),
        ),
      ],
    ),
  );

  Widget _dialogExamples() => _surface(
    '按钮与弹窗',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('体验确认对话框、底部操作面板、消息反馈及按钮禁用状态。'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: _showConfirmation,
              icon: const Icon(Icons.rate_review_outlined),
              label: const Text('确认对话框'),
            ),
            OutlinedButton.icon(
              onPressed: _showSheet,
              icon: const Icon(Icons.vertical_align_top_rounded),
              label: const Text('底部操作面板'),
            ),
            TextButton(
              onPressed: () => _message('这是示例消息，不会保存真实任务。'),
              child: const Text('显示消息反馈'),
            ),
            const FilledButton(onPressed: null, child: Text('禁用按钮')),
          ],
        ),
        const SizedBox(height: 20),
        Text('操作结果：$_lastAction'),
      ],
    ),
  );

  Future<void> _showConfirmation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认示例操作'),
        content: const Text('这是确认流程演示，不会删除或修改真实数据。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认演示'),
          ),
        ],
      ),
    );
    if (mounted) {
      setState(() => _lastAction = confirmed == true ? '已确认演示' : '已取消演示');
    }
  }

  Future<void> _showSheet() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('示例操作面板', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('选择仅更新本页的操作结果，不安排真实任务。'),
            for (final label in ['计划今天', '安排明天', '移入项目'])
              ListTile(
                title: Text(label),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.pop(context, label),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _lastAction = '已选择“$selected”示例');
    }
  }
}
