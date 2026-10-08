import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_app/core/ui/ui_composition.dart';
import 'package:task_app/data/app_database.dart';
import 'package:task_app/features/settings/app_preferences.dart';
import 'package:task_app/features/settings/ui_layout.dart';
import 'package:task_app/features/tasks/application/providers.dart';

class _PersistenceFixture {
  _PersistenceFixture() {
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWith((ref) async => database)],
    );
  }

  final database = AppDatabase(NativeDatabase.memory());
  late final ProviderContainer container;

  Future<void> write(String key, String value) => database
      .into(database.appSettings)
      .insertOnConflictUpdate(
        AppSettingsCompanion.insert(key: key, value: value),
      );

  Future<String?> read(String key) async {
    final row = await (database.select(
      database.appSettings,
    )..where((row) => row.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> dispose() async {
    container.dispose();
    await database.close();
  }
}

Object? _reverseKeys(Object? value) => switch (value) {
  Map() => {
    for (final key in value.keys.toList().reversed)
      key as String: _reverseKeys(value[key]),
  },
  List() => value.map(_reverseKeys).toList(),
  _ => value,
};

void _casTests<Value>({
  required String name,
  required String key,
  required Value baseline,
  required Value proposal,
  required Value concurrent,
  required Map<String, Object?> Function(Value) toJson,
  required Future<Value> Function(ProviderContainer) load,
  required AsyncValue<Value> Function(ProviderContainer) state,
  required void Function(ProviderContainer) invalidate,
  required Future<void> Function(ProviderContainer, Value, Value) save,
}) {
  group(name, () {
    late _PersistenceFixture fixture;

    setUp(() => fixture = _PersistenceFixture());
    tearDown(() => fixture.dispose());

    test(
      'creates an absent row and publishes only the persisted proposal',
      () async {
        final expected = await load(fixture.container);
        expect(await fixture.read(key), isNull);
        await save(fixture.container, proposal, expected);
        expect(jsonDecode((await fixture.read(key))!), toJson(proposal));
        expect(state(fixture.container).asData!.value, same(proposal));
      },
    );

    test(
      'accepts canonical equality despite reordered persisted JSON keys',
      () async {
        await fixture.write(key, jsonEncode(toJson(baseline)));
        final expected = await load(fixture.container);
        final reordered = const JsonEncoder.withIndent('  ')
            .convert(_reverseKeys(toJson(baseline)));
        expect(reordered, isNot(jsonEncode(toJson(baseline))));
        await fixture.write(key, reordered);
        await save(fixture.container, proposal, expected);
        expect(jsonDecode((await fixture.read(key))!), toJson(proposal));
        expect(state(fixture.container).asData!.value, same(proposal));
      },
    );

    test(
      'rejects out-of-band persisted changes even when provider state is stale',
      () async {
        await fixture.write(key, jsonEncode(toJson(baseline)));
        final expected = await load(fixture.container);
        final originalState = state(fixture.container);
        final changedRaw = jsonEncode(toJson(concurrent));
        await fixture.write(key, changedRaw);
        expect(state(fixture.container), same(originalState));
        await expectLater(
          save(fixture.container, proposal, expected),
          throwsA(isA<StateError>()),
        );
        expect(await fixture.read(key), changedRaw);
        expect(state(fixture.container), same(originalState));
      },
    );

    test('rejects a stale expected value after provider refresh', () async {
      await fixture.write(key, jsonEncode(toJson(baseline)));
      final expected = await load(fixture.container);
      await fixture.write(key, jsonEncode(toJson(concurrent)));
      invalidate(fixture.container);
      await load(fixture.container);
      final refreshedState = state(fixture.container);
      await expectLater(
        save(fixture.container, proposal, expected),
        throwsA(isA<StateError>()),
      );
      expect(jsonDecode((await fixture.read(key))!), toJson(concurrent));
      expect(state(fixture.container), same(refreshedState));
    });

    test('rejects deletion of a non-default persisted baseline', () async {
      await fixture.write(key, jsonEncode(toJson(concurrent)));
      final expected = await load(fixture.container);
      final originalState = state(fixture.container);
      await (fixture.database.delete(
        fixture.database.appSettings,
      )..where((row) => row.key.equals(key))).go();
      await expectLater(
        save(fixture.container, proposal, expected),
        throwsA(isA<StateError>()),
      );
      expect(await fixture.read(key), isNull);
      expect(state(fixture.container), same(originalState));
    });

    for (final existing in [false, true]) {
      test(
        'rolls back target and trigger writes without publishing: existing=$existing',
        () async {
          final originalRaw = existing ? jsonEncode(toJson(baseline)) : null;
          if (originalRaw != null) await fixture.write(key, originalRaw);
          final expected = await load(fixture.container);
          final originalState = state(fixture.container);
          await fixture.database.customStatement(
            "CREATE TRIGGER reject_cas AFTER ${existing ? 'UPDATE' : 'INSERT'} ON app_settings "
            "WHEN NEW.key = '$key' BEGIN "
            "INSERT INTO app_settings (key, value) VALUES ('cas.audit', NEW.value); "
            "SELECT RAISE(FAIL, 'CAS persistence failure'); END",
          );
          await expectLater(
            save(fixture.container, proposal, expected),
            throwsA(isA<Exception>()),
          );
          expect(await fixture.read(key), originalRaw);
          expect(await fixture.read('cas.audit'), isNull);
          expect(state(fixture.container), same(originalState));
          await fixture.database.customStatement('DROP TRIGGER reject_cas');
          await save(fixture.container, proposal, expected);
          expect(jsonDecode((await fixture.read(key))!), toJson(proposal));
          expect(state(fixture.container).asData!.value, same(proposal));
        },
      );
    }
  });
}

void main() {
  group('UiLayout corrupt-source CAS recovery', () {
    late _PersistenceFixture fixture;
    const key = UiLayoutController.storageKey;
    late UiLayout proposal;

    setUp(() {
      fixture = _PersistenceFixture();
      proposal = UiLayout(
        narrow: UiLayoutProfile(mainLimit: 2),
        wide: UiLayoutProfile(mainLimit: 7),
      );
    });
    tearDown(() => fixture.dispose());

    for (final raw in ['not-json', '{"version":999}']) {
      test(
        'retains raw corruption until explicit matching repair: $raw',
        () async {
          await fixture.write(key, raw);
          final expected = await fixture.container.read(
            uiLayoutProvider.future,
          );
          expect(expected.warning, isNotNull);
          expect(expected.corruptSource, raw);
          expect(expected.narrow.mainLimit, 4);
          expect(await fixture.read(key), raw);
          expect(expected.toJson().containsKey('corruptSource'), isFalse);
          expect(expected.toJson().containsKey('warning'), isFalse);
          await fixture.container
              .read(uiLayoutProvider.notifier)
              .saveIfUnchanged(proposal, expected: expected);
          expect(jsonDecode((await fixture.read(key))!), proposal.toJson());
          final published = fixture.container
              .read(uiLayoutProvider)
              .asData!
              .value;
          expect(published, same(proposal));
          expect(published.warning, isNull);
          expect(published.corruptSource, isNull);
        },
      );
    }

    test(
      'rejects changed corrupt bytes rather than trusting recovered defaults',
      () async {
        await fixture.write(key, 'original-invalid-json');
        final expected = await fixture.container.read(uiLayoutProvider.future);
        final originalState = fixture.container.read(uiLayoutProvider);
        await fixture.write(key, 'different-invalid-json');
        await expectLater(
          fixture.container
              .read(uiLayoutProvider.notifier)
              .saveIfUnchanged(proposal, expected: expected),
          throwsA(anyOf(isA<FormatException>(), isA<StateError>())),
        );
        expect(await fixture.read(key), 'different-invalid-json');
        expect(fixture.container.read(uiLayoutProvider), same(originalState));
        expect(expected.corruptSource, 'original-invalid-json');
      },
    );

    test('rejects a concurrent valid replacement of the corrupt row', () async {
      await fixture.write(key, 'invalid-json');
      final expected = await fixture.container.read(uiLayoutProvider.future);
      final originalState = fixture.container.read(uiLayoutProvider);
      final replacement = jsonEncode(
        UiLayout(wide: UiLayoutProfile(mainLimit: 9)).toJson(),
      );
      await fixture.write(key, replacement);
      await expectLater(
        fixture.container
            .read(uiLayoutProvider.notifier)
            .saveIfUnchanged(proposal, expected: expected),
        throwsA(isA<StateError>()),
      );
      expect(await fixture.read(key), replacement);
      expect(fixture.container.read(uiLayoutProvider), same(originalState));
    });

    test(
      'a warning without the exact raw token cannot authorize repair',
      () async {
        await fixture.write(key, 'invalid-json');
        final loaded = await fixture.container.read(uiLayoutProvider.future);
        final originalState = fixture.container.read(uiLayoutProvider);
        for (final token in <String?>[null, 'wrong-invalid-json']) {
          await expectLater(
            fixture.container
                .read(uiLayoutProvider.notifier)
                .saveIfUnchanged(
                  proposal,
                  expected: UiLayout(
                    warning: loaded.warning,
                    corruptSource: token,
                  ),
                ),
            throwsA(anyOf(isA<FormatException>(), isA<StateError>())),
          );
          expect(await fixture.read(key), 'invalid-json');
          expect(fixture.container.read(uiLayoutProvider), same(originalState));
        }
      },
    );

    test('failed repair rolls back corrupt bytes and preserves the token for retry', () async {
      const raw = 'invalid-json';
      await fixture.write(key, raw);
      final expected = await fixture.container.read(uiLayoutProvider.future);
      final originalState = fixture.container.read(uiLayoutProvider);
      await fixture.database.customStatement(
        "CREATE TRIGGER reject_repair AFTER UPDATE ON app_settings "
        "WHEN NEW.key = '$key' BEGIN "
        "INSERT INTO app_settings (key, value) VALUES ('repair.audit', NEW.value); "
        "SELECT RAISE(FAIL, 'repair failure'); END",
      );
      await expectLater(
        fixture.container
            .read(uiLayoutProvider.notifier)
            .saveIfUnchanged(proposal, expected: expected),
        throwsA(isA<Exception>()),
      );
      expect(await fixture.read(key), raw);
      expect(await fixture.read('repair.audit'), isNull);
      expect(fixture.container.read(uiLayoutProvider), same(originalState));
      expect(expected.corruptSource, raw);
      await fixture.database.customStatement('DROP TRIGGER reject_repair');
      await fixture.container
          .read(uiLayoutProvider.notifier)
          .saveIfUnchanged(proposal, expected: expected);
      expect(jsonDecode((await fixture.read(key))!), proposal.toJson());
      expect(
        fixture.container.read(uiLayoutProvider).asData!.value,
        same(proposal),
      );
    });
  });

  _casTests<AppPreferences>(
    name: 'AppPreferences.saveIfUnchanged',
    key: AppPreferencesController.storageKey,
    baseline: const AppPreferences(),
    proposal: const AppPreferences(
      themeMode: ThemeMode.dark,
      reduceMotion: true,
      haptics: false,
    ),
    concurrent: const AppPreferences(themeMode: ThemeMode.light),
    toJson: (value) => value.toJson(),
    load: (container) => container.read(appPreferencesProvider.future),
    state: (container) => container.read(appPreferencesProvider),
    invalidate: (container) => container.invalidate(appPreferencesProvider),
    save: (container, proposal, expected) => container
        .read(appPreferencesProvider.notifier)
        .saveIfUnchanged(proposal, expected: expected),
  );
  _casTests<UiLayout>(
    name: 'UiLayout.saveIfUnchanged',
    key: UiLayoutController.storageKey,
    baseline: UiLayout(
      narrow: UiLayoutProfile(
        mainLimit: 4,
        mounts: {
          'first.entry': const UiMount(placement: UiPlacement.header),
          'missing.entry': const UiMount(placement: UiPlacement.hidden),
        },
      ),
      wide: UiLayoutProfile(mainLimit: 8),
    ),
    proposal: UiLayout(
      narrow: UiLayoutProfile(
        mainLimit: 2,
        mounts: {
          'first.entry': const UiMount(
            placement: UiPlacement.page,
            pageId: 'host.page',
            slotId: 'body',
            order: 3,
            context: PageContext(projectId: 'project'),
          ),
          'missing.entry': const UiMount(placement: UiPlacement.hidden),
        },
      ),
      wide: UiLayoutProfile(mainLimit: 7),
    ),
    concurrent: UiLayout(wide: UiLayoutProfile(mainLimit: 9)),
    toJson: (value) => value.toJson(),
    load: (container) => container.read(uiLayoutProvider.future),
    state: (container) => container.read(uiLayoutProvider),
    invalidate: (container) => container.invalidate(uiLayoutProvider),
    save: (container, proposal, expected) => container
        .read(uiLayoutProvider.notifier)
        .saveIfUnchanged(proposal, expected: expected),
  );
}
