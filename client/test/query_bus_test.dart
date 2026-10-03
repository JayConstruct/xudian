import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/contracts/query_bus.dart';
import 'package:task_app/core/modules/module_context.dart';

void main() {
  test('query bus routes authorized queries', () async {
    final bus = QueryBus();
    bus.register(
      'test.value',
      permission: 'test.read',
      handler: (_) async => 42,
    );

    final result = await bus.execute(
      ModuleContext(moduleId: 'app.test', permissions: ['test.read']),
      'test.value',
    );
    expect(result, 42);
  });

  test('query bus rejects unauthorized queries', () async {
    final bus = QueryBus();
    bus.register(
      'test.value',
      permission: 'test.read',
      handler: (_) async => 1,
    );
    await expectLater(
      bus.execute(
        ModuleContext(moduleId: 'app.test', permissions: const []),
        'test.value',
      ),
      throwsStateError,
    );
  });

  test('query bus rejects duplicate and unknown queries', () async {
    final bus = QueryBus();
    bus.register(
      'test.value',
      permission: 'test.read',
      handler: (_) async => 1,
    );
    expect(
      () => bus.register(
        'test.value',
        permission: 'test.read',
        handler: (_) async => 2,
      ),
      throwsStateError,
    );
    await expectLater(
      bus.execute(const ModuleContext.system(), 'test.missing'),
      throwsStateError,
    );
  });
}
