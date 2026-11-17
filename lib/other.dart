import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import 'common.dart';
import 'core.dart';
import 'home.dart';
import 'l10n.dart';
import 'settings.dart';

// ============================== BOOT + PERMISSION ==============================
Future<bool> hasAccess() async {
  if (!Platform.isAndroid) return true;
  final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
  if (sdk >= 30) return Permission.manageExternalStorage.isGranted;
  return Permission.storage.isGranted;
}

class Boot extends StatefulWidget {
  const Boot({super.key});
  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> with WidgetsBindingObserver {
  bool? ok;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) { if (s == AppLifecycleState.resumed && ok != true) _check(); }

  Future<void> _check() async {
    final v = await hasAccess();
    if (mounted) setState(() => ok = v);
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 450),
        switchInCurve: Curves.easeOutCubic,
        child: ok == null ? const Scaffold(key: ValueKey('w')) : ok! ? const Home(key: ValueKey('h')) : Onboarding(key: const ValueKey('o'), onDone: _check),
      );
}

class Onboarding extends StatefulWidget {
  final Future<void> Function() onDone;
  const Onboarding({super.key, required this.onDone});
  @override
  State<Onboarding> createState() => _OnboardingState();
}

class _OnboardingState extends State<Onboarding> with SingleTickerProviderStateMixin {
  late final AnimationController ac = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
  @override
  void dispose() { ac.dispose(); super.dispose(); }

  Future<void> _ask() async {
    HapticFeedback.mediumImpact();
    final sdk = Platform.isAndroid ? (await DeviceInfoPlugin().androidInfo).version.sdkInt : 0;
    PermissionStatus s;
    if (sdk >= 30) {
      s = await Permission.manageExternalStorage.request();
    } else {
      s = await Permission.storage.request();
    }
    if (!s.isGranted) await openAppSettings();
    await widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pad = MediaQuery.of(context).padding;
    return Scaffold(
      body: Padding(
        padding: EdgeInsets.fromLTRB(28, pad.top + 24, 28, pad.bottom + 28),
        child: Column(children: [
          Expanded(
            child: Center(
              child: AnimatedBuilder(
                animation: ac,
                builder: (_, __) {
                  final v = Curves.easeInOut.transform(ac.value);
                  return Stack(alignment: Alignment.center, children: [
                    Container(width: 260 + v * 24, height: 260 + v * 24, decoration: BoxDecoration(color: cs.primaryContainer.withOpacity(.35), borderRadius: BorderRadius.circular(110 + v * 20))),
                    Container(width: 190, height: 190, decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(64 + v * 22)), child: Icon(Icons.folder_rounded, size: 100, color: cs.onPrimaryContainer)),
                  ]);
                },
              ),
            ),
          ),
          Appear(child: Text(t('storage_access'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800))),
          const SizedBox(height: 28),
          Appear(i: 1, child: SizedBox(width: double.infinity, height: 64, child: FilledButton.icon(onPressed: _ask, icon: const Icon(Icons.lock_open_rounded), label: Text(t('allow'), style: const TextStyle(fontSize: 17))))),
        ]),
      ),
    );
  }
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
    HapticFeedback.mediumImpact();
    if (running) { Core.ftpStop(); setState(() => running = false); return; }
    if (random) pass.text = _rnd();
    final pt = int.tryParse(port.text) ?? 2121;
    final ok = Core.ftpStart(root, pt, user.text, pass.text, hid);
    st.pr.setString('ftp_user', user.text); st.pr.setInt('ftp_port', pt);
    if (!ok) snack(context, Core.lib == null ? t('error') : t('port_busy'));
    setState(() => running = ok);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final addr = 'ftp://$ip:${port.text}';
    return Scaffold(
      appBar: AppBar(title: Text(t('ftp_title'), style: const TextStyle(fontWeight: FontWeight.w700))),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 40), children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: running ? cs.primaryContainer : cs.surfaceContainer, borderRadius: BorderRadius.circular(32)),
          child: Column(children: [
            AnimatedSwitcher(duration: const Duration(milliseconds: 300), child: Icon(running ? Icons.wifi_tethering_rounded : Icons.wifi_tethering_off_rounded, key: ValueKey(running), size: 44, color: running ? cs.onPrimaryContainer : cs.outline)),
            const SizedBox(height: 14),
            SelectableText(addr, textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: running ? cs.onPrimaryContainer : cs.onSurface)),
            const SizedBox(height: 10),
            Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 4, children: [
              SelectableText(user.text, style: TextStyle(color: running ? cs.onPrimaryContainer : cs.onSurface)),
              SelectableText(pass.text, style: TextStyle(color: running ? cs.onPrimaryContainer : cs.onSurface)),
            ]),
            const SizedBox(height: 8),
            IconButton(icon: const Icon(Icons.copy_rounded), onPressed: () { Clipboard.setData(ClipboardData(text: addr)); HapticFeedback.selectionClick(); }),
          ]),
        ),
        const SizedBox(height: 18),
        TextField(controller: user, enabled: !running, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: t('login'))),
        const SizedBox(height: 12),
        TextField(controller: pass, enabled: !running && !random, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: t('password'))),
        const SizedBox(height: 12),
        TextField(controller: port, enabled: !running, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}), decoration: InputDecoration(labelText: t('port'))),
        const SizedBox(height: 8),
        SwitchListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 4), title: Text(t('random_pass')), value: random, onChanged: running ? null : (v) => setState(() => random = v)),
        SwitchListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 4), title: Text(t('hidden')), value: hid, onChanged: running ? null : (v) => setState(() => hid = v)),
        const SizedBox(height: 14),
        SizedBox(
          height: 64,
          child: running
              ? FilledButton.tonalIcon(onPressed: _toggle, icon: const Icon(Icons.stop_rounded), label: Text(t('stop')))
              : FilledButton.icon(onPressed: _toggle, icon: const Icon(Icons.play_arrow_rounded), label: Text(t('start'))),
        ),
      ]),
    );
  }
}

