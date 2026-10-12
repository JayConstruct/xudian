import 'module_package.dart';

const _contributionSlots = {
  'navigationPrimary',
  'workspacePage',
  'workspaceHeaderActions',
  'workspaceAssistant',
  'taskDetailSections',
  'taskEditorSections',
  'inputActions',
  'projectViews',
  'settingsSections',
  'globalOverlay',
};

String _choice(
  Object? value,
  String fallback,
  Set<String> choices,
  String label,
) {
  final selected = value ?? fallback;
  if (selected is! String || !choices.contains(selected)) {
    throw FormatException('Invalid $label');
  }
  return selected;
}

void _optionalString(Object? value, String label) {
  if (value != null && value is! String) {
    throw FormatException('Invalid $label');
  }
}

void _requiredString(Object? value, String label) {
  if (value is! String) throw FormatException('Invalid $label');
}

void _stringList(Object? value, String label) {
  if (value != null &&
      (value is! List || value.any((entry) => entry is! String))) {
    throw FormatException('Invalid $label');
  }
}

/// Checks declarations without constructing Flutter registrations. These checks
/// preserve the data validation performed by ScriptAppModule and ModuleRegistry.
/// The application may additionally validate its native pages and renderers via
/// ModuleHost.validateCandidate. This check also protects a headless host.
void validateModuleUiDeclarations(Iterable<ScriptPackage> packages) {
  final pages = <String>{}, entries = <String>{};
  final contributions = <String, Set<String>>{};
  for (final package in packages) {
    for (final raw in package.definition['pages'] as List? ?? []) {
      final page = object(raw);
      final id = string(page['id'], 'page id');
      if (!pages.add(id)) throw StateError('Duplicate UI page: $id');
      _requiredString(page['handler'], 'page handler');
      _optionalString(page['title'], 'page title');
      _choice(page['headerMode'], 'standard', {
        'standard',
        'contributed',
        'date',
      }, 'page headerMode');
      if (page['initializesRuntimeContext'] != null &&
          page['initializesRuntimeContext'] is! bool) {
        throw const FormatException('Invalid page initializesRuntimeContext');
      }
      _stringList(page['requiredContext'], 'page requiredContext');
      final slots = <String>{};
      for (final rawSlot in page['slots'] as List? ?? []) {
        final slot = object(rawSlot);
        final slotId = slot['id'] as String;
        _requiredString(slot['label'], 'page slot label');
        final kind = _choice(slot['kind'], 'entries', {
          'entries',
          'tabs',
          'sections',
        }, 'page slot kind');
        final inline = slot.containsKey('inline') ? slot['inline'] : false;
        if (inline is! bool || inline && kind != 'sections') {
          throw const FormatException(
            'inline requires a boolean sections slot',
          );
        }
        _stringList(slot['requiredContext'], 'page slot requiredContext');
        final capacity = slot['capacity'] as int?;
        if (slotId.isEmpty ||
            !slots.add(slotId) ||
            capacity != null && capacity < 1) {
          throw StateError('Invalid or duplicate page slot: $id/$slotId');
        }
      }
      for (final rawEntry in [
        if (page['entry'] != null) page['entry'],
        ...page['entries'] as List? ?? [],
      ]) {
        final entry = object(rawEntry);
        final entryId = entry['id'] as String;
        if (!entries.add(entryId)) {
          throw StateError('Duplicate UI entry: $entryId');
        }
        _optionalString(entry['label'], 'entry label');
        _choice(entry['opening'], 'workspace', {
          'workspace',
          'detail',
          'adaptivePanel',
        }, 'entry opening');
        _choice(entry['placement'], 'main', {
          'main',
          'header',
          'more',
          'settings',
          'hidden',
          'page',
        }, 'entry placement');
        for (final field in ['targetPageId', 'slotId', 'taskId', 'projectId']) {
          _optionalString(entry[field], 'entry $field');
        }
        if (entry['order'] != null && entry['order'] is! int) {
          throw const FormatException('Invalid entry order');
        }
        if (entry['values'] != null) object(entry['values'], 'entry values');
      }
    }
    for (final raw in package.definition['contributions'] as List? ?? []) {
      final contribution = object(raw);
      final slot = contribution['slot'] as String;
      if (!_contributionSlots.contains(slot)) {
        throw const FormatException('Invalid contribution slot');
      }
      final id = contribution['id'] as String;
      _requiredString(contribution['handler'], 'contribution handler');
      _optionalString(contribution['label'], 'contribution label');
      if (!(contributions[slot] ??= {}).add(id)) {
        throw StateError('Duplicate UI contribution: $slot/$id');
      }
    }
  }
}
