import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'common.dart';
import 'core.dart';
import 'l10n.dart';
import 'settings.dart';
import 'viewers.dart';

class Manager extends StatefulWidget {
  final String path, title;
  final List<String> exts;
  final bool recent, showHiddenForce;
  const Manager({super.key, required this.path, required this.title, this.exts = const [], this.recent = false, this.showHiddenForce = false});
  @override
  State<Manager> createState() => _ManagerState();
}

class _ManagerState extends State<Manager> {
  late String cur = widget.path;
  List<FE> items = [];
  final sel = <String>{};
  bool grid = false, asc = false, hidden = false, searching = false, loading = false;
  double density = 1;
  String sort = 'date', q = '';
  final qc = TextEditingController();
  Timer? deb;
  int gen = 0;
  static List<String> clip = [];
  static bool clipCut = false;
  bool get virtual => widget.exts.isNotEmpty || widget.recent;

  @override
  void initState() {
    super.initState();
    hidden = widget.showHiddenForce;
    _prefs();
    _load();
  }

  @override
  void dispose() { deb?.cancel(); qc.dispose(); super.dispose(); }

  void _prefs() {
    final s = st.pr.getString('fv:$cur') ?? st.pr.getString('fv:*');
    if (s != null) {
      final a = s.split('|');
      if (a.length >= 4) {
        grid = a[0] == '1'; sort = a[1]; asc = a[2] == '1'; hidden = a[3] == '1' || widget.showHiddenForce;
        if (a.length > 4) density = double.tryParse(a[4])?.clamp(.75, 1.35) ?? 1;
      }
    }
  }

  Future<void> _savePrefs({bool all = false}) async {
    final v = '${grid ? 1 : 0}|$sort|${asc ? 1 : 0}|${hidden ? 1 : 0}|${density.toStringAsFixed(2)}';
    if (all) {
      for (final k in st.pr.getKeys().where((k) => k.startsWith('fv:')).toList()) { await st.pr.remove(k); }
      await st.pr.setString('fv:*', v);
    } else {
      await st.pr.setString('fv:$cur', v);
    }
  }

  Future<void> _load() async {
    final my = ++gen;
    setState(() => loading = true);
    List<FE> r;
    if (q.isNotEmpty || virtual) {
      r = await Core.searchAsync(cur, q, widget.exts, hidden, widget.recent ? 4000 : 2000);
      if (widget.recent && q.isEmpty) {
        final lim = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 14 * 86400;
        r = r.where((e) => e.mod > lim && !e.dir).toList();
      }
    } else {
      r = await Core.listAsync(cur, hidden);
    }
    if (!mounted || my != gen) return;
    setState(() { items = r; _sort(); loading = false; });
  }

