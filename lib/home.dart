import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'common.dart';
import 'core.dart';
import 'l10n.dart';
import 'manager.dart';
import 'other.dart';
import 'settings.dart';

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  static const titles = ['local', 'library', 'network'];
  final pages = const [LocalTab(), LibraryTab(), NetworkTab()];

  Widget _page(int i) => AnimatedOpacity(
        opacity: tab == i ? 1 : 0,
        duration: const Duration(milliseconds: 260),
        child: AnimatedSlide(
          offset: tab == i ? Offset.zero : Offset(i < tab ? -.05 : .05, 0),
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
          child: IgnorePointer(ignoring: tab != i, child: pages[i]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      body: Stack(children: [
        Column(children: [
          Padding(
            padding: EdgeInsets.fromLTRB(24, top + 14, 16, 6),
            child: Row(children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  child: Align(key: ValueKey(tab), alignment: Alignment.centerLeft, child: Text(t(titles[tab]), style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w700))),
                ),
              ),
              RoundBtn(Icons.tune_rounded, () => go(context, const SettingsScreen()), label: t('settings')),
              const SizedBox(width: 8),
              RoundBtn(Icons.info_outline_rounded, () => go(context, const AboutScreen()), label: t('about')),
            ]),
          ),
          Expanded(child: Stack(children: [for (var i = 0; i < 3; i++) _page(i)])),
        ]),
        Positioned(left: 0, right: 0, bottom: 0, child: FloatNav(i: tab, on: (v) => setState(() => tab = v))),
      ]),
    );
  }
}

class FloatNav extends StatelessWidget {
  final int i;
  final ValueChanged<int> on;
  const FloatNav({super.key, required this.i, required this.on});
  static const icons = [Icons.smartphone_rounded, Icons.perm_media_rounded, Icons.lan_rounded];
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(30, 0, 30, max(bottom, 10) + 10),
      child: Container(
        height: 76,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: cs.outlineVariant.withOpacity(.6)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(.2), blurRadius: 28, offset: const Offset(0, 10))],
        ),
        child: LayoutBuilder(builder: (c, box) {
          final w = box.maxWidth / 3;
          return Stack(children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 420),
              curve: Curves.easeOutBack,
              left: w * i, width: w, top: 0, bottom: 0,
              child: Container(decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(32), border: Border.all(color: cs.onSurface, width: 2))),
            ),
            Row(children: [
              for (var k = 0; k < 3; k++)
                Expanded(
                  child: Semantics(
                    label: t(_HomeState.titles[k]),
                    button: true,
                    child: Tap(
                      onTap: () => on(k),
                      scale: .9,
                      child: Center(child: AnimatedScale(scale: i == k ? 1.12 : 1, duration: const Duration(milliseconds: 300), curve: Curves.easeOutBack, child: Icon(icons[k], size: 28, color: i == k ? cs.onSurface : cs.onSurfaceVariant))),
                    ),
                  ),
                ),
            ]),
          ]);
        }),
      ),
    );
  }
}

class Shortcut extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final double r;
  const Shortcut(this.icon, this.label, this.onTap, {super.key, this.r = 34});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tap(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: r * 2, height: r * 2, decoration: BoxDecoration(color: cs.secondaryContainer, shape: BoxShape.circle), child: Icon(icon, size: r * .9, color: cs.onSecondaryContainer)),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

