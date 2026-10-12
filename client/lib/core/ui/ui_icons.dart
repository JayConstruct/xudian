import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A shared vector vocabulary. UI packs can replace ui.icon@1; native controls
/// keep their semantic labels and interaction, independent of their artwork.
enum AppGlyph {
  today,
  calendar,
  tasks,
  modules,
  folder,
  inbox,
  settings,
  add,
  close,
  more,
  right,
  left,
  down,
  up,
  search,
  info,
  warning,
  error,
  check,
  delete,
  edit,
  clock,
  school,
  sliders,
  transfer,
  history,
  ai,
  copy,
  pin,
  unpin,
  refresh,
  link,
  code,
  play,
  pause,
  eye,
  download,
  upload,
}

IconData? appIconData(Object? name) => switch (name) {
  'today' => Icons.today_outlined,
  'calendar' || 'date' || 'dateRange' => Icons.calendar_month_outlined,
  'tasks' || 'task' || 'checklist' => Icons.checklist_outlined,
  'modules' || 'module' || 'widgets' => Icons.grid_view_outlined,
  'projects' || 'folder' => Icons.folder_outlined,
  'inbox' => Icons.inbox_outlined,
  'settings' => Icons.settings_outlined,
  'add' => Icons.add_rounded,
  'close' => Icons.close_rounded,
  'more' || 'more_horiz' => Icons.more_horiz,
  'chevronRight' || 'right' => Icons.chevron_right_rounded,
  'chevronLeft' || 'left' => Icons.chevron_left_rounded,
  'expandMore' || 'down' => Icons.expand_more_rounded,
  'expandLess' || 'up' => Icons.expand_less_rounded,
  'search' => Icons.search_rounded,
  'info' => Icons.info_outline,
  'warning' => Icons.warning_amber_rounded,
  'error' => Icons.error_outline,
  'check' || 'success' => Icons.check_rounded,
  'list' => Icons.list_alt_outlined,
  'delete' => Icons.delete_outline,
  'edit' => Icons.edit_outlined,
  'schedule' || 'clock' || 'time' => Icons.schedule_outlined,
  'school' => Icons.school_outlined,
  'tune' || 'sliders' => Icons.tune,
  'importExport' || 'transfer' => Icons.import_export,
  'history' => Icons.history,
  'ai' || 'sparkles' => Icons.auto_awesome_outlined,
  'copy' => Icons.copy_outlined,
  'pin' => Icons.push_pin_outlined,
  'unpin' => Icons.push_pin,
  'refresh' => Icons.refresh_rounded,
  'link' => Icons.link_rounded,
  'code' => Icons.code_rounded,
  'play' => Icons.play_arrow_rounded,
  'pause' => Icons.pause_rounded,
  'eye' => Icons.visibility_outlined,
  'download' => Icons.download_outlined,
  'upload' => Icons.upload_outlined,
  _ => null,
};

String? appIconName(IconData? icon) => icon == null ? null : _glyph(icon)?.name;

