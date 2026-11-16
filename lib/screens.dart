import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:highlight/highlight.dart' as hl;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'core.dart';
import 'l10n.dart';
import 'settings.dart';

final root = Platform.isAndroid ? '/storage/emulated/0' : (Platform.environment['HOME'] ?? '/');
final trashDir = '$root/.FilesYouTrash';

void go(BuildContext c, Widget w) => Navigator.push(c, MaterialPageRoute(builder: (_) => w));
void snack(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

// ============================== HOME ==============================
class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  @override
  Widget build(BuildContext context) {
    final pages = [const LocalTab(), const LibraryTab(), const NetworkTab()];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Files You'),
        actions: [
          IconButton(icon: const Icon(Icons.settings_outlined), tooltip: t('settings'), onPressed: () => go(context, const SettingsScreen())),
          IconButton(icon: const Icon(Icons.info_outline), tooltip: t('about'), onPressed: () => go(context, const AboutScreen())),
        ],
      ),
      body: pages[tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.smartphone_outlined), selectedIcon: const Icon(Icons.smartphone), label: t('local')),
          NavigationDestination(icon: const Icon(Icons.video_library_outlined), selectedIcon: const Icon(Icons.video_library), label: t('library')),
          NavigationDestination(icon: const Icon(Icons.lan_outlined), selectedIcon: const Icon(Icons.lan), label: t('network')),
        ],
      ),
    );
  }
}

class Shortcut extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const Shortcut(this.icon, this.label, this.onTap, {super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 96,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(radius: 30, backgroundColor: cs.secondaryContainer, child: Icon(icon, size: 28, color: cs.onSecondaryContainer)),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center, softWrap: true, style: const TextStyle(fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

class LocalTab extends StatefulWidget {
  const LocalTab({super.key});
  @override
  State<LocalTab> createState() => _LocalTabState();
}

class _LocalTabState extends State<LocalTab> {
  Map<String, dynamic> sto = {'total': 0, 'free': 0};
  Map<String, dynamic> sc = {'photo': 0, 'audio': 0, 'video': 0};
  @override
  void initState() {
    super.initState();
    sto = Core.storage(root);
    Core.scanAsync(root).then((v) { if (mounted) setState(() => sc = v); });
  }

  Future<void> clean() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(t('clean')),
        content: Text(t('clean_msg')),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('cancel'))), FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t('ok')))],
      ),
    );
    if (ok != true) return;
    try { if (Directory(trashDir).existsSync()) Directory(trashDir).deleteSync(recursive: true); } catch (_) {}
    try { final d = await getTemporaryDirectory(); if (d.existsSync()) d.deleteSync(recursive: true); } catch (_) {}
    if (mounted) { setState(() => sto = Core.storage(root)); snack(context, t('cleaned')); }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = (sto['total'] as num).toInt(), free = (sto['free'] as num).toInt();
    final used = total - free;
    final frac = total == 0 ? 0.0 : used / total;
    Widget cat(IconData i, String l, int b) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Icon(i, color: cs.primary),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(l, style: const TextStyle(fontWeight: FontWeight.w600)), Text(fmt(b))])),
          ]),
        );
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        elevation: 0,
        color: cs.surfaceContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            SizedBox(
              width: 170, height: 170,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox(width: 170, height: 170, child: CircularProgressIndicator(value: frac, strokeWidth: 16, strokeCap: StrokeCap.round, backgroundColor: cs.surfaceContainerHigh)),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('${(frac * 100).round()}%', style: Theme.of(context).textTheme.headlineMedium),
                    Text(fmt(used), textAlign: TextAlign.center),
                    Text('${t('used_of')} ${fmt(total)}', textAlign: TextAlign.center, softWrap: true, style: const TextStyle(fontSize: 11)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(width: 16),
            Expanded(child: Column(children: [
              cat(Icons.photo_outlined, t('photos'), (sc['photo'] as num).toInt()),
              cat(Icons.audiotrack_outlined, t('audio'), (sc['audio'] as num).toInt()),
              cat(Icons.movie_outlined, t('video'), (sc['video'] as num).toInt()),
            ])),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      FilledButton.tonalIcon(onPressed: clean, icon: const Icon(Icons.cleaning_services_outlined), label: Text(t('clean'))),
      const SizedBox(height: 20),
      Wrap(alignment: WrapAlignment.spaceEvenly, runSpacing: 12, children: [
        Shortcut(Icons.smartphone, t('main_storage'), () => go(context, Manager(path: root, title: t('main_storage')))),
        Shortcut(Icons.download_outlined, t('downloads'), () => go(context, Manager(path: Directory('$root/Download').existsSync() ? '$root/Download' : root, title: t('downloads')))),
        Shortcut(Icons.android, t('apps'), () => go(context, Manager(path: root, title: t('apps'), exts: const ['apk', 'xapk', 'apks']))),
        Shortcut(Icons.delete_outline, t('trash'), () { Directory(trashDir).createSync(recursive: true); go(context, Manager(path: trashDir, title: t('trash'), showHiddenForce: true)); }),
      ]),
    ]);
  }
}

