import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'dart:async';

import '../module_host/host_providers.dart';
import '../module_host/module_package.dart';
import 'ui_composition.dart';

/// EntityRef is data, never a grant. Ownership and permissions are checked again
/// by services when the contributed page reads or prepares a command.
final pageContextValidityProvider = StreamProvider.autoDispose
    .family<bool, PageContext>((ref, context) async* {
      final refs = (context.values['entities'] as List? ?? [])
          .map(object)
          .toList();
      if (refs.isEmpty) {
        yield true;
        return;
      }
      final host = await ref.watch(moduleHostProvider.future);
      Future<bool> valid() async {
        for (final entity in refs) {
          final actor = host.store.actors[entity['moduleId']];
          if (actor == null ||
              !await host.store.entityExists(
                actor,
                entity['collection'] as String,
                entity['id'] as String,
              )) {
            return false;
          }
        }
        return true;
      }

      final updates = StreamController<void>();
      final data = host.store.changes.stream.listen((_) => updates.add(null));
      final registry = host.registryChanges.stream.listen(
        (_) => updates.add(null),
      );
      ref.onDispose(() {
        data.cancel();
        registry.cancel();
        updates.close();
      });
      yield await valid();
      await for (final _ in updates.stream) {
        yield await valid();
      }
    });
