import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'core.dart';
import 'settings.dart';

String _detectRoot() {
  if (!Platform.isAndroid) return Platform.environment['HOME'] ?? '/';
  for (final c in ['/storage/emulated/0', '/sdcard', '/storage/self/primary']) {
    if (Directory(c).existsSync()) return c;
  }
  return '/storage/emulated/0';
}

final String root = _detectRoot();
final String trashDir = '$root/.FilesYouTrash';

const imgExt = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'ico'};
const imgAll = {...imgExt, 'heic', 'heif', 'avif'};
const audExt = {'mp3', 'wav', 'flac', 'm4a', 'ogg', 'aac', 'opus', 'amr', 'wma'};
const vidExt = {'mp4', 'mkv', 'avi', 'mov', 'webm', '3gp', 'm4v'};

Future<T?> go<T>(BuildContext c, Widget w) => Navigator.push<T>(
      c,
      PageRouteBuilder<T>(
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 280),
        pageBuilder: (_, __, ___) => w,
        transitionsBuilder: (_, a, __, child) {
          final cv = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
          return FadeTransition(
            opacity: cv,
            child: SlideTransition(position: Tween(begin: const Offset(0, .05), end: Offset.zero).animate(cv), child: child),
          );
        },
      ),
    );

void snack(BuildContext c, String m) {
  ScaffoldMessenger.of(c).clearSnackBars();
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m), behavior: SnackBarBehavior.floating, margin: const EdgeInsets.fromLTRB(20, 0, 20, 110)));
}

/// Pressable with scale animation and haptics.
class Tap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap, onLong;
  final double scale;
  const Tap({super.key, required this.child, this.onTap, this.onLong, this.scale = .94});
  @override
  State<Tap> createState() => _TapState();
}

class _TapState extends State<Tap> {
  bool down = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => down = true),
        onTapUp: (_) => setState(() => down = false),
        onTapCancel: () => setState(() => down = false),
        onTap: widget.onTap == null ? null : () { HapticFeedback.selectionClick(); widget.onTap!(); },
        onLongPress: widget.onLong == null ? null : () { HapticFeedback.mediumImpact(); widget.onLong!(); },
        child: AnimatedScale(scale: down ? widget.scale : 1, duration: const Duration(milliseconds: 130), curve: Curves.easeOut, child: widget.child),
      );
}

/// Staggered fade/slide-in.
class Appear extends StatelessWidget {
  final int i;
  final Widget child;
  const Appear({super.key, this.i = 0, required this.child});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 380 + min(i, 10) * 45),
        curve: Curves.easeOutCubic,
        builder: (_, v, c) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * 20), child: c)),
        child: child,
      );
}

class RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? label;
  const RoundBtn(this.icon, this.onTap, {super.key, this.label});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: label,
      button: true,
      child: Tap(onTap: onTap, child: Container(width: 48, height: 48, decoration: BoxDecoration(color: cs.surfaceContainerHigh, shape: BoxShape.circle), child: Icon(icon, color: cs.onSurface))),
    );
  }
}

IconData iconFor(FE e) {
  if (e.dir) return Icons.folder_rounded;
  final x = e.ext;
  if (imgAll.contains(x) || x == 'svg') return Icons.image_rounded;
  if (audExt.contains(x)) return Icons.music_note_rounded;
  if (vidExt.contains(x)) return Icons.movie_rounded;
  switch (x) {
    case 'apk': case 'xapk': case 'apks': return Icons.android_rounded;
    case 'zip': case 'rar': case '7z': case 'tar': case 'gz': return Icons.folder_zip_rounded;
    case 'html': case 'htm': return Icons.html_rounded;
    case 'md': case 'markdown': return Icons.article_rounded;
    case 'pdf': return Icons.picture_as_pdf_rounded;
    case 'plugin': case 'json': case 'dart': case 'js': case 'py': case 'rs': case 'kt': case 'java': case 'xml': case 'css': case 'sh': case 'yaml': case 'yml': return Icons.code_rounded;
    case 'txt': case 'log': return Icons.notes_rounded;
    default: return Icons.insert_drive_file_rounded;
  }
}

class Leading extends StatelessWidget {
  final FE e;
  final double size;
  final bool selected;
  const Leading(this.e, this.size, {super.key, this.selected = false});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = BorderRadius.circular(size * .32);
    Widget tile(Color bg, IconData i, Color fg, double k, Key key) =>
        Container(key: key, width: size, height: size, decoration: BoxDecoration(color: bg, borderRadius: r), child: Icon(i, size: size * k, color: fg));
    Widget inner;
    if (selected) {
      inner = tile(cs.primary, Icons.check_rounded, cs.onPrimary, .55, const ValueKey('s'));
    } else if (e.dir) {
      final c = Color(st.folder);
      inner = tile(c.withOpacity(.2), Icons.folder_rounded, c, .72, const ValueKey('d'));
    } else if (imgExt.contains(e.ext)) {
      inner = ClipRRect(
        key: ValueKey(e.path),
        borderRadius: r,
        child: Image.file(File(e.path), width: size, height: size, fit: BoxFit.cover, cacheWidth: (size * 2.5).round(),
            errorBuilder: (_, __, ___) => tile(cs.primaryContainer, iconFor(e), cs.onPrimaryContainer, .5, const ValueKey('f'))),
      );
    } else {
      inner = tile(cs.primaryContainer, iconFor(e), cs.onPrimaryContainer, .5, ValueKey('f${e.ext}'));
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 220), child: inner);
  }
}

String fmtDate(int sec) {
  final d = DateTime.fromMillisecondsSinceEpoch(sec * 1000);
  String z(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${z(d.month)}-${z(d.day)} ${z(d.hour)}:${z(d.minute)}';
}

String base(String path) => p.basename(path);