class LibraryTab extends StatelessWidget {
  const LibraryTab({super.key});
  @override
  Widget build(BuildContext context) {
    void lib(String title, List<String> e, {bool recent = false}) => go(context, Manager(path: root, title: title, exts: e, recent: recent));
    return ListView(padding: const EdgeInsets.all(16), children: [
      Wrap(alignment: WrapAlignment.spaceEvenly, runSpacing: 16, children: [
        Shortcut(Icons.photo_outlined, t('photos'), () => lib(t('photos'), const ['jpg', 'jpeg', 'png', 'gif', 'webp', 'heic', 'bmp'])),
        Shortcut(Icons.audiotrack_outlined, t('audio'), () => lib(t('audio'), const ['mp3', 'wav', 'flac', 'm4a', 'ogg', 'aac', 'opus'])),
        Shortcut(Icons.movie_outlined, t('video'), () => lib(t('video'), const ['mp4', 'mkv', 'avi', 'mov', 'webm', '3gp'])),
        Shortcut(Icons.description_outlined, t('docs'), () => lib(t('docs'), const ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'md', 'odt', 'rtf', 'csv'])),
        Shortcut(Icons.fiber_new_outlined, t('new_files'), () => lib(t('new_files'), const [], recent: true)),
      ]),
    ]);
  }
}

class NetworkTab extends StatefulWidget {
  const NetworkTab({super.key});
  @override
  State<NetworkTab> createState() => _NetworkTabState();
}

class _NetworkTabState extends State<NetworkTab> {
  List<String> places = [];
  @override
  void initState() {
    super.initState();
    places = st.pr.getStringList('places') ?? [];
  }

  Future<void> addPlace(String kind) async {
    final n = TextEditingController(text: kind), h = TextEditingController(), u = TextEditingController(), w = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(kind),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: n, decoration: InputDecoration(labelText: t('name'))),
          TextField(controller: h, decoration: InputDecoration(labelText: t('host'))),
          TextField(controller: u, decoration: InputDecoration(labelText: t('login'))),
          TextField(controller: w, obscureText: true, decoration: InputDecoration(labelText: t('password'))),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: Text(t('cancel'))), FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(t('add')))],
      ),
    );
    if (ok == true) {
      places.add(jsonEncode({'k': kind, 'n': n.text, 'h': h.text, 'u': u.text}));
      await st.pr.setStringList('places', places);
      if (mounted) setState(() {});
    }
  }

  void newPlace() {
    Navigator.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => DefaultTabController(
        length: 2,
        child: SizedBox(
          height: 420,
          child: Column(children: [
            TabBar(tabs: [Tab(text: t('cloud')), Tab(text: t('remote'))]),
            Expanded(child: TabBarView(children: [
              _kinds(c, const [['Dropbox', Icons.cloud_outlined], ['Google Drive', Icons.add_to_drive_outlined], ['OneDrive', Icons.cloud_queue], ['Box', Icons.inventory_2_outlined]]),
              _kinds(c, [[t('lan'), Icons.wifi], ['SMB', Icons.folder_shared_outlined], ['FTP', Icons.swap_vert], ['SFTP', Icons.lock_outline], ['WebDAV', Icons.dns_outlined]]),
            ])),
          ]),
        ),
      ),
    );
  }

  Widget _kinds(BuildContext c, List<List<dynamic>> k) => ListView(children: [
        for (final e in k)
          ListTile(leading: Icon(e[1] as IconData), title: Text(e[0] as String), onTap: () { Navigator.pop(c); addPlace(e[0] as String); }),
      ]);

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(16), children: [
        FilledButton.icon(onPressed: () => go(context, const FtpScreen()), icon: const Icon(Icons.wifi_tethering), label: Text(t('access_from'))),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(onPressed: newPlace, icon: const Icon(Icons.add), label: Text(t('new_place'))),
        const SizedBox(height: 16),
        if (places.isEmpty) Center(child: Text(t('no_places'))),
        for (final s in places)
          Builder(builder: (_) {
            final m = jsonDecode(s) as Map;
            return Card(
              elevation: 0,
              child: ListTile(
                leading: const Icon(Icons.storage_outlined),
                title: Text('${m['n']}'),
                subtitle: Text('${m['k']}  ${m['h']}'),
                trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () async { places.remove(s); await st.pr.setStringList('places', places); setState(() {}); }),
              ),
            );
          }),
      ]);
}

