# xquickjs native worker

Pinned source: quickjs-ng **v0.17.0**, upstream release commit `6d46d07`.
Upstream archive SHA-256: `559bc4c420475e55c7ab4510adbc562f55d7524d75e8e89d79ce4bb02f5687d9`.
Source: https://github.com/quickjs-ng/quickjs/releases/tag/v0.17.0
License: MIT, retained in `src/vendor/LICENSE`.

Vendored engine: quickjs.c, libregexp.c, libunicode.c, dtoa.c and their headers.
No quickjs-libc/OS module, CLI, third-party native module or bytecode loader is exposed.
`src/bridge.c` contains the app's opaque handle and bounded message queues; engine calls
run entirely on an owning pthread/Windows thread. Flutter build hooks compile the pinned
sources for the target. Linux uses GCC when no Clang toolchain is installed; other targets
use native_toolchain_c's CBuilder.

Default stack: 512 KiB. Continuous execution deadline: 1 second. Dart requests have a
10-second computation deadline. Cancellation interrupts native execution and joins the
worker. This runs in the Flutter process; it is not an OS sandbox.

The native output queue signals Dart when it changes from empty to nonempty, through
`NativeCallable.listener`. Dart drains the bounded message queue in the worker's owner
zone. The native thread only posts an asynchronous isolate notification: no engine
pointer crosses threads and no Dart code runs on the native engine thread. Idle workers
create no polling timers; host replies and subscription events use the same notification
path. Two workers still execute their own ESM initialization and retain separate globals;
activation and transaction semantics are unchanged.

Closing first marks the Dart worker closed, interrupts native execution and joins/destroys
the native worker, then closes the listener. Joining guarantees native code cannot call
the closed trampoline. Closing the listener port discards already queued notifications;
no pointer is carried by the callback. Constructor failures use the same teardown order.
The listener is created in the durable owner zone so a temporary installation transaction
cannot leak into later requests. The host continues to dispatch initialization bridges
through the active installation transaction when applicable.

From `client/`, run `dart run tool/benchmark_script_worker.dart 30` for a local real-engine
microbenchmark: construction/load with a top-level await, 12 serial host bridge calls,
and timers created during one idle second. Output is JSON in microseconds with individual
samples and nearest-rank p50/p95. It excludes application/Flutter startup and is not a device CPU,
battery or Android cold-start benchmark. Native callback scheduling still depends on the
Dart event loop; there is no fixed deadline for notification delivery.

Callback thread/lifecycle rules: [Dart NativeCallable.listener](https://api.dart.dev/dart-ffi/NativeCallable/NativeCallable.listener.html)
and [NativeCallable.close](https://api.dart.dev/dart-ffi/NativeCallable/close.html).

See `docs/MODULE_SDK.md` and real-engine `client/test/script_worker_test.dart`.