AppGlyph? _glyph(IconData icon) {
  if ([
    Icons.today,
    Icons.today_outlined,
    Icons.event,
    Icons.event_outlined,
  ].contains(icon)) {
    return AppGlyph.today;
  }
  if ([
    Icons.calendar_month,
    Icons.calendar_month_outlined,
    Icons.calendar_today,
    Icons.calendar_today_outlined,
    Icons.date_range,
    Icons.date_range_outlined,
  ].contains(icon)) {
    return AppGlyph.calendar;
  }
  if ([
    Icons.task_alt,
    Icons.check_box_outlined,
    Icons.checklist,
    Icons.checklist_outlined,
    Icons.list_alt,
    Icons.list_alt_outlined,
  ].contains(icon)) {
    return AppGlyph.tasks;
  }
  if ([
    Icons.grid_view,
    Icons.grid_view_outlined,
    Icons.grid_view_rounded,
    Icons.widgets,
    Icons.widgets_outlined,
    Icons.extension,
    Icons.extension_outlined,
    Icons.apps,
    Icons.dashboard_outlined,
  ].contains(icon)) {
    return AppGlyph.modules;
  }
  if ([Icons.folder, Icons.folder_outlined].contains(icon)) {
    return AppGlyph.folder;
  }
  if ([Icons.inbox, Icons.inbox_outlined].contains(icon)) return AppGlyph.inbox;
  if ([Icons.settings, Icons.settings_outlined].contains(icon)) {
    return AppGlyph.settings;
  }
  if ([Icons.add, Icons.add_rounded, Icons.add_circle_outline].contains(icon)) {
    return AppGlyph.add;
  }
  if ([Icons.close, Icons.close_rounded, Icons.clear].contains(icon)) {
    return AppGlyph.close;
  }
  if ([
    Icons.more_horiz,
    Icons.more_horiz_rounded,
    Icons.more_vert,
  ].contains(icon)) {
    return AppGlyph.more;
  }
  if ([
    Icons.chevron_right,
    Icons.chevron_right_rounded,
    Icons.arrow_forward_ios,
    Icons.arrow_forward_ios_rounded,
  ].contains(icon)) {
    return AppGlyph.right;
  }
  if ([
    Icons.chevron_left,
    Icons.chevron_left_rounded,
    Icons.arrow_back_ios,
    Icons.arrow_back_ios_new,
    Icons.arrow_back,
    Icons.arrow_back_rounded,
  ].contains(icon)) {
    return AppGlyph.left;
  }
  if ([
    Icons.expand_more,
    Icons.expand_more_rounded,
    Icons.keyboard_arrow_down,
    Icons.arrow_drop_down,
  ].contains(icon)) {
    return AppGlyph.down;
  }
  if ([
    Icons.expand_less,
    Icons.expand_less_rounded,
    Icons.keyboard_arrow_up,
  ].contains(icon)) {
    return AppGlyph.up;
  }
  if ([
    Icons.search,
    Icons.search_rounded,
    Icons.search_outlined,
  ].contains(icon)) {
    return AppGlyph.search;
  }
  if ([
    Icons.info,
    Icons.info_outline,
    Icons.info_outlined,
    Icons.info_outline_rounded,
  ].contains(icon)) {
    return AppGlyph.info;
  }
  if ([
    Icons.warning,
    Icons.warning_amber,
    Icons.warning_amber_rounded,
    Icons.warning_amber_outlined,
    Icons.warning_outlined,
  ].contains(icon)) {
    return AppGlyph.warning;
  }
  if ([
    Icons.error,
    Icons.error_outline,
    Icons.error_outlined,
    Icons.error_outline_rounded,
    Icons.cancel_outlined,
  ].contains(icon)) {
    return AppGlyph.error;
  }
  if ([
    Icons.check,
    Icons.check_rounded,
    Icons.done,
    Icons.check_circle_outline,
    Icons.check_circle_outlined,
    Icons.check_circle_outline_rounded,
  ].contains(icon)) {
    return AppGlyph.check;
  }
  if ([
    Icons.delete,
    Icons.delete_outline,
    Icons.delete_outlined,
  ].contains(icon)) {
    return AppGlyph.delete;
  }
  if ([Icons.edit, Icons.edit_outlined, Icons.edit_rounded].contains(icon)) {
    return AppGlyph.edit;
  }
  if ([
    Icons.schedule,
    Icons.schedule_outlined,
    Icons.access_time,
    Icons.access_time_rounded,
  ].contains(icon)) {
    return AppGlyph.clock;
  }
  if ([Icons.school, Icons.school_outlined].contains(icon)) {
    return AppGlyph.school;
  }
  if ([Icons.tune, Icons.tune_rounded, Icons.filter_list].contains(icon)) {
    return AppGlyph.sliders;
  }
  if ([
    Icons.import_export,
    Icons.swap_vert,
    Icons.unfold_more,
  ].contains(icon)) {
    return AppGlyph.transfer;
  }
  if ([Icons.history, Icons.history_rounded, Icons.restore].contains(icon)) {
    return AppGlyph.history;
  }
  if ([Icons.auto_awesome, Icons.auto_awesome_outlined].contains(icon)) {
    return AppGlyph.ai;
  }
  if ([
    Icons.copy,
    Icons.copy_outlined,
    Icons.content_copy,
    Icons.content_copy_outlined,
    Icons.copy_all_rounded,
  ].contains(icon)) {
    return AppGlyph.copy;
  }
  if ([Icons.push_pin_outlined].contains(icon)) return AppGlyph.pin;
  if ([Icons.push_pin].contains(icon)) return AppGlyph.unpin;
  if ([Icons.refresh, Icons.refresh_rounded, Icons.replay].contains(icon)) {
    return AppGlyph.refresh;
  }
  if ([Icons.link, Icons.link_rounded, Icons.open_in_new].contains(icon)) {
    return AppGlyph.link;
  }
  if ([Icons.code, Icons.code_rounded].contains(icon)) return AppGlyph.code;
  if ([Icons.play_arrow, Icons.play_arrow_rounded].contains(icon)) {
    return AppGlyph.play;
  }
  if ([Icons.pause, Icons.pause_rounded].contains(icon)) return AppGlyph.pause;
  if ([Icons.visibility, Icons.visibility_outlined].contains(icon)) {
    return AppGlyph.eye;
  }
  if ([
    Icons.download,
    Icons.download_outlined,
    Icons.file_download_outlined,
  ].contains(icon)) {
    return AppGlyph.download;
  }
  if ([
    Icons.upload,
    Icons.upload_outlined,
    Icons.file_upload_outlined,
  ].contains(icon)) {
    return AppGlyph.upload;
  }
  return null;
}