// ============================== MANAGER ==============================
IconData iconFor(FE e) {
  if (e.dir) return Icons.folder;
  switch (e.ext) {
    case 'jpg': case 'jpeg': case 'png': case 'gif': case 'webp': case 'bmp': case 'heic': return Icons.image_outlined;
    case 'mp3': case 'wav': case 'flac': case 'm4a': case 'ogg': case 'aac': return Icons.audiotrack_outlined;
    case 'mp4': case 'mkv': case 'avi': case 'mov': case 'webm': return Icons.movie_outlined;
    case 'apk': return Icons.android;
    case 'zip': case 'rar': case '7z': case 'tar': case 'gz': return Icons.archive_outlined;
    case 'html': case 'htm': return Icons.html;
    case 'plugin': case 'json': case 'dart': case 'js': case 'py': case 'rs': case 'kt': case 'java': case 'xml': case 'css': return Icons.code;
    case 'pdf': return Icons.picture_as_pdf_outlined;
    default: return Icons.insert_drive_file_outlined;
  }
}

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
  String sort = 'date', q = '';
  final qc = TextEditingController();
  Timer? deb;
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

  void _prefs() {
    final s = st.pr.getString('fv:$cur') ?? st.pr.getString('fv:*');
    if (s != null) {
      final a = s.split('|');
      grid = a[0] == '1'; sort = a[1]; asc = a[2] == '1'; hidden = a[3] == '1' || widget.showHiddenForce;
    }
  }

  Future<void> _savePrefs({bool all = false}) async {
    final v = '${grid ? 1 : 0}|$sort|${asc ? 1 : 0}|${hidden ? 1 : 0}';
    await st.pr.setString(all ? 'fv:*' : 'fv:$cur', v);
    if (all) { for (final k in st.pr.getKeys().where((k) => k.startsWith('fv:') && k != 'fv:*').toList()) { await st.pr.remove(k); } }
  }

  Future<void> _load() async {
    setState(() => loading = true);
    List<FE> r;
    if (q.isNotEmpty || virtual) {
      r = await Core.searchAsync(cur, q, widget.exts, hidden, widget.recent ? 4000 : 1500);
      if (widget.recent && q.isEmpty) {
        final lim = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 14 * 86400;
        r = r.where((e) => e.mod > lim && !e.dir).toList();
      }
    } else {
      r = Core.list(cur, hidden);
    }
    if (!mounted) return;
    setState(() { items = r; _sort(); loading = false; });
  }

  void _sort() {
    int c(FE a, FE b) {
      if (a.dir != b.dir && sort != 'date') return a.dir ? -1 : 1;
      switch (sort) {
        case 'size': return a.size.compareTo(b.size);
        case 'date': return a.mod.compareTo(b.mod);
        case 'type': final r = a.ext.compareTo(b.ext); return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        default: return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
    }
    items.sort((a, b) => asc ? c(a, b) : c(b, a));
  }

  void _cd(String path) { cur = path; sel.clear(); qc.clear(); q = ''; searching = false; _prefs(); _load(); }

  bool get canUp => !virtual && cur != root && cur != widget.path || (!virtual && cur != widget.path);

  Future<void> _open(FE e) async {
    if (e.dir) { _cd(e.path); return; }
    final isHtml = e.ext == 'html' || e.ext == 'htm';
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 8), child: Align(alignment: Alignment.centerLeft, child: Text('${t('open_with')}: ${e.name}', style: Theme.of(context).textTheme.titleMedium))),
            ListTile(leading: const Icon(Icons.notes), title: Text(t('text_editor')), onTap: () { Navigator.pop(c); go(context, Editor(path: e.path, code: false)); }),
            ListTile(leading: const Icon(Icons.code), title: Text(t('code_editor')), onTap: () { Navigator.pop(c); go(context, Editor(path: e.path, code: true)); }),
            if (isHtml) ListTile(leading: const Icon(Icons.web), title: Text(t('html_local')), onTap: () { Navigator.pop(c); go(context, HtmlView(path: e.path)); }),
            if (isHtml) ListTile(leading: const Icon(Icons.public), title: Text(t('html_browser')), onTap: () { Navigator.pop(c); openInBrowser(e.path); }),
            ListTile(leading: const Icon(Icons.open_in_new), title: Text(t('system_open')), onTap: () { Navigator.pop(c); OpenFilex.open(e.path); }),
          ]),
        ),
      ),
    );
  }

  Future<void> _delete() async {
    Directory(trashDir).createSync(recursive: true);
    final inTrash = cur.startsWith(trashDir);
    for (final path in sel) {
      try {
        if (inTrash) {
          FileSystemEntity.isDirectorySync(path) ? Directory(path).deleteSync(recursive: true) : File(path).deleteSync();
        } else {
          final dst = '$trashDir/${DateTime.now().millisecondsSinceEpoch}_${p.basename(path)}';
          try { FileSystemEntity.isDirectorySync(path) ? Directory(path).renameSync(dst) : File(path).renameSync(dst); } catch (_) {
            if (!FileSystemEntity.isDirectorySync(path)) { File(path).copySync(dst); File(path).deleteSync(); }
          }
        }
      } catch (_) {}
    }
    sel.clear();
    if (mounted) snack(context, t('moved_trash'));
    _load();
  }

  Future<String?> _ask(String title, String init) async {
    final c = TextEditingController(text: init);
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true),
        actions: [TextButton(onPressed: () => Navigator.pop(d), child: Text(t('cancel'))), FilledButton(onPressed: () => Navigator.pop(d, c.text), child: Text(t('ok')))],
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
        if (clipCut) { try { FileSystemEntity.isDirectorySync(s) ? Directory(s).renameSync(dst) : File(s).renameSync(dst); } catch (_) { _copyRec(s, dst); FileSystemEntity.isDirectorySync(s) ? Directory(s).deleteSync(recursive: true) : File(s).deleteSync(); } }
        else { _copyRec(s, dst); }
      } catch (_) {}
    }
    clip = [];
    _load();
  }

  Widget _crumbs() {
    final parts = cur.split('/').where((e) => e.isNotEmpty).toList();
    return Wrap(spacing: 2, runSpacing: 0, crossAxisAlignment: WrapCrossAlignment.center, children: [
      for (var i = 0; i < parts.length; i++) ...[
        InkWell(onTap: virtual ? null : () => _cd('/${parts.sublist(0, i + 1).join('/')}'), child: Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(parts[i], style: const TextStyle(fontSize: 13)))),
        if (i < parts.length - 1) const Text('/', style: TextStyle(fontSize: 13)),
      ],
    ]);
  }

  Widget _menu() => PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (v) async {
          if (v == 'grid') grid = !grid;
          else if (v == 'hidden') { hidden = !hidden; _load(); }
          else if (v == 'all') { await _savePrefs(all: true); if (mounted) snack(context, t('ok')); return; }
          else if (v == 'paste') { _paste(); return; }
          else if (v == 'newf') { final n = await _ask(t('new_folder'), ''); if (n != null && n.isNotEmpty) { Directory('$cur/$n').createSync(); _load(); } return; }
          else if (v.startsWith('s:')) { final k = v.substring(2); if (sort == k) { asc = !asc; } else { sort = k; asc = k == 'name'; } _sort(); }
          setState(() {});
          _savePrefs();
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'grid', child: Text('${t('view')}: ${grid ? t('list') : t('grid')}')),
          for (final k in ['name', 'size', 'date', 'type'])
            PopupMenuItem(value: 's:$k', child: Row(children: [Expanded(child: Text('${t('sort')}: ${t(k)}')), if (sort == k) Icon(asc ? Icons.arrow_upward : Icons.arrow_downward, size: 18)])),
          CheckedPopupMenuItem(value: 'hidden', checked: hidden, child: Text(t('hidden'))),
          PopupMenuItem(value: 'all', child: Text(t('apply_all'))),
          if (!virtual) PopupMenuItem(value: 'newf', child: Text(t('new_folder'))),
          if (!virtual && clip.isNotEmpty) PopupMenuItem(value: 'paste', child: Text(t('paste'))),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selecting = sel.isNotEmpty;
    final stg = Core.storage(cur);
    final tot = (stg['total'] as num).toInt(), fr = (stg['free'] as num).toInt();
    return PopScope(
      canPop: !selecting && (virtual || cur == widget.path),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (selecting) { setState(sel.clear); } else { _cd(p.dirname(cur)); }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: selecting ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(sel.clear)) : null,
          title: selecting
              ? Text('${t('selected')}: ${sel.length}')
              : searching
                  ? TextField(controller: qc, autofocus: true, decoration: InputDecoration(hintText: t('search'), border: InputBorder.none), onChanged: (v) { q = v; deb?.cancel(); deb = Timer(const Duration(milliseconds: 120), _load); })
                  : Text(widget.title),
          actions: selecting
              ? [
                  IconButton(icon: const Icon(Icons.select_all), tooltip: t('select_all'), onPressed: () => setState(() => sel.addAll(items.map((e) => e.path)))),
                  IconButton(icon: const Icon(Icons.copy), tooltip: t('copy'), onPressed: () { clip = sel.toList(); clipCut = false; setState(sel.clear); }),
                  IconButton(icon: const Icon(Icons.content_cut), tooltip: t('cut'), onPressed: () { clip = sel.toList(); clipCut = true; setState(sel.clear); }),
                  if (sel.length == 1) IconButton(icon: const Icon(Icons.drive_file_rename_outline), tooltip: t('rename'), onPressed: () async { final o = sel.first; final n = await _ask(t('rename'), p.basename(o)); if (n != null && n.isNotEmpty) { try { File(o).renameSync('${p.dirname(o)}/$n'); } catch (_) { try { Directory(o).renameSync('${p.dirname(o)}/$n'); } catch (_) {} } sel.clear(); _load(); } }),
                  IconButton(icon: const Icon(Icons.delete_outline), tooltip: t('delete'), onPressed: _delete),
                ]
              : [
                  IconButton(icon: Icon(searching ? Icons.search_off : Icons.search), onPressed: () => setState(() { searching = !searching; if (!searching) { q = ''; qc.clear(); _load(); } })),
                  _menu(),
                ],
        ),
        body: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 4), child: Align(alignment: Alignment.centerLeft, child: _crumbs())),
          if (tot > 0) Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              LinearProgressIndicator(value: (tot - fr) / tot, borderRadius: BorderRadius.circular(4), minHeight: 6),
              const SizedBox(height: 2),
              Text('${fmt(fr)} ${t('free_of')} ${fmt(tot)}', style: const TextStyle(fontSize: 12)),
            ]),
          ),
          if (loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: items.isEmpty && !loading ? Center(child: Text(t('empty'))) : grid ? _grid(cs) : _list(cs)),
        ]),
      ),
    );
  }

  String _sub(FE e) {
    final d = DateTime.fromMillisecondsSinceEpoch(e.mod * 1000);
    final ds = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return e.dir ? ds : '${fmt(e.size)}  $ds';
  }

  void _tap(FE e) { if (sel.isNotEmpty) { setState(() => sel.contains(e.path) ? sel.remove(e.path) : sel.add(e.path)); } else { _open(e); } }
  void _long(FE e) => setState(() => sel.contains(e.path) ? sel.remove(e.path) : sel.add(e.path));
  Color _ic(FE e, ColorScheme cs) => e.dir ? Color(st.folder) : cs.primary;

  Widget _list(ColorScheme cs) => ListView.builder(
        itemCount: items.length,
        itemBuilder: (_, i) {
          final e = items[i];
          final s = sel.contains(e.path);
          return ListTile(
            selected: s,
            selectedTileColor: cs.secondaryContainer,
            leading: Icon(s ? Icons.check_circle : iconFor(e), color: _ic(e, cs)),
            title: Text(e.name),
            subtitle: Text(q.isNotEmpty || virtual ? '${p.dirname(e.path)}\n${_sub(e)}' : _sub(e)),
            onTap: () => _tap(e),
            onLongPress: () => _long(e),
          );
        },
      );

  Widget _grid(ColorScheme cs) => SingleChildScrollView(
        padding: const EdgeInsets.all(8),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in items)
            SizedBox(
              width: 104,
              child: Material(
                color: sel.contains(e.path) ? cs.secondaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _tap(e),
                  onLongPress: () => _long(e),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(children: [
                      Icon(sel.contains(e.path) ? Icons.check_circle : iconFor(e), size: 44, color: _ic(e, cs)),
                      const SizedBox(height: 4),
                      Text(e.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      );
}

// ============================== EDITORS / VIEWERS ==============================
const _langs = {
  'dart': 'dart', 'js': 'javascript', 'json': 'json', 'plugin': 'json', 'html': 'xml', 'htm': 'xml', 'xml': 'xml', 'css': 'css',
  'py': 'python', 'rs': 'rust', 'kt': 'kotlin', 'java': 'java', 'md': 'markdown', 'yaml': 'yaml', 'yml': 'yaml', 'sh': 'bash',
  'ts': 'typescript', 'c': 'cpp', 'cpp': 'cpp', 'h': 'cpp', 'go': 'go', 'sql': 'sql', 'toml': 'ini', 'ini': 'ini', 'lua': 'lua', 'php': 'php',
};

class CodeCtl extends TextEditingController {
  final String lang;
  final Map<String, TextStyle> theme;
  CodeCtl(String text, this.lang, this.theme) : super(text: text);
  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    try {
      final r = hl.highlight.parse(text, language: lang);
      return TextSpan(style: style, children: _c(r.nodes ?? [], style));
    } catch (_) {
      return TextSpan(style: style, text: text);
    }
  }

  List<TextSpan> _c(List<hl.Node> ns, TextStyle? base) => [
        for (final n in ns)
          if (n.value != null) TextSpan(text: n.value, style: n.className != null ? theme[n.className] : null)
          else TextSpan(children: _c(n.children ?? [], base), style: n.className != null ? theme[n.className] : null)
      ];
}

class Editor extends StatefulWidget {
  final String path;
  final bool code;
  const Editor({super.key, required this.path, required this.code});
  @override
  State<Editor> createState() => _EditorState();
}

class _EditorState extends State<Editor> {
  TextEditingController? c;
  bool err = false, dirty = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (c != null) return;
    try {
      final txt = utf8.decode(File(widget.path).readAsBytesSync(), allowMalformed: false);
      final dark = Theme.of(context).brightness == Brightness.dark;
      final lang = _langs[p.extension(widget.path).toLowerCase().replaceFirst('.', '')] ?? 'plaintext';
      c = widget.code ? CodeCtl(txt, lang, Map<String, TextStyle>.from(dark ? atomOneDarkTheme : githubTheme)) : TextEditingController(text: txt);
    } catch (_) { err = true; }
  }

  void _save() {
    File(widget.path).writeAsStringSync(c!.text);
    setState(() => dirty = false);
    snack(context, t('saved'));
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !dirty,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final s = await showDialog<int>(context: context, builder: (d) => AlertDialog(title: Text(t('save')), actions: [
            TextButton(onPressed: () => Navigator.pop(d, 0), child: Text(t('cancel'))),
            TextButton(onPressed: () => Navigator.pop(d, 1), child: Text(t('delete'))),
            FilledButton(onPressed: () => Navigator.pop(d, 2), child: Text(t('save'))),
          ]));
          if (s == 2) _save();
          if ((s == 1 || s == 2) && mounted) { setState(() => dirty = false); Navigator.pop(context); }
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(p.basename(widget.path), style: const TextStyle(fontSize: 16)),
            actions: [if (!err) IconButton(icon: const Icon(Icons.save_outlined), tooltip: t('save'), onPressed: _save)],
          ),
          body: err
              ? Center(child: Text(t('cannot_read')))
              : SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: TextField(
                      controller: c,
                      maxLines: null,
                      expands: true,
                      keyboardType: TextInputType.multiline,
                      textAlignVertical: TextAlignVertical.top,
                      onChanged: (_) { if (!dirty) setState(() => dirty = true); },
                      style: widget.code ? const TextStyle(fontFamily: 'monospace', fontSize: 13.5) : null,
                      decoration: const InputDecoration(border: InputBorder.none),
                    ),
                  ),
                ),
        ),
      );
}