class RingPainter extends CustomPainter {
  final double v, w;
  final Color fg, bg;
  RingPainter(this.v, this.w, this.fg, this.bg);
  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromLTWH(w / 2, w / 2, s.width - w, s.height - w);
    final base = Paint()..style = PaintingStyle.stroke..strokeWidth = w..strokeCap = StrokeCap.round..color = bg;
    canvas.drawArc(r, 0, 2 * pi, false, base);
    if (v > 0) canvas.drawArc(r, -pi / 2, 2 * pi * v, false, base..color = fg);
  }
  @override
  bool shouldRepaint(RingPainter o) => o.v != v || o.fg != fg || o.bg != bg;
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
        icon: const Icon(Icons.cleaning_services_rounded, size: 36),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          IconButton.filledTonal(iconSize: 28, onPressed: () => Navigator.pop(c, false), icon: const Icon(Icons.close_rounded)),
          IconButton.filled(iconSize: 28, onPressed: () => Navigator.pop(c, true), icon: const Icon(Icons.check_rounded)),
        ],
      ),
    );
    if (ok != true) return;
    try { if (Directory(trashDir).existsSync()) Directory(trashDir).deleteSync(recursive: true); } catch (_) {}
    try { final d = await getTemporaryDirectory(); if (d.existsSync()) d.deleteSync(recursive: true); } catch (_) {}
    if (mounted) { setState(() => sto = Core.storage(root)); snack(context, t('cleaned')); }
  }

  Widget _cat(IconData i, String l, int b, Color c, Color on) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Container(width: 42, height: 42, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(14)), child: Icon(i, color: on, size: 22)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l, style: const TextStyle(fontSize: 12)),
          Text(fmt(b), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ])),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final total = (sto['total'] as num).toInt(), free = (sto['free'] as num).toInt();
    final used = total - free;
    final frac = total == 0 ? 0.0 : used / total;
    final pad = MediaQuery.of(context).padding.bottom;
    return ListView(padding: EdgeInsets.fromLTRB(20, 8, 20, 130 + pad), children: [
      Appear(
        child: Card(
          color: cs.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: LayoutBuilder(builder: (c, box) {
              final ring = min(190.0, box.maxWidth * .5);
              return Row(children: [
                SizedBox(
                  width: ring, height: ring,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: frac),
                    duration: const Duration(milliseconds: 1100),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => CustomPaint(
                      painter: RingPainter(v, ring * .1, cs.primary, cs.surfaceContainerHighest),
                      child: Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text('${(v * 100).round()}%', style: TextStyle(fontSize: ring * .21, fontWeight: FontWeight.w800)),
                          Text(fmt(used), style: const TextStyle(fontSize: 12)),
                          Text('/ ${fmt(total)}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        ]),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(children: [
                  _cat(Icons.photo_rounded, t('photos'), (sc['photo'] as num).toInt(), cs.primaryContainer, cs.onPrimaryContainer),
                  _cat(Icons.music_note_rounded, t('audio'), (sc['audio'] as num).toInt(), cs.secondaryContainer, cs.onSecondaryContainer),
                  _cat(Icons.movie_rounded, t('video'), (sc['video'] as num).toInt(), cs.tertiaryContainer, cs.onTertiaryContainer),
                ])),
              ]);
            }),
          ),
        ),
      ),
      const SizedBox(height: 14),
      Appear(i: 1, child: FilledButton.tonalIcon(onPressed: clean, icon: const Icon(Icons.cleaning_services_rounded), label: Text(t('clean')))),
      const SizedBox(height: 8),
      Appear(i: 2, child: FilledButton.tonalIcon(onPressed: () => go(context, const AnalyzerScreen()), icon: const Icon(Icons.analytics_rounded), label: Text(t('analyzer')))),
      const SizedBox(height: 26),
      Appear(
        i: 3,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Shortcut(Icons.smartphone_rounded, t('main_storage'), () => go(context, Manager(path: root, title: t('main_storage'))))),
          Expanded(child: Shortcut(Icons.download_rounded, t('downloads'), () => go(context, Manager(path: Directory('$root/Download').existsSync() ? '$root/Download' : root, title: t('downloads'))))),
          Expanded(child: Shortcut(Icons.android_rounded, t('apps'), () => go(context, const InstalledApps()))),
          Expanded(child: Shortcut(Icons.delete_rounded, t('trash'), () { Directory(trashDir).createSync(recursive: true); go(context, Manager(path: trashDir, title: t('trash'), showHiddenForce: true)); })),
        ]),
      ),
    ]);
  }

  class AnalyzerScreen extends StatefulWidget {
    const AnalyzerScreen({super.key});
    @override
    State<AnalyzerScreen> createState() => _AnalyzerScreenState();
  }

  class _AnalyzerScreenState extends State<AnalyzerScreen> {
    late Future<List<dynamic>> data = _load();

    Future<List<dynamic>> _load() async {
      final result = await Future.wait([
        Core.scanAsync(root),
        Core.searchAsync(root, '', const [], false, 300),
      ]);
      final files = (result[1] as List).cast<FE>()..sort((a, b) => b.size.compareTo(a.size));
      return [result[0] as Map<String, dynamic>, files.take(20).toList()];
    }

    @override
    Widget build(BuildContext context) => Scaffold(
          appBar: AppBar(title: Text(t('analyzer'), style: const TextStyle(fontWeight: FontWeight.w700))),
          body: FutureBuilder<List<dynamic>>(
            future: data,
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text('${t('error')}: ${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final sizes = snap.data![0] as Map<String, dynamic>;
              final files = snap.data![1] as List<FE>;
              final categories = [('photos', 'photo'), ('audio', 'audio'), ('video', 'video')];
              return RefreshIndicator(
                onRefresh: () async => setState(() => data = _load()),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  children: [
                    Text(t('analyzer_categories'), style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    for (final item in categories)
                      ListTile(
                        leading: const Icon(Icons.data_usage_rounded),
                        title: Text(t(item.$1)),
                        trailing: Text(fmt((sizes[item.$2] as num?)?.toInt() ?? 0)),
                      ),
                    const SizedBox(height: 18),
                    Text(t('analyzer_large'), style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    for (final file in files)
                      ListTile(
                        dense: true,
                        leading: Leading(file, 40),
                        title: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(file.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                        trailing: Text(fmt(file.size)),
                        onTap: () => openFile(context, file),
                      ),
                  ],
                ),
              );
            },
          ),
        );
  }

class InstalledApps extends StatefulWidget {
    const InstalledApps({super.key});
    @override
    State<InstalledApps> createState() => _InstalledAppsState();
  }

class _InstalledAppsState extends State<InstalledApps> {
    static const channel = MethodChannel('files_you/apps');
    late Future<List<dynamic>> apps = _load();

    Future<List<dynamic>> _load() async => (await channel.invokeMethod<List<dynamic>>('installedApps')) ?? [];

    Future<void> _action(String method, String package) async {
      await channel.invokeMethod(method, {'package': package});
      if (method == 'uninstall' && mounted) setState(() => apps = _load());
    }

    @override
    Widget build(BuildContext context) => Scaffold(
          appBar: AppBar(title: Text(t('apps'), style: const TextStyle(fontWeight: FontWeight.w700))),
          body: FutureBuilder<List<dynamic>>(
            future: apps,
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text('${t('error')}: ${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              return RefreshIndicator(
                onRefresh: () async => setState(() => apps = _load()),
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: snap.data!.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 76),
                  itemBuilder: (_, i) {
                    final app = Map<String, dynamic>.from(snap.data![i] as Map);
                    final icon = app['icon'] as String?;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
                      leading: icon == null ? const CircleAvatar(child: Icon(Icons.android_rounded)) : CircleAvatar(backgroundImage: MemoryImage(base64Decode(icon))),
                      title: Text(app['label'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(app['package'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onTap: () => _action('launch', app['package'] as String),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) => _action(v, app['package'] as String),
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'launch', child: Text(t('open'))),
                          PopupMenuItem(value: 'uninstall', child: Text(t('delete'))),
                        ],
                      ),
                    );
                  },
                ),
              );
            },
          ),
        );
  }
}
class LibraryTab extends StatelessWidget {
  const LibraryTab({super.key});
  @override
  Widget build(BuildContext context) {
    void lib(String title, List<String> e, {bool recent = false}) => go(context, Manager(path: root, title: title, exts: e, recent: recent));
    final items = <List<dynamic>>[
      [Icons.photo_rounded, t('photos'), () => lib(t('photos'), [...imgAll])],
      [Icons.music_note_rounded, t('audio'), () => lib(t('audio'), [...audExt])],
      [Icons.movie_rounded, t('video'), () => lib(t('video'), [...vidExt])],
      [Icons.description_rounded, t('docs'), () => lib(t('docs'), const ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'txt', 'md', 'odt', 'rtf', 'csv'])],
      [Icons.schedule_rounded, t('new_files'), () => lib(t('new_files'), const [], recent: true)],
    ];
    final pad = MediaQuery.of(context).padding.bottom;
    return LayoutBuilder(builder: (c, box) {
      final w = (box.maxWidth - 40) / 3;
      return SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 130 + pad),
        child: Wrap(runSpacing: 18, children: [
          for (var i = 0; i < items.length; i++)
            SizedBox(width: w, child: Appear(i: i, child: Shortcut(items[i][0], items[i][1], items[i][2], r: 40))),
        ]),
      );
    });
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
          const SizedBox(height: 10),
          TextField(controller: h, decoration: InputDecoration(labelText: t('host'))),
          const SizedBox(height: 10),
          TextField(controller: u, decoration: InputDecoration(labelText: t('login'))),
          const SizedBox(height: 10),
          TextField(controller: w, obscureText: true, decoration: InputDecoration(labelText: t('password'))),
        ])),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          IconButton.filledTonal(iconSize: 26, onPressed: () => Navigator.pop(c, false), icon: const Icon(Icons.close_rounded)),
          IconButton.filled(iconSize: 26, onPressed: () => Navigator.pop(c, true), icon: const Icon(Icons.check_rounded)),
        ],
      ),
    );
    if (ok == true) {
      places.add(jsonEncode({'k': kind, 'n': n.text, 'h': h.text, 'u': u.text}));
      await st.pr.setStringList('places', places);
      if (mounted) setState(() {});
    }
  }

  Widget _grid(BuildContext c, List<List<dynamic>> k) => GridView.count(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.9,
        children: [
          for (final e in k)
            Tap(
              onTap: () { Navigator.pop(c); addPlace(e[0] as String); },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Theme.of(c).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(22)),
                child: Row(children: [
                  Icon(e[1] as IconData, size: 26),
                  const SizedBox(width: 10),
                  Expanded(child: Text(e[0] as String, softWrap: true, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                ]),
              ),
            ),
        ],
      );

  void newPlace() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => DefaultTabController(
        length: 2,
        child: SizedBox(
          height: 430,
          child: Column(children: [
            TabBar(dividerColor: Colors.transparent, tabs: [Tab(text: t('cloud')), Tab(text: t('remote'))]),
            Expanded(child: TabBarView(children: [
              _grid(c, const [['Dropbox', Icons.cloud_rounded], ['Google Drive', Icons.add_to_drive_rounded], ['OneDrive', Icons.cloud_queue_rounded], ['Box', Icons.inventory_2_rounded]]),
              _grid(c, [[t('lan'), Icons.wifi_rounded], ['SMB', Icons.folder_shared_rounded], ['FTP', Icons.swap_vert_rounded], ['SFTP', Icons.lock_rounded], ['WebDAV', Icons.dns_rounded]]),
            ])),
          ]),
        ),
      ),
    );
  }

  Widget _big(IconData i, String l, VoidCallback f, Color bg, Color fg) => Tap(
        onTap: f,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(30)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(i, size: 38, color: fg),
            const SizedBox(height: 26),
            Text(l, softWrap: true, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: fg)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pad = MediaQuery.of(context).padding.bottom;
    return ListView(padding: EdgeInsets.fromLTRB(20, 8, 20, 130 + pad), children: [
      Appear(
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: _big(Icons.wifi_tethering_rounded, t('access_from'), () => go(context, const FtpScreen()), cs.primaryContainer, cs.onPrimaryContainer)),
            const SizedBox(width: 12),
            Expanded(child: _big(Icons.add_rounded, t('new_place'), newPlace, cs.tertiaryContainer, cs.onTertiaryContainer)),
          ]),
        ),
      ),
      const SizedBox(height: 18),
      if (places.isEmpty) Padding(padding: const EdgeInsets.only(top: 40), child: Icon(Icons.cloud_off_rounded, size: 56, color: cs.outlineVariant)),
      for (var i = 0; i < places.length; i++)
        Builder(builder: (_) {
          final s = places[i];
          final m = jsonDecode(s) as Map;
          return Appear(
            i: i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    Container(width: 48, height: 48, decoration: BoxDecoration(color: cs.secondaryContainer, borderRadius: BorderRadius.circular(16)), child: Icon(Icons.storage_rounded, color: cs.onSecondaryContainer)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${m['n']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('${m['k']}  ${m['h']}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    ])),
                    IconButton(icon: const Icon(Icons.delete_outline_rounded), onPressed: () async { places.remove(s); await st.pr.setStringList('places', places); setState(() {}); }),
                  ]),
                ),
              ),
            ),
          );
        }),
    ]);
  }
}