  void _sort() {
    int c(FE a, FE b) {
      switch (sort) {
        case 'size': return a.size.compareTo(b.size);
        case 'date': return a.mod.compareTo(b.mod);
        case 'type': final r = a.ext.compareTo(b.ext); return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        default: return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
    }
    items.sort((a, b) {
      final group = (a.dir ? 0 : 1).compareTo(b.dir ? 0 : 1);
      if (group != 0) return group;
      return asc ? c(a, b) : c(b, a);
    });
  }

  void _cd(String path) {
    cur = path; sel.clear(); qc.clear(); q = ''; searching = false; _prefs(); _load();
  }

  void _changed() {
    Core.invalidate(cur);
    if (mounted) setState(() {});
    _load();
  }

  Future<void> _delete() async {
    Directory(trashDir).createSync(recursive: true);
    final inTrash = cur.startsWith(trashDir);
    for (final path in sel) {
      try {
        final isDir = FileSystemEntity.isDirectorySync(path);
        if (inTrash) {
          isDir ? Directory(path).deleteSync(recursive: true) : File(path).deleteSync();
        } else {
          final dst = '$trashDir/${DateTime.now().millisecondsSinceEpoch}_${p.basename(path)}';
          try { isDir ? Directory(path).renameSync(dst) : File(path).renameSync(dst); } catch (_) {
            if (!isDir) { File(path).copySync(dst); File(path).deleteSync(); }
          }
        }
      } catch (_) {}
    }
    sel.clear();
    if (mounted) snack(context, t('moved_trash'));
    _changed();
  }

  Future<String?> _ask(String title, String init) async {
    final c = TextEditingController(text: init);
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          IconButton.filledTonal(iconSize: 26, onPressed: () => Navigator.pop(d), icon: const Icon(Icons.close_rounded)),
          IconButton.filled(iconSize: 26, onPressed: () => Navigator.pop(d, c.text), icon: const Icon(Icons.check_rounded)),
        ],
      ),
    );
  }

  void _copyRec(String src, String dst) {
    if (FileSystemEntity.isDirectorySync(src)) {
      Directory(dst).createSync(recursive: true);
      for (final e in Directory(src).listSync()) { _copyRec(e.path, '$dst/${p.basename(e.path)}'); }
    } else { File(src).copySync(dst); }
  }

  Future<void> _paste() async {
    for (final s in clip) {
      final dst = '$cur/${p.basename(s)}';
      try {
        if (clipCut) {
          try { FileSystemEntity.isDirectorySync(s) ? Directory(s).renameSync(dst) : File(s).renameSync(dst); } catch (_) {
            _copyRec(s, dst);
            FileSystemEntity.isDirectorySync(s) ? Directory(s).deleteSync(recursive: true) : File(s).deleteSync();
          }
        } else { _copyRec(s, dst); }
      } catch (_) {}
    }
    clip = [];
    _changed();
  }

  Future<void> _rename() async {
    final o = sel.first;
    final n = await _ask(t('rename'), p.basename(o));
    if (n != null && n.isNotEmpty) {
      final d = '${p.dirname(o)}/$n';
      try { FileSystemEntity.isDirectorySync(o) ? Directory(o).renameSync(d) : File(o).renameSync(d); } catch (_) {}
      sel.clear();
      _changed();
    }
  }

  Widget _crumbs() {
    final parts = cur.split('/').where((e) => e.isNotEmpty).toList();
    final cs = Theme.of(context).colorScheme;
    return Wrap(spacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
      for (var i = 0; i < parts.length; i++) ...[
        GestureDetector(
          onTap: virtual ? null : () => _cd('/${parts.sublist(0, i + 1).join('/')}'),
          child: Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(parts[i], style: TextStyle(fontSize: 12, fontWeight: i == parts.length - 1 ? FontWeight.w700 : FontWeight.w400, color: i == parts.length - 1 ? cs.primary : cs.onSurfaceVariant))),
        ),
        if (i < parts.length - 1) Icon(Icons.chevron_right_rounded, size: 14, color: cs.onSurfaceVariant),
      ],
    ]);
  }

  Widget _menu() => PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert_rounded),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        onSelected: (v) async {
          if (v == 'grid') { grid = !grid; }
          else if (v == 'hidden') { hidden = !hidden; _changed(); }
          else if (v == 'all') { await _savePrefs(all: true); if (mounted) snack(context, t('ok')); return; }
          else if (v == 'newf') { final n = await _ask(t('new_folder'), ''); if (n != null && n.isNotEmpty) { Directory('$cur/$n').createSync(); _changed(); } return; }
          else if (v.startsWith('s:')) { final k = v.substring(2); if (sort == k) { asc = !asc; } else { sort = k; asc = k == 'name'; } _sort(); }
          setState(() {});
          _savePrefs();
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'grid', child: Row(children: [Icon(grid ? Icons.view_list_rounded : Icons.grid_view_rounded), const SizedBox(width: 12), Text(grid ? t('list') : t('grid'))])),
          for (final k in ['name', 'size', 'date', 'type'])
            PopupMenuItem(value: 's:$k', child: Row(children: [
              Icon(sort == k ? (asc ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded) : Icons.sort_rounded),
              const SizedBox(width: 12),
              Text(t(k)),
            ])),
          CheckedPopupMenuItem(value: 'hidden', checked: hidden, child: Text(t('hidden'))),
          PopupMenuItem(value: 'all', child: Row(children: [const Icon(Icons.folder_copy_rounded), const SizedBox(width: 12), Flexible(child: Text(t('apply_all')))])),
          if (!virtual) PopupMenuItem(value: 'newf', child: Row(children: [const Icon(Icons.create_new_folder_rounded), const SizedBox(width: 12), Text(t('new_folder'))])),
        ],
      );

  Future<void> _tap(FE e) async {
    if (sel.isNotEmpty) { setState(() => sel.contains(e.path) ? sel.remove(e.path) : sel.add(e.path)); }
    else if (e.dir) { _cd(e.path); }
    else {
      await openFile(context, e);
      Core.invalidate(cur);
      if (mounted && !virtual) _load();
    }
  }

  void _long(FE e) => setState(() => sel.contains(e.path) ? sel.remove(e.path) : sel.add(e.path));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selecting = sel.isNotEmpty;
    final stg = Core.storage(cur);
    final tot = (stg['total'] as num).toInt(), fr = (stg['free'] as num).toInt();
    final bottom = MediaQuery.of(context).padding.bottom;
    return PopScope(
      canPop: !selecting && (virtual || cur == widget.path),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (selecting) { setState(sel.clear); } else { _cd(p.dirname(cur)); }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: selecting ? IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => setState(sel.clear)) : null,
          title: selecting
              ? Text('${sel.length}', style: const TextStyle(fontWeight: FontWeight.w700))
              : searching
                  ? TextField(
                      controller: qc, autofocus: true,
                      decoration: InputDecoration(hintText: t('search'), prefixIcon: const Icon(Icons.search_rounded), contentPadding: const EdgeInsets.symmetric(vertical: 10)),
                      onChanged: (v) { q = v; deb?.cancel(); deb = Timer(const Duration(milliseconds: 100), _load); },
                    )
                  : Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700)),
          actions: selecting
              ? null
              : [
                  IconButton(icon: Icon(searching ? Icons.search_off_rounded : Icons.search_rounded), onPressed: () => setState(() { searching = !searching; if (!searching) { q = ''; qc.clear(); _load(); } })),
                  _menu(),
                ],
        ),
        floatingActionButton: (!virtual && clip.isNotEmpty && !selecting)
            ? Padding(padding: const EdgeInsets.only(bottom: 4), child: FloatingActionButton(onPressed: _paste, child: const Icon(Icons.content_paste_rounded)))
            : null,
        body: Stack(children: [
          Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 6), child: Align(alignment: Alignment.centerLeft, child: _crumbs())),
            if (tot > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: (tot - fr) / tot),
                    duration: const Duration(milliseconds: 700),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => LinearProgressIndicator(value: v, minHeight: 8, borderRadius: BorderRadius.circular(8)),
                  ),
                  const SizedBox(height: 4),
                  Text('${fmt(fr)} / ${fmt(tot)}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                ]),
              ),
            if (loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: GestureDetector(
                onScaleUpdate: (details) {
                  if (details.pointerCount < 2) return;
                  final next = (density * details.scale).clamp(.75, 1.35);
                  if ((next - density).abs() > .015) {
                    setState(() => density = next);
                    _savePrefs();
                  }
                },
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 120),
                  child: items.isEmpty && !loading
                      ? Center(key: const ValueKey('e'), child: Icon(Icons.folder_open_rounded, size: 72, color: cs.outlineVariant))
                      : grid ? _grid(cs, bottom) : _list(cs, bottom),
                ),
              ),
            ),
          ]),
          Positioned(left: 0, right: 0, bottom: 0, child: _selBar(cs, bottom)),
        ]),
      ),
    );
  }

  Widget _ab(IconData i, VoidCallback f) => Tap(onTap: f, scale: .85, child: SizedBox(width: 54, height: 54, child: Icon(i)));

  Widget _selBar(ColorScheme cs, double bottom) => AnimatedSlide(
        offset: sel.isEmpty ? const Offset(0, 1.6) : Offset.zero,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, bottom + 14),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(36),
              border: Border.all(color: cs.outlineVariant.withOpacity(.6)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(.2), blurRadius: 24, offset: const Offset(0, 8))],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _ab(Icons.select_all_rounded, () => setState(() => sel.addAll(items.map((e) => e.path)))),
              _ab(Icons.copy_rounded, () { clip = sel.toList(); clipCut = false; setState(sel.clear); }),
              _ab(Icons.content_cut_rounded, () { clip = sel.toList(); clipCut = true; setState(sel.clear); }),
              if (sel.length == 1) _ab(Icons.drive_file_rename_outline_rounded, _rename),
              _ab(Icons.delete_rounded, _delete),
            ]),
          ),
        ),
      );

  String _sub(FE e) => e.dir ? fmtDate(e.mod) : '${fmt(e.size)}  ·  ${fmtDate(e.mod)}';

  Widget _list(ColorScheme cs, double bottom) => ListView.separated(
        key: ValueKey('l$cur$q'),
        physics: const ClampingScrollPhysics(),
        cacheExtent: 700,
        padding: EdgeInsets.only(bottom: 130 + bottom),
        itemCount: items.length,
        separatorBuilder: (_, i) {
          if (i + 1 < items.length && items[i].dir != items[i + 1].dir) {
            return Divider(height: 18 * density, indent: 18, endIndent: 18, thickness: 1);
          }
          return SizedBox(height: 2 * density);
        },
        itemBuilder: (_, i) {
          final e = items[i];
          final s = sel.contains(e.path);
          return Tap(
              onTap: () => _tap(e),
              onLong: () => _long(e),
              scale: .98,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                margin: EdgeInsets.symmetric(horizontal: 10, vertical: 1 * density),
                padding: EdgeInsets.all(7 * density),
                decoration: BoxDecoration(color: s ? cs.secondaryContainer : Colors.transparent, borderRadius: BorderRadius.circular(24)),
                child: Row(children: [
                  Leading(e, 46 * density, selected: s),
                  SizedBox(width: 10 * density),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14 * density, fontWeight: FontWeight.w600)),
                      SizedBox(height: 1 * density),
                      if (q.isNotEmpty || virtual) Text(p.dirname(e.path), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                      Text(_sub(e), style: TextStyle(fontSize: 11 * density, color: cs.onSurfaceVariant)),
                    ]),
                  ),
                ]),
              ),
            );
        },
      );

  Widget _grid(ColorScheme cs, double bottom) => LayoutBuilder(
        key: ValueKey('g$cur$q'),
        builder: (c, box) {
          final cols = (box.maxWidth / (112 * density)).floor().clamp(2, 8);
          final w = (box.maxWidth - 24 - (cols - 1) * 8) / cols;
          return SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.fromLTRB(12, 4, 12, 130 + bottom),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              for (var i = 0; i < items.length; i++)
                SizedBox(
                  width: w,
                  child: Tap(
                      onTap: () => _tap(items[i]),
                      onLong: () => _long(items[i]),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: sel.contains(items[i].path) ? cs.secondaryContainer : Colors.transparent, borderRadius: BorderRadius.circular(24)),
                        child: Column(children: [
                          Leading(items[i], w - 16, selected: sel.contains(items[i].path)),
                          const SizedBox(height: 6),
                          Text(items[i].name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                  ),
                ),
            ]),
          );
        },
      );
}
