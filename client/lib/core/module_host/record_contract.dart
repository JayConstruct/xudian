import '../contracts/json_values.dart';

/// Provider-owned bindings from stable semantic roles to private record fields.
/// A page may reference a contract; it cannot supply or override its bindings.
class RecordContract {
  RecordContract._(this.kind, this.collection, this.fields, this.settings);
  final String kind, collection;
  final Map<String, String> fields;
  final Map<String, Object?> settings;
  Map<String, Object?> toJson() => {
    'kind': kind,
    'collection': collection,
    'fields': fields,
    'settings': settings,
  };

  static const roles = {
    'timeRange': {
      'id',
      'title',
      'startAt',
      'endAt',
      'zone',
      'date',
      'duration',
      'modifiedAt',
      'locked',
      'completed',
      'deleted',
      'archived',
    },
    'timeJournal': {
      'id',
      'kind',
      'createdAt',
      'request',
      'changes',
      'undone',
      'sequence',
      'undoOccupancy',
      'undoneAt',
    },
    'timeReceipt': {'id', 'kind', 'request', 'createdAt'},
    'timeOccurrence': {'id', 'taskId', 'date', 'duration', 'locked', 'status'},
  };

  static Map<String, RecordContract> parse(Map<String, Object?> definition) {
    final raw = definition['recordContracts'];
    if (raw == null) return const {};
    if (raw is! Map) {
      throw const FormatException('recordContracts must be an object');
    }
    final collections = (definition['collections'] as List? ?? const [])
        .whereType<Map>()
        .map((c) => c['id'])
        .toSet();
    final result = <String, RecordContract>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (entry.key is! String ||
          (entry.key as String).isEmpty ||
          value is! Map ||
          value.keys.toSet().difference({
            'kind',
            'collection',
            'fields',
            'settings',
          }).isNotEmpty ||
          !roles.containsKey(value['kind']) ||
          value['collection'] is! String ||
          !collections.contains(value['collection']) ||
          value['fields'] is! Map) {
        throw const FormatException('Invalid record contract');
      }
      final rawFields = value['fields'] as Map;
      if (rawFields.entries.any(
        (entry) => entry.key is! String || entry.value is! String,
      )) {
        throw const FormatException('Record field bindings must be strings');
      }
      final fields = Map<String, String>.from(rawFields);
      final required = roles[value['kind']]!;
      if (fields.keys.toSet().difference(required).isNotEmpty ||
          required.difference(fields.keys.toSet()).isNotEmpty ||
          fields.values.toSet().length != fields.length ||
          fields['id'] != 'id' ||
          fields.values.any((name) => name.isEmpty || name.length > 128)) {
        throw const FormatException(
          'Record contract roles must be complete and unique',
        );
      }
      if (value['settings'] != null && value['settings'] is! Map) {
        throw const FormatException(
          'Record contract settings must be an object',
        );
      }
      final settings = Map<String, Object?>.from(
        (value['settings'] ?? const {}) as Map,
      );
      final kind = value['kind'];
      if (kind == 'timeJournal') {
        if (settings.length != 2 ||
            settings['retainedRecords'] is! int ||
            (settings['retainedRecords'] as int) < 1 ||
            (settings['retainedRecords'] as int) > 10000 ||
            settings['defaultKind'] is! String ||
            (settings['defaultKind'] as String).isEmpty) {
          throw const FormatException('Invalid journal retention contract');
        }
      } else if (kind == 'timeOccurrence') {
        if (settings.length != 1 ||
            settings['activeValue'] is! String ||
            (settings['activeValue'] as String).isEmpty) {
          throw const FormatException('Invalid occurrence state contract');
        }
      } else if (settings.isNotEmpty) {
        throw const FormatException('Unexpected record contract settings');
      }
      result[entry.key as String] = RecordContract._(
        value['kind'] as String,
        value['collection'] as String,
        Map.unmodifiable(fields),
        Map.unmodifiable(settings),
      );
    }
    return Map.unmodifiable(result);
  }

  Map<String, Object?> project(Object? raw) {
    final value = Map<String, Object?>.from(raw as Map);
    final reverse = {
      for (final entry in fields.entries) entry.value: entry.key,
    };
    // Unbound data is retained under a disjoint namespace. It can neither
    // impersonate a role nor disappear from the unchanged-field checks.
    return {
      for (final entry in value.entries)
        reverse[entry.key] ?? '\$raw:${entry.key}': freezeJson(entry.value),
    };
  }
}

class TimeAdjustmentRecords {
  TimeAdjustmentRecords({
    required this.subjectModuleId,
    required this.ownerModuleId,
    required this.subject,
    required this.journal,
    required this.receipt,
    required this.occurrence,
  }) {
    if (subject.kind != 'timeRange' ||
        journal.kind != 'timeJournal' ||
        receipt.kind != 'timeReceipt' ||
        occurrence.kind != 'timeOccurrence' ||
        {
              for (final entry in bindings.entries)
                '${entry.value.$1}/${entry.value.$2.collection}',
            }.length !=
            4) {
      throw const FormatException('Ambiguous time adjustment record bindings');
    }
  }
  final String subjectModuleId, ownerModuleId;
  final RecordContract subject, journal, receipt, occurrence;
  Map<String, (String, RecordContract)> get bindings => {
    '@subject': (subjectModuleId, subject),
    '@journal': (ownerModuleId, journal),
    '@receipt': (ownerModuleId, receipt),
    '@occurrence': (ownerModuleId, occurrence),
  };

  Map<String, Object?> _journal(Object? raw) {
    final value = journal.project(raw);
    if (value['changes'] is List) {
      value['changes'] = (value['changes'] as List).map((raw) {
        final change = Map<String, Object?>.from(raw as Map);
        for (final key in ['before', 'after']) {
          if (change[key] != null) change[key] = subject.project(change[key]);
        }
        for (final key in ['beforeOccurrence', 'afterOccurrence']) {
          if (change[key] != null) {
            change[key] = occurrence.project(change[key]);
          }
        }
        return change;
      }).toList();
    }
    return value;
  }

  List<Object?> projectWrites(List<Object?> writes) => writes.map((raw) {
    final write = Map<String, Object?>.from(raw as Map);
    final matches = bindings.entries
        .where(
          (entry) =>
              write['moduleId'] == entry.value.$1 &&
              write['collection'] == entry.value.$2.collection,
        )
        .toList();
    if (matches.length != 1) {
      throw const FormatException('Write outside declared record contracts');
    }
    final binding = matches.single;
    write['collection'] = binding.key;
    for (final key in ['before', 'value']) {
      if (write[key] != null) {
        write[key] = binding.key == '@journal'
            ? _journal(write[key])
            : binding.value.$2.project(write[key]);
      }
    }
    return write;
  }).toList();

  Map<String, Object?> projectInput(Object? raw) {
    final input = Map<String, Object?>.from(raw as Map);
    if (input['preview'] is! Map) return input;
    final preview = Map<String, Object?>.from(input['preview'] as Map);
    preview['changes'] = (preview['changes'] as List).map((raw) {
      final change = Map<String, Object?>.from(raw as Map);
      change['before'] = subject.project(change['before']);
      change['fields'] = subject.project(change['fields']);
      return change;
    }).toList();
    input['preview'] = preview;
    return input;
  }
}
