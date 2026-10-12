import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:task_app/core/module_host/host_providers.dart';
import 'package:task_app/core/ui/page_context_validation.dart';
import 'package:task_app/core/ui/ui_composition.dart';

void main() {
  test(
    'legacy IDs do not infer entity ownership or access the module host',
    () async {
      var hostReads = 0;
      final container = ProviderContainer(
        overrides: [
          moduleHostProvider.overrideWith((ref) async {
            hostReads++;
            throw StateError('No module host is available');
          }),
        ],
      );
      addTearDown(container.dispose);
      final provider = pageContextValidityProvider(
        const PageContext(taskId: 'unknown', projectId: 'unknown'),
      );
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final valid = await container.read(provider.future);
      expect(valid, isTrue);
      expect(hostReads, 0);
    },
  );

  test('legacy named IDs and generic parameters have the same identity', () {
    const legacy = PageContext(
      taskId: 'task-a',
      projectId: 'project-a',
      values: {'filter': 'active'},
    );
    const generic = PageContext(
      values: {
        'taskId': 'task-a',
        'projectId': 'project-a',
        'filter': 'active',
      },
    );
    expect(legacy, generic);
    expect(legacy.hashCode, generic.hashCode);
    expect(legacy.identity, generic.identity);
    expect(legacy.navigationIdentity, generic.navigationIdentity);
    expect(generic.taskId, 'task-a');
    expect(generic.projectId, 'project-a');
    expect(legacy.toJson(), generic.values);
    expect(generic.satisfies(['taskId', 'projectId', 'filter']), isTrue);
    expect(() => legacy.values['filter'] = 'changed', throwsUnsupportedError);
  });

  test(
    'legacy IDs override duplicate parameters at the compatibility boundary',
    () {
      final restored = PageContext.fromLayoutJson({
        'taskId': 'old-layout-task',
        'values': {'taskId': 'duplicate', 'projectId': 'generic-project'},
      });
      expect(restored.values, {
        'taskId': 'old-layout-task',
        'projectId': 'generic-project',
      });
      expect(
        restored
            .merge(
              const PageContext(
                values: {'taskId': 'new-task', 'selection': 'row-a'},
              ),
            )
            .values,
        {
          'taskId': 'new-task',
          'projectId': 'generic-project',
          'selection': 'row-a',
        },
      );
      expect(
        restored.merge(const PageContext(taskId: 'legacy-new')).taskId,
        'legacy-new',
      );
    },
  );

  test(
    'old layouts and generic entity references survive repeated round trips',
    () {
      final oldLayout = <String, Object?>{
        'placement': 'page',
        'pageId': 'third-party.board',
        'slotId': 'details',
        'order': 2,
        'taskId': 'task-a',
        'projectId': 'project-a',
        'values': {
          'filter': 'active',
          'entities': [
            {
              'moduleId': 'third-party.inventory',
              'collection': 'items',
              'id': 'item-a',
            },
          ],
        },
      };
      final mount = UiMount.fromJson(oldLayout);
      expect(mount.toJson(), oldLayout);
      expect(UiMount.fromJson(mount.toJson()), mount);
      expect(mount.context.values['taskId'], 'task-a');
      expect(
        mount.context.toJson()['entities'],
        (oldLayout['values'] as Map)['entities'],
      );

      const generic = UiMount(
        context: PageContext(
          values: {
            'taskId': 'task-a',
            'projectId': 'project-a',
            'filter': 'active',
          },
        ),
      );
      final restored = UiMount.fromJson(generic.toJson());
      expect(restored, generic);
      expect(restored.toJson(), generic.toJson());
      expect(generic.toJson(), {
        'placement': 'main',
        'order': 0,
        'taskId': 'task-a',
        'projectId': 'project-a',
        'values': {'filter': 'active'},
      });
    },
  );

  test(
    'navigation identity excludes runtime parameters for both input forms',
    () {
      const legacy = PageContext(
        taskId: 'task-a',
        values: {'selectedDate': '2026-10-01', 'filter': 'active'},
      );
      const generic = PageContext(
        values: {
          'taskId': 'task-a',
          'selectedDate': '2026-10-02',
          'filter': 'active',
        },
      );
      expect(legacy.navigationIdentity, generic.navigationIdentity);
      expect(legacy.identity, isNot(generic.identity));
      expect(generic.satisfies(['missing']), isFalse);
      expect(
        const PageContext(values: {'empty': ''}).satisfies(['empty']),
        isFalse,
      );
    },
  );
}
