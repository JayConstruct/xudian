import 'package:flutter/material.dart';

import '../../app/design_system.dart';
import '../ui/content_colors.dart';
import '../ui/workspace_chrome.dart';
import 'module_package.dart';

/// Half-open row intervals; every overlapping block remains selectable.
class TimeGrid extends StatefulWidget {
  const TimeGrid({
    super.key,
    required this.columns,
    required this.rows,
    required this.blocks,
    required this.onEvent,
    this.corner = const {},
    this.options = const {},
    this.bottomInset = 0,
  });
  final List<Map<String, Object?>> columns, rows, blocks;
  final Map<String, Object?> corner, options;
  final double bottomInset;
  final void Function(Object?) onEvent;
  @override
  State<TimeGrid> createState() => _TimeGridState();
}

class _TimeGridState extends State<TimeGrid> {
  final horizontal = ScrollController(), header = ScrollController();
  final vertical = WorkspaceChromeScrollController();
  Object? _handledScrollRequest;
  Object? _extentGeometry;
  double _chromeMaxExtent = 0;

  double _trailingPadding(
    BuildContext context,
    BoxConstraints constraints,
    double gridHeight,
    double headerHeight,
  ) {
    final inset = widget.bottomInset.clamp(0.0, 400.0);
    if (!constraints.hasBoundedHeight) return inset;
    // The app's header and dock animate inside a stable window. Growing the
    // viewport must not shrink the scroll range beneath an ongoing drag: that
    // boundary correction moves rows opposite to the user's reading direction.
    // Put only the freed space after the final row. Window, keyboard, font and
    // timetable geometry changes establish a fresh range instead.
    final geometry = (
      MediaQuery.sizeOf(context),
      MediaQuery.viewInsetsOf(context),
      MediaQuery.textScalerOf(context).scale(14),
      constraints.maxWidth,
      gridHeight,
      headerHeight,
    );
    if (_extentGeometry != geometry) {
      _extentGeometry = geometry;
      _chromeMaxExtent = 0;
    }
    final viewport = (constraints.maxHeight - headerHeight).clamp(
      0.0,
      double.infinity,
    );
    final naturalExtent = (gridHeight + inset - viewport).clamp(
      0.0,
      double.infinity,
    );
    if (naturalExtent > _chromeMaxExtent) _chromeMaxExtent = naturalExtent;
    return (_chromeMaxExtent + viewport - gridHeight).clamp(
      inset,
      double.infinity,
    );
  }

  List<Map<String, Object?>> get columns => widget.columns;
  List<Map<String, Object?>> get rows => widget.rows;
  List<Map<String, Object?>> get blocks => widget.blocks;
  @override
  void initState() {
    super.initState();
    horizontal.addListener(_syncHeader);
  }