/// Compatible with IconData-based destinations; known symbols use our vectors.
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
    this.textDirection,
    this.selected = false,
  });
  final IconData? icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;
  final TextDirection? textDirection;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final glyph = icon == null ? null : _glyph(icon!);
    if (glyph == null) {
      return Icon(
        icon,
        size: size,
        color: color,
        semanticLabel: semanticLabel,
        textDirection: textDirection,
      );
    }
    final inherited = IconTheme.of(context);
    final extent = size ?? inherited.size ?? 24;
    final tint =
        color ?? inherited.color ?? Theme.of(context).colorScheme.onSurface;
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: SizedBox.square(
          dimension: extent,
          child: CustomPaint(
            painter: AppIconPainter(
              glyph: glyph,
              color: tint.withValues(alpha: tint.a * (inherited.opacity ?? 1)),
              selected: selected,
              highContrast: MediaQuery.maybeOf(context)?.highContrast ?? false,
            ),
          ),
        ),
      ),
    );
  }
}

/// Named symbols are public UI data, so modules never depend on a font codepoint.
class AppSymbolIcon extends StatelessWidget {
  const AppSymbolIcon(
    this.name, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
    this.selected = false,
  });
  final Object? name;
  final double? size;
  final Color? color;
  final String? semanticLabel;
  final bool selected;
  @override
  Widget build(BuildContext context) => AppIcon(
    appIconData(name),
    size: size,
    color: color,
    semanticLabel: semanticLabel,
    selected: selected,
  );
}

class AppIconPainter extends CustomPainter {
  const AppIconPainter({
    required this.glyph,
    required this.color,
    this.selected = false,
    this.highContrast = false,
  });
  final AppGlyph glyph;
  final Color color;
  final bool selected, highContrast;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    final extent = math.min(size.width, size.height);
    canvas.translate((size.width - extent) / 2, (size.height - extent) / 2);
    canvas.scale(extent / 24, extent / 24);
    final ink = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = highContrast ? 2.2 : 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void line(double x, double y, double xx, double yy) =>
        canvas.drawLine(Offset(x, y), Offset(xx, yy), ink);
    void route(List<double> points, {bool close = false}) {
      final path = Path()..moveTo(points[0], points[1]);
      for (var i = 2; i < points.length; i += 2) {
        path.lineTo(points[i], points[i + 1]);
      }
      if (close) path.close();
      canvas.drawPath(path, ink);
    }

