import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/modules/module_registry.dart';
import 'assistant_panel.dart';
import 'assistant_runtime.dart';

class AssistantOverlay extends ConsumerStatefulWidget {
  const AssistantOverlay({
    super.key,
    required this.registry,
    required this.developerBuilder,
  });

  final ModuleRegistry registry;
  final WidgetBuilder developerBuilder;

  @override
  ConsumerState<AssistantOverlay> createState() => _AssistantOverlayState();
}

class _AssistantOverlayState extends ConsumerState<AssistantOverlay> {
  Offset? bubblePosition;
  bool panelOpened = false;

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(assistantControllerProvider(widget.registry));
    return Overlay.wrap(
      child: ListenableBuilder(
        listenable: Listenable.merge([controller, FocusManager.instance]),
        builder: (context, _) {
          if (!controller.enabled) return const SizedBox.shrink();
          panelOpened = panelOpened || controller.expanded;
          return LayoutBuilder(
            builder: (context, constraints) {
              final media = MediaQuery.of(context);
              final left = math.max(media.viewPadding.left, media.padding.left);
              final top = math.max(media.viewPadding.top, media.padding.top);
              final right = math.max(
                media.viewPadding.right,
                media.padding.right,
              );
              final bottom = math.max(
                media.viewInsets.bottom,
                math.max(media.viewPadding.bottom, media.padding.bottom),
              );
              final width = math.max(0.0, constraints.maxWidth - left - right);
              final height = math.max(
                0.0,
                constraints.maxHeight - top - bottom,
              );
              if (width == 0 || height == 0) return const SizedBox.shrink();
              final diameter = math.min(56.0, math.min(width, height));
              final maxLeft = left + width - diameter;
              final maxTop = top + height - diameter;
              final textScale = media.textScaler.scale(14) / 14;
              final focusContext = FocusManager.instance.primaryFocus?.context;
              final editing =
                  focusContext?.widget is EditableText ||
                  focusContext?.findAncestorStateOfType<EditableTextState>() !=
                      null;
              final bottomReserve = math.max(180.0, 180 * textScale);
              final position =
                  bubblePosition ??
                  Offset(
                    maxLeft - 16,
                    media.viewInsets.bottom > 0 || editing
                        ? top + 16
                        : maxTop - bottomReserve,
                  );
              final clamped = Offset(
                position.dx.clamp(left, maxLeft),
                position.dy.clamp(top, maxTop),
              );
              final wide = width >= math.max(850.0, 640 * textScale);
              final panelWidth = wide
                  ? math.min(480 * textScale, width * .55)
                  : width * .9;
              final panelHeight = wide ? height * .96 : height * .9;
              return Stack(
                children: [
                  if (panelOpened)
                    Positioned(
                      left: wide
                          ? left + width - panelWidth - width * .02
                          : left + (width - panelWidth) / 2,
                      top: top + height - panelHeight - height * .02,
                      width: panelWidth,
                      height: panelHeight,
                      child: ExcludeFocus(
                        excluding: !controller.expanded,
                        child: Offstage(
                          offstage: !controller.expanded,
                          child: TickerMode(
                            enabled: controller.expanded,
                            child: MediaQuery(
                              data: media.copyWith(
                                size: Size(panelWidth, panelHeight),
                                padding: EdgeInsets.zero,
                                viewPadding: EdgeInsets.zero,
                                viewInsets: EdgeInsets.zero,
                              ),
                              child: Material(
                                key: const ValueKey('assistant-floating-panel'),
                                elevation: 12,
                                clipBehavior: Clip.antiAlias,
                                borderRadius: BorderRadius.circular(20),
                                child: AssistantPanel(
                                  registry: widget.registry,
                                  developerBuilder: widget.developerBuilder,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (!controller.expanded)
                    Positioned(
                      left: clamped.dx,
                      top: clamped.dy,
                      width: diameter,
                      height: diameter,
                      child: GestureDetector(
                        onPanUpdate: (details) => setState(() {
                          bubblePosition = Offset(
                            (clamped.dx + details.delta.dx).clamp(
                              left,
                              maxLeft,
                            ),
                            (clamped.dy + details.delta.dy).clamp(top, maxTop),
                          );
                        }),
                        child: Material(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          elevation: 6,
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: IconButton(
                            key: const ValueKey('assistant-bubble'),
                            tooltip: controller.busy
                                ? 'AI 助手正在执行，点击查看；拖动移动'
                                : '打开 AI 助手；拖动移动',
                            onPressed: controller.open,
                            icon: Icon(
                              controller.awaitingApproval
                                  ? Icons.pending_actions
                                  : controller.busy
                                  ? Icons.more_horiz
                                  : Icons.auto_awesome_outlined,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