// ============================== SETTINGS ==============================
const _palette = [0xFFFFFFFF, 0xFF6750A4, 0xFF1E88E5, 0xFF00897B, 0xFF43A047, 0xFFF9A825, 0xFFFF7043, 0xFFE53935, 0xFFD81B60, 0xFF8E24AA, 0xFF546E7A];
const _folders = [0xFFFFFFFF, 0xFFFFB300, 0xFFFFA726, 0xFF42A5F5, 0xFF66BB6A, 0xFFEF5350, 0xFFAB47BC, 0xFF26C6DA, 0xFF8D6E63];
const _bgs = [0xFFFFFFFF, 0xFFFFF8E1, 0xFFE3F2FD, 0xFFE8F5E9, 0xFFFCE4EC, 0xFF1A1A2E, 0xFF1B1B1B, 0xFF263238];

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Widget _section(BuildContext c, String title, Widget body, int i) => Appear(
        i: i,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 14),
                body,
              ]),
            ),
          ),
        ),
      );

  Widget _dots(List<int> cols, int cur, void Function(int) on, {bool auto = false}) => Wrap(spacing: 12, runSpacing: 12, children: [
        for (final c in [if (auto) 0, ...cols])
          Builder(builder: (ctx) {
            final cs = Theme.of(ctx).colorScheme;
            final sel = c == cur;
            return Tap(
              onTap: () => on(c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 46, height: 46,
                decoration: BoxDecoration(
                  color: c == 0 ? cs.surfaceContainerHighest : Color(c),
                  borderRadius: BorderRadius.circular(sel ? 16 : 23),
                  border: Border.all(color: sel ? cs.onSurface : cs.outlineVariant, width: sel ? 3 : 1),
                ),
                child: c == 0 ? Icon(Icons.auto_awesome_rounded, size: 20, color: cs.onSurface) : (sel ? Icon(Icons.check_rounded, color: Color(c).computeLuminance() > .5 ? Colors.black : Colors.white) : null),
              ),
            );
          }),
      ]);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: st,
        builder: (context, _) => Scaffold(
          appBar: AppBar(title: Text(t('settings'), style: const TextStyle(fontWeight: FontWeight.w700))),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
            _section(
              context, t('theme'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in [[0, 'system', Icons.brightness_auto_rounded], [1, 'light', Icons.light_mode_rounded], [2, 'dark', Icons.dark_mode_rounded], [3, 'oled', Icons.contrast_rounded]])
                  ChoiceChip(
                    avatar: Icon(e[2] as IconData, size: 18),
                    label: Text(t(e[1] as String)),
                    selected: st.theme == e[0],
                    onSelected: (_) { HapticFeedback.selectionClick(); st.setInt('theme', e[0] as int); },
                  ),
              ]),
              0,
            ),
            _section(context, t('accent'), _dots(_palette, st.accent, (c) => st.setInt('accent', c), auto: true), 1),
            _section(context, t('folder_color'), _dots(_folders, st.folder, (c) => st.setInt('folder', c)), 2),
            _section(
              context, t('bg_color'),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SwitchListTile(contentPadding: EdgeInsets.zero, title: Text(t('accent_bg')), value: st.accentBg, onChanged: (v) { HapticFeedback.selectionClick(); st.setAccentBg(v); }),
                const SizedBox(height: 6),
                _dots(_bgs, st.bg, (c) => st.setInt('bg', st.bg == c ? 0 : c), auto: true),
              ]),
              3,
            ),
            _section(
              context, t('font'),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(st.fontPath == null ? 'Disket Mono' : p.basename(st.fontPath!)),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.font_download_rounded),
                    label: Text(t('font_pick')),
                    onPressed: () async {
                      final files = await FilePicker.pickFiles(type: FileType.any);
                      final f = files.isEmpty ? null : files.single.path;
                      if (f != null && f.toLowerCase().endsWith('.ttf')) {
                        final dir = await getApplicationSupportDirectory();
                        final dst = '${dir.path}/user_font_${DateTime.now().millisecondsSinceEpoch}.ttf';
                        File(f).copySync(dst);
                        await st.setFont(dst);
                      }
                    },
                  ),
                  OutlinedButton.icon(icon: const Icon(Icons.restart_alt_rounded), onPressed: () => st.setFont(null), label: Text(t('font_default'))),
                ]),
              ]),
              4,
            ),
          ]),
        ),
      );
}

