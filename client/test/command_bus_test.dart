import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/contracts/command_bus.dart';
import 'package:task_app/core/modules/module_context.dart';

void main() {
  test('command bus routes authorized commands', () async {
    final bus = CommandBus();
    bus.register(
      'test.echo',
      permission: 'test.write',
      handler: (payload) async => payload['value'],
    );

    final result = await bus.execute(
      ModuleContext(moduleId: 'app.test', permissions: ['test.write']),
      'test.echo',
      {'value': 'ok'},
    );
    expect(result, 'ok');
  });

  test('command bus rejects unauthorized commands', () async {
    final bus = CommandBus();
    bus.register(
      'test.echo',
      permission: 'test.write',
      handler: (_) async => null,
    );
    await expectLater(
      bus.execute(
        ModuleContext(moduleId: 'app.test', permissions: const []),
        'test.echo',
      ),
      throwsStateError,
    );
  });

  test('command bus rejects duplicates and unknown commands', () async {
    final bus = CommandBus();
    bus.register(
      'test.echo',
      permission: 'test.write',
      handler: (_) async => null,
    );
    expect(
      () => bus.register(
        'test.echo',
        permission: 'test.write',
        handler: (_) async => null,
      ),
      throwsStateError,
    );
    await expectLater(
      bus.execute(const ModuleContext.system(), 'test.missing'),
      throwsStateError,
    );
  });
}
