import '../../core/declarative/declarative_module_parser.dart';
import 'declarative_app_module.dart';

List<DeclarativeAppModule> buildBuiltinDeclarativeModules() {
  const parser = DeclarativeModuleParser();
  return [
    DeclarativeAppModule(parser.parse({
      'formatVersion': 1,
      'manifest': {
        'id': 'app.views.today',
        'version': '1.0.0',
        'coreApi': '1',
        'requiresCapabilities': ['tasks.query', 'tasks.command', 'ui.registry'],
        'permissions': ['tasks.read', 'tasks.write', 'ui.register'],
      },
      'pages': [
        {
          'id': 'home',
          'title': '今天',
          'icon': 'today',
          'quickAdd': true,
          'quickAddDefaults': {'plannedDate': r'$today'},
          'view': 'todayTasks',
        }
      ],
      'views': [
        {
          'id': 'todayTasks',
          'source': 'task.list',
          'filter': {
            'all': [
              {'field': 'deleted', 'op': 'eq', 'value': false},
              {'field': 'archived', 'op': 'eq', 'value': false},
              {'field': 'parentTaskId', 'op': 'isNull'},
              {'field': 'completed', 'op': 'eq', 'value': false},
              {
                'any': [
                  {'field': 'dueDate', 'op': 'lte', 'value': r'$today'},
                  {'field': 'plannedDate', 'op': 'eq', 'value': r'$today'},
                ]
              },
            ]
          },
          'emptyText': '暂无今天待办或逾期任务',
        }
      ],
    })),
    DeclarativeAppModule(parser.parse({
      'formatVersion': 1,
      'manifest': {
        'id': 'app.views.inbox',
        'version': '1.0.0',
        'coreApi': '1',
        'requiresCapabilities': ['tasks.query', 'tasks.command', 'ui.registry'],
        'permissions': ['tasks.read', 'tasks.write', 'ui.register'],
      },
      'pages': [
        {
          'id': 'home',
          'title': '收件箱',
          'icon': 'inbox',
          'quickAdd': true,
          'view': 'inboxTasks',
        }
      ],
      'views': [
        {
          'id': 'inboxTasks',
          'source': 'task.list',
          'filter': {
            'all': [
              {'field': 'deleted', 'op': 'eq', 'value': false},
              {'field': 'archived', 'op': 'eq', 'value': false},
              {'field': 'parentTaskId', 'op': 'isNull'},
              {'field': 'completed', 'op': 'eq', 'value': false},
              {'field': 'projectId', 'op': 'isNull'},
            ]
          },
          'emptyText': '收件箱为空',
        }
      ],
    })),
  ];
}
