String modulePermissionLabel(String permission) => switch (permission) {
  'tasks.read' => '读取任务与项目（tasks.read）',
  'tasks.write' => '创建或修改任务与项目（tasks.write）',
  'fields.write' => '修改自定义字段（fields.write）',
  'ui.register' => '添加界面入口（ui.register）',
  _ => permission,
};

String moduleResourceLabel(String kind) => switch (kind) {
  'page' => '页面（page）',
  'view' => '任务视图（view）',
  'field' => '自定义字段（field）',
  'template' => '任务模板（template）',
  'rule' => '自动化规则（rule）',
  'layout' => '布局（layout）',
  _ => kind,
};