  void _syncHeader() {
    if (horizontal.hasClients && header.hasClients) {
      final target = horizontal.offset
          .clamp(0, header.position.maxScrollExtent)
          .toDouble();
      if ((header.offset - target).abs() > .1) header.jumpTo(target);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    vertical.chrome = WorkspaceChromeScrollScope.maybeOf(context);
  }

  @override
  void dispose() {
    horizontal.dispose();
    header.dispose();
    vertical.dispose();
    super.dispose();
  }

  double dimension(String key, double fallback, double min, double max) =>
      (widget.options[key] as num? ?? fallback).toDouble().clamp(min, max);

  @override
  Widget build(BuildContext context) {
    final rowHeight = dimension('rowHeight', 72, 48, 160),
        headerHeight = dimension('headerHeight', 48, 40, 120),
        labelWidth = dimension('labelWidth', 86, 36, 120);
    final columnIds = columns.map((c) => c['id']).toList();
    final valid = blocks
        .where(
          (b) =>
              columnIds.contains(b['column']) &&
              b['start'] is int &&
              b['end'] is int &&
              (b['start'] as int) >= 0 &&
              (b['end'] as int) > (b['start'] as int) &&
              (b['end'] as int) <= rows.length,
        )
        .toList();
    final positions = <Map<String, Object?>, List<int>>{};
    for (final column in columnIds) {
      final items = valid.where((b) => b['column'] == column).toList()
        ..sort((a, b) => (a['start'] as int).compareTo(b['start'] as int));
      var group = <Map<String, Object?>>[], end = -1;
      void place() {
        final lanes = <int>[];
        for (final b in group) {
          var lane = lanes.indexWhere((end) => end <= (b['start'] as int));
          if (lane < 0) {
            lane = lanes.length;
            lanes.add(b['end'] as int);
          } else {
            lanes[lane] = b['end'] as int;
          }
          positions[b] = [lane, 0];
        }
        for (final b in group) {
          positions[b]![1] = lanes.length;
        }
      }

      for (final b in items) {
        if ((b['start'] as int) >= end) {
          place();
          group = [];
        }
        group.add(b);
        end = group.length == 1
            ? b['end'] as int
            : ((b['end'] as int) > end ? b['end'] as int : end);
      }
      place();
    }
    final scheme = Theme.of(context).colorScheme;
    final compact = widget.options['fillWidth'] == true;
    final background = compact ? scheme.surface : Colors.transparent;
    final line = scheme.outlineVariant.withValues(alpha: compact ? .45 : .7);
    final highlight = scheme.primary.withValues(alpha: .06);
    Widget caption(
      Map<String, Object?> value, {
      bool row = false,
      bool corner = false,
    }) {
      final title = value['title'];
      return ColoredBox(
        color: value['highlight'] == true ? highlight : Colors.transparent,
        child: Center(
          child: title == null
              ? Text(
                  '${value['label'] ?? ''}',
                  textAlign: TextAlign.center,
                  style:
                      (row
                              ? Theme.of(context).textTheme.labelSmall
                              : Theme.of(context).textTheme.labelLarge)
                          ?.copyWith(
                            color: value['highlight'] == true
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$title',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: row
                                ? 17
                                : corner
                                ? 14
                                : 18,
                            height: 1.1,
                            color: value['highlight'] == true
                                ? scheme.primary
                                : scheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (value['subtitle'] != null) ...[
                          const SizedBox(height: 5),
                          Text(
                            '${value['subtitle']}',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = (constraints.maxWidth - labelWidth).clamp(
          0.0,
          double.infinity,
        );
        final minimum = dimension('minColumnWidth', 68, 52, 320);
        final visible = (available / minimum).floor().clamp(
          1,
          columns.isEmpty ? 1 : columns.length,
        );
        final fitColumns = widget.options['fitColumns'] == true;
        final columnWidth = fitColumns
            ? available / (columns.isEmpty ? 1 : columns.length)
            : compact
            ? (available / visible).clamp(minimum, 320.0)
            : 150.0;
        // Explicit requests override a restored offset once; ordinary renders
        // keep the user's horizontal position and synchronize the fixed dates.
        final request = widget.options['scrollRequest'];
        final targetColumn = columnIds.indexOf(
          widget.options['scrollToColumn'],
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (request != null &&
              request != _handledScrollRequest &&
              targetColumn >= 0 &&
              horizontal.hasClients) {
            _handledScrollRequest = request;
            horizontal.jumpTo(
              (targetColumn * columnWidth)
                  .clamp(0, horizontal.position.maxScrollExtent)
                  .toDouble(),
            );
          }
          _syncHeader();
        });
        final gridWidth = fitColumns && columns.isNotEmpty
            ? available
            : columnWidth * columns.length;
        final gridHeight = rowHeight * rows.length;
        final trailingPadding = _trailingPadding(
          context,
          constraints,
          gridHeight,
          headerHeight,
        );
        final heading = SizedBox(
          height: headerHeight,
          child: Row(
            children: [
              SizedBox(
                width: labelWidth,
                child: caption(widget.corner, corner: true),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: header,
                  scrollDirection: Axis.horizontal,
                  physics: const NeverScrollableScrollPhysics(),
                  child: Row(
                    children: [
                      for (final column in columns)
                        Container(
                          width: columnWidth,
                          height: headerHeight,
                          decoration: BoxDecoration(
                            border: Border(left: BorderSide(color: line)),
                          ),
                          child: caption(column),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
        final body = SingleChildScrollView(
          key: const PageStorageKey('time-grid-vertical'),
          controller: vertical,
          physics: const _EndAnchoredScrollPhysics(),
          padding: EdgeInsets.only(bottom: trailingPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: labelWidth,
                child: Column(
                  children: [
                    for (final row in rows)
                      Container(
                        height: rowHeight,
                        decoration: BoxDecoration(
                          border: Border(top: BorderSide(color: line)),
                        ),
                        child: caption(row, row: true),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  key: const PageStorageKey('time-grid-horizontal'),
                  controller: horizontal,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: gridWidth,
                    height: gridHeight,
                    child: Stack(
                      children: [
                        for (var c = 0; c < columns.length; c++)
                          Positioned(
                            left: c * columnWidth,
                            top: 0,
                            width: columnWidth,
                            height: gridHeight,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: columns[c]['highlight'] == true
                                    ? highlight
                                    : null,
                                border: Border(left: BorderSide(color: line)),
                              ),
                            ),
                          ),
                        for (var r = 0; r < rows.length; r++)
                          Positioned(
                            left: 0,
                            top: r * rowHeight,
                            width: gridWidth,
                            height: rowHeight,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border(top: BorderSide(color: line)),
                              ),
                            ),
                          ),
                        for (final b in valid)
                          Builder(
                            builder: (context) {
                              final column = columnIds.indexOf(b['column']),
                                  position = positions[b]!,
                                  width = columnWidth / position[1];
                              final color = ContentColors.accent(
                                b['colorKey'] ??
                                    b['courseId'] ??
                                    b['id'] ??
                                    b['title'],
                                color: b['color'],
                              );
                              final courseSurface = ContentColors.surface(
                                color,
                                scheme,
                              );
                              final courseForeground = ContentColors.foreground(
                                color,
                                courseSurface,
                                scheme.onSurface,
                              );
                              final courseShape = AppDesign.smoothShape(
                                radius: AppDesign.compactRadius,
                                side: BorderSide(
                                  color: courseForeground.withValues(alpha: .2),
                                ),
                              );
                              final label =
                                  '${columns[column]['label'] ?? columns[column]['title']}，第${(b['start'] as int) + 1}到${b['end']}节，${b['title']}，${b['subtitle'] ?? ''}';
                              return Positioned(
                                left:
                                    column * columnWidth +
                                    position[0] * width +
                                    2,
                                top: (b['start'] as int) * rowHeight + 2,
                                width: width - 4,
                                height:
                                    ((b['end'] as int) - (b['start'] as int)) *
                                        rowHeight -
                                    4,
                                child: Semantics(
                                  button: true,
                                  label: label,
                                  child: Tooltip(
                                    message: label,
                                    child: Material(
                                      color: courseSurface,
                                      shape: courseShape,
                                      clipBehavior: Clip.antiAlias,
                                      child: InkWell(
                                        customBorder: courseShape,
                                        onTap: () => widget.onEvent(b['event']),
                                        child: Padding(
                                          padding: const EdgeInsets.all(2),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              ConstrainedBox(
                                                constraints: BoxConstraints(
                                                  maxHeight:
                                                      ((b['end'] as int) -
                                                              (b['start']
                                                                  as int)) *
                                                          rowHeight -
                                                      8,
                                                ),
                                                child: Text(
                                                  '${b['title']}',
                                                  maxLines: 4,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: compact
                                                        ? 12.5
                                                        : null,
                                                    height: 1.3,
                                                    color: courseForeground,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              Flexible(
                                                child: Text(
                                                  '${b['subtitle'] ?? ''}',
                                                  maxLines: 4,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: compact
                                                        ? 11
                                                        : null,
                                                    height: 1.35,
                                                    color: scheme.onSurface,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
        return Semantics(
          container: true,
          explicitChildNodes: true,
          child: ColoredBox(
            color: background,
            child: Column(
              mainAxisSize: constraints.hasBoundedHeight
                  ? MainAxisSize.max
                  : MainAxisSize.min,
              children: [
                heading,
                if (constraints.hasBoundedHeight)
                  Expanded(child: body)
                else
                  SizedBox(
                    height: gridHeight + widget.bottomInset.clamp(0, 400),
                    child: body,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Keep the final row visible when restoring chrome changes both the viewport
/// and trailing padding. Layout corrections do not count as user scrolling.
class _EndAnchoredScrollPhysics extends ScrollPhysics {
  const _EndAnchoredScrollPhysics({super.parent});

  @override
  _EndAnchoredScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _EndAnchoredScrollPhysics(parent: buildParent(ancestor));

  @override
  double adjustPositionForNewDimensions({
    required ScrollMetrics oldPosition,
    required ScrollMetrics newPosition,
    required bool isScrolling,
    required double velocity,
  }) {
    if (oldPosition.maxScrollExtent > 0 &&
        (oldPosition.pixels - oldPosition.maxScrollExtent).abs() < 1 &&
        oldPosition.maxScrollExtent != newPosition.maxScrollExtent) {
      return newPosition.maxScrollExtent;
    }
    return super.adjustPositionForNewDimensions(
      oldPosition: oldPosition,
      newPosition: newPosition,
      isScrolling: isScrolling,
      velocity: velocity,
    );
  }
}

List<Map<String, Object?>> objects(Object? value) =>
    (value as List? ?? []).map(object).toList();
