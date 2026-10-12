import 'package:flutter/material.dart';

import 'ui_component.dart';
import 'temporal_input.dart';

/// Adapts native UI to public recipes while the original widget continues to
/// own controllers, focus, gestures, validation and action callbacks.
class NativeUi extends StatelessWidget {
  const NativeUi({
    super.key,
    required this.child,
    this.ref,
    this.props = const {},
    this.protected = false,
  });

  final bool protected;
  final Widget child;
  final String? ref;
  final Map<String, Object?> props;

  static String? _text(Widget? widget) => switch (widget) {
    Text(:final data, :final textSpan) => data ?? textSpan?.toPlainText(),
    Row(:final children) || Column(:final children) =>
      children.map(_text).whereType<String>().join(' '),
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    if (protected) {
      return UiPackScope(
        defaultOnly: true,
        child: NativeUi(ref: ref, props: props, child: child),
      );
    }
    final native = child;
    if (native is Scaffold) return _page(native);
    final (component, values, events) = switch (native) {
      TextButton() => _button(native.child, native.onPressed, 'text'),
      OutlinedButton() => _button(native.child, native.onPressed, 'outlined'),
      FilledButton() => _button(native.child, native.onPressed, 'filled'),
      ElevatedButton() => _button(native.child, native.onPressed, 'filled'),
      IconButton() => (
        'ui.iconButton@1',
        <String, Object?>{
          'label': native.tooltip ?? '',
          'disabled': native.onPressed == null,
        },
        <String, void Function(Object?)>{
          'press': (_) => native.onPressed?.call(),
        },
      ),
      ListTile() => (
        'ui.nativeTile@1',
        <String, Object?>{
          'title': _text(native.title) ?? '',
          'subtitle': _text(native.subtitle),
          'disabled': !native.enabled,
          'selected': native.selected,
        },
        <String, void Function(Object?)>{},
      ),
      SwitchListTile() => (
        'ui.toggle@1',
        <String, Object?>{
          'label': _text(native.title) ?? '',
          'value': native.value,
          'disabled': native.onChanged == null,
        },
        <String, void Function(Object?)>{},
      ),
      CheckboxListTile() => (
        'ui.checkbox@1',
        <String, Object?>{
          'label': _text(native.title) ?? '',
          'value': native.value,
          'disabled': native.onChanged == null,
        },
        <String, void Function(Object?)>{},
      ),
      TextField() => (
        'ui.input@1',
        <String, Object?>{
          'label':
              native.decoration?.labelText ?? native.decoration?.hintText ?? '',
          'disabled': native.enabled == false,
        },
        <String, void Function(Object?)>{},
      ),
      DropdownButtonFormField() => (
        'ui.select@1',
        <String, Object?>{
          'label': native.decoration.labelText ?? '',
          // The native dropdown owns enablement; reading a type-erased
          // generic callback can throw Dart's function variance check.
        },
        <String, void Function(Object?)>{},
      ),
      Checkbox() => (
        'ui.checkbox@1',
        <String, Object?>{
          'value': native.value,
          'disabled': native.onChanged == null,
        },
        <String, void Function(Object?)>{},
      ),
      Switch() => (
        'ui.toggle@1',
        <String, Object?>{
          'value': native.value,
          'disabled': native.onChanged == null,
        },
        <String, void Function(Object?)>{},
      ),
      TemporalInput() => (
        switch (native.kind) {
          TemporalInputKind.date => 'ui.dateInput@1',
          TemporalInputKind.time => 'ui.timeInput@1',
          TemporalInputKind.dateTime => 'ui.dateTimeInput@1',
          TemporalInputKind.dateRange => 'ui.dateRangeInput@1',
        },
        <String, Object?>{'label': native.label, 'disabled': !native.enabled},
        <String, void Function(Object?)>{},
      ),
      Slider() => (
        'ui.slider@1',
        <String, Object?>{
          'value': native.value,
          'min': native.min,
          'max': native.max,
          'disabled': native.onChanged == null,
        },
        <String, void Function(Object?)>{},
      ),
      CircularProgressIndicator() => (
        'ui.loading@1',
        <String, Object?>{'value': native.value},
        <String, void Function(Object?)>{},
      ),
      LinearProgressIndicator() => (
        'ui.progress@1',
        <String, Object?>{'value': native.value},
        <String, void Function(Object?)>{},
      ),
      Dialog() => (
        'ui.nativeDialog@1',
        <String, Object?>{},
        <String, void Function(Object?)>{},
      ),
      AlertDialog() => (
        'ui.nativeDialog@1',
        <String, Object?>{'title': _text(native.title) ?? ''},
        <String, void Function(Object?)>{},
      ),
      _ => (
        'ui.nativeControl@1',
        <String, Object?>{},
        <String, void Function(Object?)>{},
      ),
    };
    return UiComponent(
      ref: ref ?? component,
      props: {...values, ...props},
      slots: {'control': native},
      events: events,
      fallback: native,
    );
  }

