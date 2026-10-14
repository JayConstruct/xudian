import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_toast.dart';
import '../../app/design_system.dart';
import '../../core/ui/native_ui.dart';

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

  Widget _measurement(BuildContext context, String title, String value) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            SelectableText(value),
          ],
        ),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = (constraints.maxWidth - 32).clamp(
            0.0,
            double.infinity,
          );
          final diagnostics = DisplayDiagnostics.capture(
            view: view,
            media: media,
            availableWidth: constraints.maxWidth,
            contentWidth: contentWidth,
          );
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              const Text('用于高级问题反馈。信息随当前视图更新，可由你主动复制；不会自动上传，也不包含草稿、业务数据或密钥。'),
              const SizedBox(height: 12),
              NativeUi(
                child: FilledButton(
                  onPressed: () => _copy(diagnostics),
                  child: const Text('复制诊断 JSON'),
                ),
              ),
              const SizedBox(height: 20),
              _measurement(
                context,
                'Flutter 平台视图尺寸（px）',
                _size(view.physicalSize),
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  '这是当前 Flutter 视图的像素尺寸，不代表设备面板的物理分辨率。窗口、系统显示设置和嵌入布局可能影响测量。',
                ),
              ),
              _measurement(context, '当前视图像素比', _number(view.devicePixelRatio)),
              _measurement(
                context,
                '视图像素换算的逻辑尺寸',
                _size(view.physicalSize / view.devicePixelRatio),
              ),
              _measurement(context, 'MediaQuery 逻辑视口', _size(media.size)),
              _measurement(
                context,
                '页面容器可用宽度（逻辑像素）',
                _number(constraints.maxWidth),
              ),
              _measurement(context, '内容可用宽度（扣除页面左右留白）', _number(contentWidth)),
              _measurement(
                context,
                '当前安全区 padding（逻辑像素）',
                _insets(media.padding),
              ),
              _measurement(
                context,
                '视图安全区 viewPadding（逻辑像素）',
                _insets(media.viewPadding),
              ),
              _measurement(
                context,
                '键盘等遮挡 viewInsets（逻辑像素）',
                _insets(media.viewInsets),
              ),
              const Text(
                '实际字号样本（逻辑像素）',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              for (final size in [12.0, 14.0, 24.0])
                Text(
                  '${size.toInt()} → ${_number(media.textScaler.scale(size))}',
                ),
              const SizedBox(height: 8),
              const Text('样本直接使用 TextScaler.scale，不假设缩放比例恒定。本页不会更改系统或应用的显示设置。'),
            ],
          );
        },
      ),
    );
  }
}