class HtmlView extends StatefulWidget {
  final String path;
  const HtmlView({super.key, required this.path});
  @override
  State<HtmlView> createState() => _HtmlViewState();
}

class _HtmlViewState extends State<HtmlView> {
  late final WebViewController w = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..loadFile(widget.path);
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(p.basename(widget.path), style: const TextStyle(fontSize: 16))), body: WebViewWidget(controller: w));
}

HttpServer? _srv;
Future<void> openInBrowser(String file) async {
  await _srv?.close(force: true);
  final dir = p.dirname(file);
  _srv = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  const mime = {'html': 'text/html', 'htm': 'text/html', 'css': 'text/css', 'js': 'text/javascript', 'json': 'application/json', 'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'gif': 'image/gif', 'svg': 'image/svg+xml', 'webp': 'image/webp', 'txt': 'text/plain', 'woff2': 'font/woff2', 'ttf': 'font/ttf'};
  _srv!.listen((r) async {
    final rel = Uri.decodeComponent(r.uri.path).split('/').where((e) => e.isNotEmpty && e != '..').join('/');
    final f = File('$dir/$rel');
    if (await f.exists()) {
      r.headers.contentType = ContentType.parse('${mime[p.extension(f.path).toLowerCase().replaceFirst('.', '')] ?? 'application/octet-stream'}; charset=utf-8');
      await r.addStream(f.openRead());
    } else { r.response.statusCode = 404; }
    await r.close();
  });
  await launchUrl(Uri.parse('http://127.0.0.1:${_srv!.port}/${Uri.encodeComponent(p.basename(file))}'), mode: LaunchMode.externalApplication);
}

// ============================== FTP ==============================
class FtpScreen extends StatefulWidget {
  const FtpScreen({super.key});
  @override
  State<FtpScreen> createState() => _FtpScreenState();
}

class _FtpScreenState extends State<FtpScreen> {
  static bool running = false;
  final user = TextEditingController(text: st.pr.getString('ftp_user') ?? 'user');
  final pass = TextEditingController(text: st.pr.getString('ftp_pass') ?? '1234');
  final port = TextEditingController(text: '${st.pr.getInt('ftp_port') ?? 2121}');
  bool random = true, hid = false;
  String ip = '0.0.0.0';

  @override
  void initState() {
    super.initState();
    NetworkInterface.list(type: InternetAddressType.IPv4).then((l) {
      for (final i in l) { for (final a in i.addresses) { if (!a.isLoopback) { if (mounted) setState(() => ip = a.address); return; } } }
    });
  }

  String _rnd() { const c = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'; final r = Random.secure(); return List.generate(8, (_) => c[r.nextInt(c.length)]).join(); }

  void _toggle() {
    if (running) { Core.ftpStop(); setState(() => running = false); return; }
    if (random) pass.text = _rnd();
    final pt = int.tryParse(port.text) ?? 2121;
    final ok = Core.ftpStart(root, pt, user.text, pass.text, hid);
    st.pr.setString('ftp_user', user.text); st.pr.setInt('ftp_port', pt);
    if (!ok) snack(context, t('port_busy'));
    setState(() => running = ok);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(t('ftp_title'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          elevation: 0,
          color: running ? cs.primaryContainer : cs.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              Text(running ? t('running') : t('stopped')),
              const SizedBox(height: 8),
              SelectableText('ftp://$ip:${port.text}', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              SelectableText('${t('login')}: ${user.text}'),
              SelectableText('${t('password')}: ${pass.text}'),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        TextField(controller: user, enabled: !running, decoration: InputDecoration(labelText: t('login'), border: const OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: pass, enabled: !running && !random, decoration: InputDecoration(labelText: t('password'), border: const OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: port, enabled: !running, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t('port'), border: const OutlineInputBorder())),
        SwitchListTile(title: Text(t('random_pass')), value: random, onChanged: running ? null : (v) => setState(() => random = v)),
        SwitchListTile(title: Text(t('hidden')), value: hid, onChanged: running ? null : (v) => setState(() => hid = v)),
        const SizedBox(height: 8),
        running ? FilledButton.tonalIcon(onPressed: _toggle, icon: const Icon(Icons.stop), label: Text(t('stop'))) : FilledButton.icon(onPressed: _toggle, icon: const Icon(Icons.play_arrow), label: Text(t('start'))),
      ]),
    );
  }
}

// ============================== SETTINGS ==============================
const _palette = [0xFF6750A4, 0xFF1E88E5, 0xFF00897B, 0xFF43A047, 0xFFF9A825, 0xFFFF7043, 0xFFE53935, 0xFFD81B60, 0xFF8E24AA, 0xFF546E7A];
const _folders = [0xFFFFB300, 0xFFFFA726, 0xFF42A5F5, 0xFF66BB6A, 0xFFEF5350, 0xFFAB47BC, 0xFF26C6DA, 0xFF8D6E63];
const _bgs = [0, 0xFFFFFFFF, 0xFFFFF8E1, 0xFFE3F2FD, 0xFFE8F5E9, 0xFF1A1A2E, 0xFF1B1B1B, 0xFF263238];

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  Widget _dots(String title, List<int> cols, int cur, void Function(int) on, {bool zeroIsSystem = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final c in [if (zeroIsSystem) 0, ...cols])
              GestureDetector(
                onTap: () => on(c),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: c == 0 ? Colors.grey.shade400 : Color(c),
                  child: c == cur ? const Icon(Icons.check, color: Colors.white, size: 18) : (c == 0 ? const Icon(Icons.auto_awesome, size: 16, color: Colors.white) : null),
                ),
              ),
          ]),
        ]),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: st,
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: Text(t('settings'))),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Text(t('theme'), style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              showSelectedIcon: false,
              segments: [ButtonSegment(value: 0, label: Text(t('light'))), ButtonSegment(value: 1, label: Text(t('dark'))), ButtonSegment(value: 2, label: Text(t('oled')))],
              selected: {st.theme},
              onSelectionChanged: (s) => st.setInt('theme', s.first),
            ),
            _dots(t('accent'), _palette, st.accent, (c) => st.setInt('accent', c), zeroIsSystem: true),
            _dots(t('folder_color'), _folders, st.folder, (c) => st.setInt('folder', c)),
            SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(t('accent_bg')), value: st.accentBg, onChanged: st.setAccentBg),
            _dots(t('bg_color'), _bgs.sublist(1), st.bg, (c) => st.setInt('bg', st.bg == c ? 0 : c)),
            const Divider(),
            Text(t('font'), style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(st.fontPath == null ? t('font_default') : p.basename(st.fontPath!)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.tonalIcon(
                icon: const Icon(Icons.font_download_outlined),
                label: Text(t('font_pick')),
                onPressed: () async {
                  final r = await FilePicker.platform.pickFiles(type: FileType.any);
                  final f = r?.files.single.path;
                  if (f != null && f.toLowerCase().endsWith('.ttf')) {
                    final dir = await getApplicationSupportDirectory();
                    final dst = '${dir.path}/user_font.ttf';
                    File(f).copySync(dst);
                    await st.setFont(dst);
                  }
                },
              ),
              OutlinedButton(onPressed: () => st.setFont(null), child: Text(t('font_default'))),
            ]),
          ]),
        ),
      );
}

// ============================== ABOUT ==============================
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});
  @override
  Widget build(BuildContext context) {
    const devs = [
      ['Господин (секс-символ)', 'Lyzos'],
      ['Опти', 'optimist_opti'],
      ['LuDev', 'LuPlugins'],
    ];
    return Scaffold(
      appBar: AppBar(title: Text(t('about'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Center(child: Text('Files You', style: Theme.of(context).textTheme.headlineMedium)),
        const SizedBox(height: 20),
        Text(t('developers'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final d in devs)
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                ClipOval(
                  child: SizedBox(
                    width: 64, height: 64,
                    child: Image.network(
                      'https://t.me/i/userpic/320/${d[1]}.jpg',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(color: Theme.of(context).colorScheme.primaryContainer, alignment: Alignment.center, child: Text(d[0].characters.first, style: const TextStyle(fontSize: 26))),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(child: Text(d[0], style: Theme.of(context).textTheme.titleMedium)),
              ]),
            ),
          ),
      ]),
    );
  }
}
