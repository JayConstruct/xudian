import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xquickjs/xquickjs.dart';

void main() {
  test('native output notifications create no idle polling timers', () async {
    var timers = 0;
    late JavaScriptWorker worker;
    await runZoned(
      () async {
        worker = JavaScriptWorker({
          'main.js': 'export function value(){return 42;}',
        }, host: (_, _) async => null);
        await worker.load('main.js');
        final before = timers;
        await Future<void>.delayed(const Duration(milliseconds: 180));
        expect(
          timers - before,
          1,
          reason: 'Only the test wait creates a timer',
        );
        expect(await worker.invoke('value', {}), 42);
      },
      zoneSpecification: ZoneSpecification(
        createTimer: (self, parent, zone, duration, callback) {
          timers++;
          return parent.createTimer(zone, duration, callback);
        },
      ),
    );
    worker.close();
  });

  test(
    'top-level awaits execute per worker and globals remain isolated',
    () async {
      var initializations = 0;
      const scripts = {
        'main.js': """
import {clock} from '@xudian/sdk';
const initial = await clock.now();
let count = 0;
export function value(){return {initial,count:++count};}
""",
      };
      final first = JavaScriptWorker(
        scripts,
        host: (_, _) async => ++initializations,
      );
      final second = JavaScriptWorker(
        scripts,
        host: (_, _) async => ++initializations,
      );
      addTearDown(first.close);
      addTearDown(second.close);
      await first.load('main.js');
      await second.load('main.js');
      expect(initializations, 2);
      expect(await first.invoke('value', {}), {'initial': 1, 'count': 1});
      expect(await first.invoke('value', {}), {'initial': 1, 'count': 2});
      expect(await second.invoke('value', {}), {'initial': 2, 'count': 1});
    },
  );

  test('queued notifications, pending calls and late host replies survive close', () async {
    for (var iteration = 0; iteration < 100; iteration++) {
      final reply = Completer<Object?>();
      final requested = Completer<void>();
      final worker = JavaScriptWorker(
        {
          'main.js': """
import {clock} from '@xudian/sdk';
export async function waiting(){return await clock.now();}
export function burst(){for(let i=0;i<30;i++) globalThis.__send(JSON.stringify({type:'result',id:-1,value:i})); return 7;}
""",
        },
        host: (_, _) async {
          requested.complete();
          return reply.future;
        },
      );
      await worker.load('main.js');
      final waiting = worker.invoke('waiting', {});
      final waitingError = expectLater(waiting, throwsStateError);
      await requested.future;
      final burst = worker.invoke('burst', {});
      final burstResult = burst.then(
        (value) => expect(value, 7),
        onError: (Object error) => expect(error, isA<StateError>()),
      );
      // Give the native thread a chance to queue notifications while Dart is
      // still in this synchronous turn, then destroy it before callbacks drain.
      sleep(const Duration(milliseconds: 1));
      worker.close();
      reply.complete('late');
      worker.close();
      await waitingError;
      await burstResult;
    }
    await Future<void>.delayed(Duration.zero);
  });

  test(
    'notifications use the owner zone after temporary construction ends',
    () async {
      const transactionKey = #temporaryWorkerTransaction;
      final owner = Zone.current;
      final temporary = owner.fork(zoneValues: {transactionKey: true});
      final seen = <bool>[];
      final worker = temporary.run(
        () => JavaScriptWorker(
          {
            'main.js': "import {clock} from '@xudian/sdk'; await clock.now(); export async function now(){return clock.now();}",
          },
          ownerZone: owner,
          host: (_, _) async {
            seen.add(Zone.current[transactionKey] == true);
            return 1;
          },
        ),
      );
      addTearDown(worker.close);
      await temporary.run(() => worker.load('main.js'));
      expect(await temporary.run(() => worker.invoke('now', {})), 1);
      expect(seen, [false, false]);
    },
  );

  test(
    'closing from a synchronous host callback never joins a waiting Dart call',
    () async {
      late JavaScriptWorker worker;
      worker = JavaScriptWorker(
        {'main.js': "import {clock} from '@xudian/sdk'; await clock.now();"},
        host: (_, _) async {
          worker.close();
          return 1;
        },
      );
      await expectLater(worker.load('main.js'), throwsStateError);
      expect(worker.closed, isTrue);
    },
  );

  test(
    'caught host errors expose business text and retain diagnostic details',
    () async {
      const detail =
          'Bad state: Error: 撤销已停止：任务已完成\n'
          '    at batchUndo (main.js:34:375)\n';
      final worker = JavaScriptWorker({
        'main.js': """
import {services} from '@xudian/sdk';
export async function caught() {
  try { await services.prepare({},{}); }
  catch(error) { return {text:String(error),message:error.message,diagnostic:error.diagnostic,isError:error instanceof Error}; }
}
export async function uncaught() { await services.prepare({},{}); }
""",
      }, host: (_, _) async => throw StateError(detail));
      addTearDown(worker.close);
      await worker.load('main.js');
      expect(await worker.invoke('caught', {}), {
        'text': '撤销已停止：任务已完成',
        'message': '撤销已停止：任务已完成',
        'diagnostic': 'Bad state: $detail',
        'isError': true,
      });
      await expectLater(
        worker.invoke('uncaught', {}),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'provider diagnostic stack',
            contains('at batchUndo (main.js:34:375)'),
          ),
        ),
      );
    },
  );
  test(
    'idle worker wakes for concurrent invokes, delayed host replies and events',
    () async {
      final delivered = Completer<Object?>();
      final subscribed = Completer<void>();
      final reply = Completer<Object?>();
      final worker = JavaScriptWorker(
        {
          'main.js': "import {data} from '@xudian/sdk'; let value; export async function watch(){await data.watch('things',{},v=>{value=v;});} export function latest(){return value;} export async function delayed(){return data.get('things','1');} export function echo(v){return v;}",
        },
        host: (method, args) async {
          if (method == 'data.watch') {
            subscribed.complete();
            return 'subscription';
          }
          if (method == 'data.get') {
            delivered.complete();
            return reply.future;
          }
          return null;
        },
      );
      addTearDown(worker.close);
      await worker.load('main.js');
      await worker.invoke('watch', {});
      await subscribed.future;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final pending = worker.invoke('delayed', {});
      await delivered.future;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final echoes = List.generate(8, (i) => worker.invoke('echo', i));
      worker.emit('subscription', {'name': '变更'});
      reply.complete('已返回');
      expect(await pending, '已返回');
      expect(await Future.wait(echoes), List.generate(8, (i) => i));
      expect(await worker.invoke('latest', {}), {'name': '变更'});
    },
  );
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
