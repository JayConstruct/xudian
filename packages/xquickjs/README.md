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

See `docs/MODULE_SDK.md` and real-engine `client/test/script_worker_test.dart`.
