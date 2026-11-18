import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;

class FE {
  final String path, name;
  final bool dir;
  final int size, mod;
  FE(this.path, this.name, this.dir, this.size, this.mod);
  String get ext => dir ? '' : p.extension(name).toLowerCase().replaceFirst('.', '');
  factory FE.fromJson(Map m) => FE(m['p'], m['n'], m['d'], (m['s'] as num).toInt(), (m['m'] as num).toInt());
}

String fmt(num b) {
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  var i = 0;
  double v = b.toDouble();
  while (v >= 1024 && i < u.length - 1) { v /= 1024; i++; }
  return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${u[i]}';
}

typedef _S2 = Pointer<Utf8> Function(Pointer<Utf8>, int);
typedef _S2n = Pointer<Utf8> Function(Pointer<Utf8>, Int32);

class Core {
  static final _searchCache = <String, List<FE>>{};
  static DynamicLibrary? _lib;
  static bool _tried = false;
  static DynamicLibrary? get lib {
    if (!_tried) {
      _tried = true;
      try { _lib = DynamicLibrary.open('libfiles_you_core.so'); } catch (_) {}
    }
    return _lib;
  }

  static String _take(Pointer<Utf8> r) {
    final s = r.toDartString();
    lib!.lookupFunction<Void Function(Pointer<Utf8>), void Function(Pointer<Utf8>)>('fy_free')(r);
    return s;
  }

  static Map<String, dynamic> storage(String path) {
    final l = lib;
    if (l == null) return {'total': 0, 'free': 0};
    final a = path.toNativeUtf8();
    final f = l.lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>), Pointer<Utf8> Function(Pointer<Utf8>)>('fy_storage');
    final s = _take(f(a));
    malloc.free(a);
    return jsonDecode(s);
  }

  static List<FE> list(String path, bool hidden) {
    final l = lib;
    if (l == null) {
      try {
        return Directory(path).listSync().where((e) => hidden || !p.basename(e.path).startsWith('.')).map(_fb).toList();
      } catch (_) { return []; }
    }

    final a = path.toNativeUtf8();
    final f = l.lookupFunction<_S2n, _S2>('fy_list');
    final s = _take(f(a, hidden ? 1 : 0));
    malloc.free(a);
    return (jsonDecode(s) as List).map((e) => FE.fromJson(e)).toList();
  }

  static Future<List<FE>> listAsync(String path, bool hidden) =>
      Isolate.run(() => list(path, hidden));

  static void invalidate(String path) {
    _searchCache.removeWhere((key, _) => key.startsWith('$path|'));
  }

  static FE _fb(FileSystemEntity e) {
    FileStat s;
    try { s = e.statSync(); } catch (_) { s = FileStat.statSync('/'); }
    final d = s.type == FileSystemEntityType.directory;
    return FE(e.path, p.basename(e.path), d, d ? 0 : s.size, s.modified.millisecondsSinceEpoch ~/ 1000);
  }

  static List<FE> search(String root, String q, List<String> exts, bool hidden, int limit) {
    final l = lib;
    if (l == null) {
      final r = <FE>[];
      final ql = q.toLowerCase();
      try {
        for (final e in Directory(root).listSync(recursive: true, followLinks: false)) {
          final n = p.basename(e.path);
          if (!hidden && n.startsWith('.')) continue;
          if (exts.isNotEmpty && !exts.contains(p.extension(n).toLowerCase().replaceFirst('.', ''))) continue;
          if (ql.isNotEmpty && !e.path.toLowerCase().contains(ql)) continue;
          if (ql.isEmpty && e is Directory) continue;
          r.add(_fb(e));
          if (r.length >= limit) break;
        }
      } catch (_) {}
      return r;
    }
    final a = root.toNativeUtf8(), b = q.toNativeUtf8(), c = exts.join(',').toNativeUtf8();
    final f = l.lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, Int32, Int32),
        Pointer<Utf8> Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Utf8>, int, int)>('fy_search');
    final s = _take(f(a, b, c, hidden ? 1 : 0, limit));
    malloc.free(a); malloc.free(b); malloc.free(c);
    return (jsonDecode(s) as List).map((e) => FE.fromJson(e)).toList();
  }

  static Map<String, dynamic> scan(String root) {
    final l = lib;
    if (l == null) return {'photo': 0, 'audio': 0, 'video': 0};
    final a = root.toNativeUtf8();
    final f = l.lookupFunction<Pointer<Utf8> Function(Pointer<Utf8>), Pointer<Utf8> Function(Pointer<Utf8>)>('fy_scan');
    final s = _take(f(a));
    malloc.free(a);
    return jsonDecode(s);
  }

  static Future<List<FE>> searchAsync(String r, String q, List<String> e, bool h, int lim) =>
      () async {
        final key = '$r|$q|${e.join(",")}|$h|$lim';
        final cached = _searchCache[key];
        if (cached != null) return List<FE>.of(cached);
        final result = await Isolate.run(() => search(r, q, e, h, lim));
        _searchCache[key] = result;
        if (_searchCache.length > 24) _searchCache.remove(_searchCache.keys.first);
        return result;
      }();
  static Future<Map<String, dynamic>> scanAsync(String r) => Isolate.run(() => scan(r));

  // FTP (runs on the main isolate; the library is process-global)
  static bool ftpStart(String root, int port, String user, String pass, bool hidden) {
    final l = lib;
    if (l == null) return false;
    final a = root.toNativeUtf8(), u = user.toNativeUtf8(), w = pass.toNativeUtf8();
    final f = l.lookupFunction<Int32 Function(Pointer<Utf8>, Int32, Pointer<Utf8>, Pointer<Utf8>, Int32),
        int Function(Pointer<Utf8>, int, Pointer<Utf8>, Pointer<Utf8>, int)>('fy_ftp_start');
    final r = f(a, port, u, w, hidden ? 1 : 0);
    malloc.free(a); malloc.free(u); malloc.free(w);
    return r == 0;
  }

  static void ftpStop() {
    lib?.lookupFunction<Void Function(), void Function()>('fy_ftp_stop')();
  }
}
