import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_toast.dart';
import '../../app/design_system.dart';
import '../../core/ui/native_ui.dart';
import 'settings_widgets.dart';

/// Only display measurements are exported. No repository or preferences access.
class DisplayDiagnostics {
  DisplayDiagnostics.capture({
    required ui.FlutterView view,
    required MediaQueryData media,
    required double availableWidth,
    required double contentWidth,
  }) : values = {
         'schemaVersion': 1,
         'source': 'currentFlutterViewAndMediaQuery',
         'platformView': {
           'physicalSizePx': _size(view.physicalSize),
           'devicePixelRatio': view.devicePixelRatio,
           'logicalSizeFromView': _size(
             view.physicalSize / view.devicePixelRatio,
           ),
           'hardwarePanelResolution': 'notMeasured',
         },
         'mediaQuery': {
           'logicalViewportSize': _size(media.size),
           'padding': _insets(media.padding),
           'viewPadding': _insets(media.viewPadding),
           'keyboardAndOtherViewInsets': _insets(media.viewInsets),
           'textScalerSamples': {
             for (final fontSize in [12.0, 14.0, 24.0])
               fontSize.toInt().toString(): media.textScaler.scale(fontSize),
           },
         },
         'layout': {
           'availableWidthLogicalPx': availableWidth,
           'contentWidthLogicalPx': contentWidth,
         },
         'privacy': {
           'dataScope': 'displayMetricsOnly',
           'transfer': 'manualClipboardOnly',
         },
       };

  final Map<String, Object?> values;
  String get json => const JsonEncoder.withIndent('  ').convert(values);

  static Map<String, double> _size(Size size) => {
    'width': size.width,
    'height': size.height,
  };

  static Map<String, double> _insets(EdgeInsets insets) => {
    'left': insets.left,
    'top': insets.top,
    'right': insets.right,
    'bottom': insets.bottom,
  };
}

class DisplayDiagnosticsPage extends StatefulWidget {
  const DisplayDiagnosticsPage({super.key});

  @override
  State<DisplayDiagnosticsPage> createState() => _DisplayDiagnosticsPageState();
}

class _DisplayDiagnosticsPageState extends State<DisplayDiagnosticsPage>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    // Refresh even if an ancestor supplies its own unchanged MediaQuery.
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _number(double value) => value.toStringAsFixed(2);
  String _size(Size size) => '${_number(size.width)} × ${_number(size.height)}';
  String _insets(EdgeInsets insets) =>
      '左 ${_number(insets.left)}，上 ${_number(insets.top)}，右 ${_number(insets.right)}，下 ${_number(insets.bottom)}';

  Widget _measurement(String title, String value, {bool inline = false}) =>
      Builder(
        builder: (context) {
          final label = Semantics(container: true, child: Text(title));
          final reading = SelectableText(
            value,
            style: ListTileTheme.of(context).subtitleTextStyle,
          );
          return ListTile(
            minTileHeight: inline ? 50 : 62,
            title: inline
                ? Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 3,
                    children: [label, reading],
                  )
                : label,
            subtitle: inline ? null : reading,
          );
        },
      );

  Future<void> _showInsets(BuildContext context) => showModalBottomSheet<void>(
    useSafeArea: true,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: AppDesign.canvas(context),
    barrierColor: const Color(0x5C161722),
    context: context,
    builder: (context) {
      final media = MediaQueryData.fromView(
        View.of(context),
        platformData: MediaQuery.of(context),
      );
      return SettingsSheet(
        title: Semantics(
          header: true,
          child: Text(
            '安全区与遮挡',
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontSize: 21, fontWeight: FontWeight.w700),
          ),
        ),
        content: SingleChildScrollView(
          child: SettingsGroupSurface(
            dividerIndent: 16,
            children: [
              _measurement('当前安全区 padding（逻辑像素）', _insets(media.padding)),
              _measurement(
                '视图安全区 viewPadding（逻辑像素）',
                _insets(media.viewPadding),
              ),
              _measurement('键盘等遮挡 viewInsets（逻辑像素）', _insets(media.viewInsets)),
            ],
          ),
        ),
      );
    },
  );

  Future<void> _copy(DisplayDiagnostics diagnostics) async {
    await Clipboard.setData(ClipboardData(text: diagnostics.json));
    if (mounted) {
      AppToast.show(context, message: '显示诊断信息已复制', kind: 'success');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Capture before Scaffold/SafeArea consume padding or keyboard insets.
    final media = MediaQuery.of(context);
    final view = View.of(context);
    return DetailPage(
      title: '显示与布局信息',
      titleMaxLines: 2,
      settingsStyle: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const horizontalPadding = AppDesign.pageGutter;
          final contentWidth = (constraints.maxWidth - 2 * horizontalPadding)
              .clamp(0.0, double.infinity);
          final diagnostics = DisplayDiagnostics.capture(
            view: view,
            media: media,
            availableWidth: constraints.maxWidth,
            contentWidth: contentWidth,
          );
          return SettingsList(
            horizontalPadding: horizontalPadding,
            footer: NativeUi(
              child: FilledButton.icon(
                onPressed: () => _copy(diagnostics),
                icon: const Icon(Icons.copy_outlined),
                label: const Text('复制诊断 JSON'),
              ),
            ),
            children: [
              SettingsSummary(
                label: '当前逻辑视口',
                title: _size(media.size),
                detail: '逻辑像素 · 随窗口实时更新',
                icon: Icons.aspect_ratio_rounded,
              ),
              SettingsGroup(
                title: '视图与布局',
                dividerIndent: 16,
                children: [
                  _measurement(
                    'Flutter 平台视图尺寸（px）',
                    _size(view.physicalSize),
                    inline: true,
                  ),
                  _measurement(
                    '当前视图像素比',
                    _number(view.devicePixelRatio),
                    inline: true,
                  ),
                  _measurement(
                    '视图像素换算的逻辑尺寸',
                    _size(view.physicalSize / view.devicePixelRatio),
                    inline: true,
                  ),
                  _measurement(
                    '页面 / 内容宽度',
                    '${_number(constraints.maxWidth)} / ${_number(contentWidth)}',
                    inline: true,
                  ),
                ],
              ),
              SettingsGroup(
                title: '边距与字号',
                dividerIndent: 16,
                children: [
                  SettingsEntry(
                    title: '安全区与遮挡',
                    subtitle: 'padding、viewPadding、viewInsets',
                    icon: Icons.fullscreen,
                    onTap: () => _showInsets(context),
                  ),
                  ListTile(
                    minTileHeight: 62,
                    title: const Text('实际字号样本（逻辑像素）'),
                    subtitle: Wrap(
                      spacing: 12,
                      children: [
                        for (final size in [12.0, 14.0, 24.0])
                          Text(
                            '${size.toInt()} → ${_number(media.textScaler.scale(size))}',
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SettingsNote('字号样本不假设缩放比例恒定。视图像素反映当前窗口，复制内容仅含显示指标。'),
            ],
          );
        },
      ),
    );
  }
}