// ============================== ABOUT ==============================
class TgAvatar extends StatefulWidget {
  final String user;
  final double size;
  const TgAvatar(this.user, {super.key, this.size = 72});
  @override
  State<TgAvatar> createState() => _TgAvatarState();
}

class _TgAvatarState extends State<TgAvatar> {
  Uint8List? bytes;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<Uint8List?> _get(HttpClient c, String url, {int depth = 0}) async {
    final req = await c.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/124 Mobile Safari/537.36');
    req.followRedirects = true;
    final res = await req.close().timeout(const Duration(seconds: 12));
    if (res.statusCode != 200) return null;
    final b = BytesBuilder();
    await for (final d in res) { b.add(d); }
    return b.takeBytes();
  }

  Future<void> _load() async {
    final dir = await getApplicationSupportDirectory();
    final f = File('${dir.path}/tg_${widget.user}.jpg');
    if (f.existsSync()) { final b = await f.readAsBytes(); if (mounted) setState(() => bytes = b); }
    final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final page = await _get(c, 'https://t.me/${widget.user}');
      if (page == null) return;
      final html = String.fromCharCodes(page);
      final m = RegExp(r'<meta property="og:image" content="([^"]+)"').firstMatch(html);
      if (m == null) return;
      final url = m.group(1)!.replaceAll('&amp;', '&');
      final img = await _get(c, url);
      if (img != null && img.length > 500) {
        await f.writeAsBytes(img);
        if (mounted) setState(() => bytes = img);
      }
    } catch (_) {
    } finally { c.close(force: true); }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.size * .34),
      child: SizedBox(
        width: widget.size, height: widget.size,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: bytes != null
              ? Image.memory(bytes!, key: const ValueKey('i'), fit: BoxFit.cover, width: widget.size, height: widget.size, gaplessPlayback: true)
              : Container(key: const ValueKey('p'), color: cs.primaryContainer, alignment: Alignment.center, child: Text(widget.user[0].toUpperCase(), style: TextStyle(fontSize: widget.size * .4, fontWeight: FontWeight.w800, color: cs.onPrimaryContainer))),
        ),
      ),
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});
  static const devs = [
    ['Господин', 'Lyzos'],
    ['Опти', 'optimist_opti'],
    ['LuDev', 'LuPlugins'],
  ];

  Future<void> _license(BuildContext context) async {
    final txt = await rootBundle.loadString('assets/LICENSE.txt');
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false, initialChildSize: .8, maxChildSize: .95,
        builder: (_, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(24, 0, 24, 32), children: [
          Text(txt, style: const TextStyle(fontSize: 12.5, height: 1.5)),
          const SizedBox(height: 20),
          OutlinedButton.icon(icon: const Icon(Icons.extension_rounded), label: Text(t('licenses')), onPressed: () { Navigator.pop(c); showLicensePage(context: context, applicationName: 'Files You'); }),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottom = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      appBar: AppBar(title: Text(t('about'), style: const TextStyle(fontWeight: FontWeight.w700))),
      body: Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 20), children: [
            Appear(
              child: Center(
                child: Column(children: [
                  ClipRRect(borderRadius: BorderRadius.circular(34), child: Image.asset('assets/icon.png', width: 112, height: 112)),
                  const SizedBox(height: 14),
                  Text('Files You', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
            const SizedBox(height: 28),
            for (var i = 0; i < devs.length; i++)
              Appear(
                i: i + 1,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Tap(
                    scale: .97,
                    onTap: () => launchUrl(Uri.parse('https://t.me/${devs[i][1]}'), mode: LaunchMode.externalApplication),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: cs.surfaceContainer, borderRadius: BorderRadius.circular(32)),
                      child: Row(children: [
                        TgAvatar(devs[i][1], size: 76),
                        const SizedBox(width: 16),
                        Expanded(child: Text(devs[i][0], softWrap: true, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
                        Icon(Icons.north_east_rounded, color: cs.onSurfaceVariant),
                        const SizedBox(width: 6),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ),
        Tap(
          onTap: () => _license(context),
          scale: .98,
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 10, 24, bottom + 16),
            child: Column(children: [
              Text('Files You Non-Commercial License 1.0', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
              const SizedBox(height: 2),
              Text('© 2026 Господин (@lyzos)', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ]),
          ),
        ),
      ]),
    );
  }
}