  (String, Map<String, Object?>, Map<String, void Function(Object?)>) _button(
    Widget? label,
    VoidCallback? press,
    String variant,
  ) {
    final text = _text(label);
    // Flutter's .icon constructors use private composite children. Keep that
    // complete native control rather than replacing its real label with ''.
    if (text == null) {
      return (
        'ui.nativeControl@1',
        {'kind': 'button', 'variant': variant, 'disabled': press == null},
        <String, void Function(Object?)>{},
      );
    }
    return (
      'ui.button@1',
      {'label': text, 'variant': variant, 'disabled': press == null},
      {'press': (_) => press?.call()},
    );
  }

  Widget _page(Scaffold native) {
    final appBar = native.appBar;
    final title = appBar is AppBar ? _text(appBar.title) : null;
    final body = native.body ?? const SizedBox.shrink();
    return Scaffold(
      key: native.key,
      appBar: appBar == null
          ? null
          : PreferredSize(
              preferredSize: appBar.preferredSize,
              child: UiComponent(
                ref: 'ui.chrome.pageHeader@1',
                props: {'title': title ?? ''},
                slots: {'control': appBar},
                fallback: appBar,
              ),
            ),
      body: UiComponent(
        ref: ref ?? 'ui.page.native@1',
        props: {'title': title ?? '', ...props},
        slots: {'body': body},
        fallback: body,
      ),
      floatingActionButton: native.floatingActionButton,
      floatingActionButtonLocation: native.floatingActionButtonLocation,
      floatingActionButtonAnimator: native.floatingActionButtonAnimator,
      persistentFooterButtons: native.persistentFooterButtons,
      persistentFooterAlignment: native.persistentFooterAlignment,
      persistentFooterDecoration: native.persistentFooterDecoration,
      drawer: native.drawer,
      onDrawerChanged: native.onDrawerChanged,
      endDrawer: native.endDrawer,
      onEndDrawerChanged: native.onEndDrawerChanged,
      bottomNavigationBar: native.bottomNavigationBar,
      bottomSheet: native.bottomSheet,
      backgroundColor: native.backgroundColor,
      resizeToAvoidBottomInset: native.resizeToAvoidBottomInset,
      primary: native.primary,
      drawerDragStartBehavior: native.drawerDragStartBehavior,
      extendBody: native.extendBody,
      drawerBarrierDismissible: native.drawerBarrierDismissible,
      extendBodyBehindAppBar: native.extendBodyBehindAppBar,
      drawerScrimColor: native.drawerScrimColor,
      bottomSheetScrimBuilder: native.bottomSheetScrimBuilder,
      drawerEdgeDragWidth: native.drawerEdgeDragWidth,
      drawerEnableOpenDragGesture: native.drawerEnableOpenDragGesture,
      endDrawerEnableOpenDragGesture: native.endDrawerEnableOpenDragGesture,
      restorationId: native.restorationId,
    );
  }
}