    void box(
      double x,
      double y,
      double width,
      double height, [
      double radius = 2.5,
    ]) => canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, width, height),
        Radius.circular(radius),
      ),
      ink,
    );
    void circle(double x, double y, double radius) =>
        canvas.drawCircle(Offset(x, y), radius, ink);
    void dot(double x, double y, [double radius = .9]) =>
        canvas.drawCircle(Offset(x, y), radius, Paint()..color = color);
    void arc(
      double x,
      double y,
      double width,
      double height,
      double start,
      double sweep,
    ) => canvas.drawArc(
      Rect.fromLTWH(x, y, width, height),
      start,
      sweep,
      false,
      ink,
    );
    void star(double x, double y, double radius) => route([
      x,
      y - radius,
      x + radius * .3,
      y - radius * .3,
      x + radius,
      y,
      x + radius * .3,
      y + radius * .3,
      x,
      y + radius,
      x - radius * .3,
      y + radius * .3,
      x - radius,
      y,
      x - radius * .3,
      y - radius * .3,
    ], close: true);
    switch (glyph) {
      case AppGlyph.today:
      case AppGlyph.calendar:
        if (selected) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              const Rect.fromLTWH(4, 8, 16, 12),
              const Radius.circular(2),
            ),
            Paint()..color = color.withValues(alpha: .12),
          );
        }
        box(3.5, 4.5, 17, 16, 2.4);
        line(3.5, 9, 20.5, 9);
        line(8, 2.8, 8, 6);
        line(16, 2.8, 16, 6);
        if (glyph == AppGlyph.today) {
          box(7.5, 12, 4, 4, .7);
        } else {
          for (final y in [12.5, 16.5]) {
            for (final x in [7.5, 12.0, 16.5]) {
              dot(x, y, .65);
            }
          }
        }
      case AppGlyph.tasks:
        box(3.8, 3.8, 16.4, 16.4, 3);
        route([7.4, 12.2, 10.4, 15.2, 16.8, 8.8]);
      case AppGlyph.modules:
        for (final y in [3.5, 13.5]) {
          for (final x in [3.5, 13.5]) {
            box(x, y, 7, 7, 1.8);
          }
        }
      case AppGlyph.folder:
        final path = Path()
          ..moveTo(3, 8)
          ..lineTo(3, 6)
          ..quadraticBezierTo(3, 4, 5, 4)
          ..lineTo(9, 4)
          ..lineTo(11, 6)
          ..lineTo(19, 6)
          ..quadraticBezierTo(21, 6, 21, 8)
          ..lineTo(21, 18)
          ..quadraticBezierTo(21, 20, 19, 20)
          ..lineTo(5, 20)
          ..quadraticBezierTo(3, 20, 3, 18)
          ..close();
        canvas.drawPath(path, ink);
        line(3, 9, 21, 9);
      case AppGlyph.inbox:
        route([3, 13, 6, 5, 18, 5, 21, 13, 21, 19, 3, 19], close: true);
        route([3, 13, 8, 13, 10, 16, 14, 16, 16, 13, 21, 13]);
      case AppGlyph.settings:
        final path = Path();
        for (var i = 0; i < 48; i++) {
          final angle = i * math.pi / 24;
          final radius = (i % 6 == 0 || i % 6 == 5) ? 9.4 : 7.5;
          final x = 12 + radius * math.cos(angle),
              y = 12 + radius * math.sin(angle);
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
        canvas.drawPath(path, ink);
        circle(12, 12, 3);
      case AppGlyph.add:
        line(5, 12, 19, 12);
        line(12, 5, 12, 19);
      case AppGlyph.close:
        line(6, 6, 18, 18);
        line(18, 6, 6, 18);
      case AppGlyph.more:
        dot(5, 12, 1.4);
        dot(12, 12, 1.4);
        dot(19, 12, 1.4);
      case AppGlyph.right:
        route([9, 5, 16, 12, 9, 19]);
      case AppGlyph.left:
        route([15, 5, 8, 12, 15, 19]);
      case AppGlyph.down:
        route([5, 9, 12, 16, 19, 9]);
      case AppGlyph.up:
        route([5, 15, 12, 8, 19, 15]);
      case AppGlyph.search:
        circle(10.5, 10.5, 6.5);
        line(15.5, 15.5, 20.5, 20.5);
      case AppGlyph.info:
        circle(12, 12, 9);
        dot(12, 7);
        line(12, 11, 12, 17);
      case AppGlyph.warning:
        final p = Path()
          ..moveTo(10.3, 4)
          ..quadraticBezierTo(12, 1, 13.7, 4)
          ..lineTo(21, 17)
          ..quadraticBezierTo(22.5, 20, 19, 20)
          ..lineTo(5, 20)
          ..quadraticBezierTo(1.5, 20, 3, 17)
          ..close();
        canvas.drawPath(p, ink);
        line(12, 8, 12, 13);
        dot(12, 16);
      case AppGlyph.error:
        circle(12, 12, 9);
        line(8.5, 8.5, 15.5, 15.5);
        line(15.5, 8.5, 8.5, 15.5);
      case AppGlyph.check:
        route([4.5, 12, 9.5, 17, 19.5, 7]);
      case AppGlyph.delete:
        line(4, 6, 20, 6);
        box(9, 3, 6, 3, 1);
        route([6, 6, 7, 20, 17, 20, 18, 6]);
        line(10, 10, 10, 16);
        line(14, 10, 14, 16);
      case AppGlyph.edit:
        route([4, 20, 5, 15, 16, 4, 20, 8, 9, 19, 4, 20]);
        line(13.5, 6.5, 17.5, 10.5);
      case AppGlyph.clock:
        circle(12, 12, 9);
        route([12, 6, 12, 12, 16, 14]);
      case AppGlyph.school:
        route([2.5, 9, 12, 4, 21.5, 9, 12, 14], close: true);
        route([6, 11, 6, 17, 12, 20, 18, 17, 18, 11]);
        line(21.5, 9, 21.5, 16);
      case AppGlyph.sliders:
        line(3, 6, 7, 6);
        line(11, 6, 21, 6);
        circle(9, 6, 2);
        line(3, 12, 13, 12);
        line(17, 12, 21, 12);
        circle(15, 12, 2);
        line(3, 18, 7, 18);
        line(11, 18, 21, 18);
        circle(9, 18, 2);
      case AppGlyph.transfer:
        route([3, 7, 7, 3, 11, 7]);
        line(7, 3, 7, 20);
        route([13, 17, 17, 21, 21, 17]);
        line(17, 4, 17, 21);
      case AppGlyph.history:
        arc(4, 4, 16, 16, -math.pi * .8, math.pi * 1.8);
        route([3, 4, 3, 9, 8, 9]);
        route([12, 7, 12, 12, 16, 14]);
      case AppGlyph.ai:
        star(10, 12, 7);
        star(19, 5, 2.5);
        star(19, 19, 2);
      case AppGlyph.copy:
        box(8, 8, 12, 13, 2);
        route([15, 5, 15, 3, 3, 3, 3, 15, 5, 15]);
      case AppGlyph.pin:
      case AppGlyph.unpin:
        route([8, 3, 16, 3, 15, 10, 18, 14, 6, 14, 9, 10, 8, 3]);
        line(12, 14, 12, 21);
        if (glyph == AppGlyph.unpin) line(3, 3, 21, 21);
      case AppGlyph.refresh:
        arc(4, 4, 16, 16, math.pi * .25, math.pi * 1.65);
        route([15, 4, 20, 4, 20, 9]);
      case AppGlyph.link:
        arc(3, 6, 12, 12, math.pi * .25, math.pi * 1.5);
        arc(9, 6, 12, 12, -math.pi * .75, math.pi * 1.5);
        line(9, 12, 15, 12);
      case AppGlyph.code:
        route([8, 6, 2, 12, 8, 18]);
        route([16, 6, 22, 12, 16, 18]);
        line(14, 4, 10, 20);
      case AppGlyph.play:
        route([7, 4, 20, 12, 7, 20], close: true);
      case AppGlyph.pause:
        line(8, 4, 8, 20);
        line(16, 4, 16, 20);
      case AppGlyph.eye:
        final p = Path()
          ..moveTo(2, 12)
          ..quadraticBezierTo(12, -1, 22, 12)
          ..quadraticBezierTo(12, 25, 2, 12);
        canvas.drawPath(p, ink);
        circle(12, 12, 3);
      case AppGlyph.download:
        route([7, 11, 12, 16, 17, 11]);
        line(12, 3, 12, 16);
        route([4, 16, 4, 21, 20, 21, 20, 16]);
      case AppGlyph.upload:
        route([7, 8, 12, 3, 17, 8]);
        line(12, 3, 12, 16);
        route([4, 16, 4, 21, 20, 21, 20, 16]);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(AppIconPainter oldDelegate) =>
      glyph != oldDelegate.glyph ||
      color != oldDelegate.color ||
      selected != oldDelegate.selected ||
      highContrast != oldDelegate.highContrast;
}
