import 'package:flutter_test/flutter_test.dart';
import 'package:xquickjs/xquickjs.dart';

void main() {
  test('native worker executes package ESM, Chinese and asynchronous host promises', () async {
    final worker = JavaScriptWorker({
      'main.js': "import {data} from '@xudian/sdk'; import {text} from './text.js'; export async function test() { return text + (await data.get('things','1')).name; }",
      'text.js': "export const text = '你好，';",
    }, host: (method, args) async => {'name': '序点'});
    addTearDown(worker.close);
    expect(await worker.load('main.js'), true);
    expect(await worker.invoke('test', {}), '你好，序点');
  });
  test(
    'nested ESM resolves parent imports inside package and rejects escape',
    () async {
      final worker = JavaScriptWorker({
        'main.js': "export {value} from './nested/value.js';",
        'nested/value.js': "import {text} from '../shared.js'; export function value(){ return text; }",
        'shared.js': "export const text='包内父目录';",
      }, host: (_, _) async => null);
      addTearDown(worker.close);
      await worker.load('main.js');
      expect(await worker.invoke('value', {}), '包内父目录');
      final escape = JavaScriptWorker({
        'main.js': "import '../outside.js';",
      }, host: (_, _) async => null);
      addTearDown(escape.close);
      await expectLater(escape.load('main.js'), throwsStateError);
    },
  );
  test(
    'infinite loop interrupted on native worker without blocking Dart',
    () async {
      final worker = JavaScriptWorker({
        'main.js': 'export function loop() { while(true) {} }',
      }, host: (_, _) async => null);
      addTearDown(worker.close);
      await worker.load('main.js');
      final watch = Stopwatch()..start();
      await expectLater(worker.invoke('loop', {}), throwsStateError);
      expect(watch.elapsed, lessThan(const Duration(seconds: 4)));
    },
  );
  test('OS module and path traversal are unavailable', () async {
    final worker = JavaScriptWorker({
      'main.js': "import 'std';",
    }, host: (_, _) async => null);
    addTearDown(worker.close);
    await expectLater(worker.load('main.js'), throwsStateError);
  });
  test(
    'memory exhaustion, Chinese exception and explicit cancellation stay local',
    () async {
      final worker = JavaScriptWorker({
        'main.js': "export function fail(){throw new Error('中文异常');} export function allocate(){const a=[];while(true)a.push(new Array(100000).fill('中文'));} export function loop(){while(true){}}",
      }, host: (_, _) async => null);
      addTearDown(worker.close);
      await worker.load('main.js');
      await expectLater(
        worker.invoke('fail', {}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('中文异常'),
          ),
        ),
      );
      await expectLater(worker.invoke('allocate', {}), throwsStateError);
      if (!worker.closed) {
        final work = worker.invoke('loop', {});
        final expected = expectLater(work, throwsStateError);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        worker.close();
        await expected;
      }
      final other = JavaScriptWorker({
        'main.js': 'export function value(){return 42;}',
      }, host: (_, _) async => null);
      addTearDown(other.close);
      await other.load('main.js');
      expect(await other.invoke('value', {}), 42);
    },
  );
}
