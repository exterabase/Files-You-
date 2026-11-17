import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:highlight/highlight.dart' as hl;
import 'package:markdown/markdown.dart' as md;
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'common.dart';
import 'core.dart';
import 'l10n.dart';
import 'archive_utils.dart';

}

Future<void> openFile(BuildContext context, FE e) async {
  final x = e.ext;
  final opts = <List<dynamic>>[];
  void v(IconData i, String l, VoidCallback f) => opts.add([i, l, f]);
  if (imgExt.contains(x)) v(Icons.image_rounded, t('viewer'), () => go(context, ImageView(path: e.path)));
  if (x == 'svg') v(Icons.image_rounded, t('viewer'), () => go(context, SvgView(path: e.path)));
  if (x == 'md' || x == 'markdown') v(Icons.article_rounded, t('markdown'), () => go(context, MdView(path: e.path)));
  if (audExt.contains(x) || vidExt.contains(x)) v(Icons.play_circle_rounded, t('player'), () => go(context, MediaView(path: e.path)));
  if (isArchiveExt(x)) {
    v(Icons.folder_zip_rounded, t('archive_view'), () => go(context, ArchiveView(path: e.path)));
    v(Icons.unarchive_rounded, t('archive_extract'), () => _extractArchive(context, e.path));
  }
  if (x == 'apk') {
    final packageName = p.basenameWithoutExtension(e.path);
    if (RegExp(r'^[a-zA-Z][\w]*(\.[a-zA-Z][\w]*)+$').hasMatch(packageName)) {
      v(Icons.store_rounded, t('play_market'), () => launchUrl(Uri.parse('market://details?id=$packageName')));
    }
  }
  if (x == 'html' || x == 'htm') {
    v(Icons.web_rounded, t('html_local'), () => go(context, HtmlView(path: e.path)));
    v(Icons.public_rounded, t('html_browser'), () => openInBrowser(e.path));
  }

  Future<void> _extractArchive(BuildContext context, String path) async {
    final destination = '${p.dirname(path)}/${p.basenameWithoutExtension(path)}';
    try {
      final count = await extractArchive(path, destination);
      if (context.mounted) snack(context, '${t('archive_extracted')}: $count');
    } on UnsupportedError {
      await OpenFilex.open(path);
    } catch (e) {
      if (context.mounted) snack(context, '${t('error')}: $e');
    }
  }

  class ArchiveView extends StatefulWidget {
    final String path;
    const ArchiveView({super.key, required this.path});
    @override
    State<ArchiveView> createState() => _ArchiveViewState();
  }

  class _ArchiveViewState extends State<ArchiveView> {
    late Future<List<String>> entries;
    @override
    void initState() {
      super.initState();
      entries = Future(() => archiveEntries(widget.path));
    }

    @override
    Widget build(BuildContext context) => Scaffold(
          appBar: AppBar(title: Text(base(widget.path))),
          body: FutureBuilder<List<String>>(
            future: entries,
            builder: (context, snap) {
              if (snap.hasError) return Center(child: Text('${t('error')}: ${snap.error}'));
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: snap.data!.length,
                itemBuilder: (_, i) => ListTile(leading: const Icon(Icons.insert_drive_file_rounded), title: Text(snap.data![i])),
              );
            },
          ),
        );
  v(Icons.notes_rounded, t('text_editor'), () => go(context, Editor(path: e.path, code: false)));
  v(Icons.code_rounded, t('code_editor'), () => go(context, Editor(path: e.path, code: true)));
  v(Icons.open_in_new_rounded, t('system_open'), () => OpenFilex.open(e.path));
  await showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (c) {
      final cs = Theme.of(c).colorScheme;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
              child: Row(children: [
                Leading(e, 48),
                const SizedBox(width: 12),
                Expanded(child: Text(e.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
              ]),
            ),
            for (var i = 0; i < opts.length; i++)
              Appear(
                i: i,
                child: Tap(
                  scale: .97,
                  onTap: () { Navigator.pop(c); (opts[i][2] as VoidCallback)(); },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: i == 0 ? cs.primaryContainer : cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(22)),
                    child: Row(children: [
                      Icon(opts[i][0] as IconData, color: i == 0 ? cs.onPrimaryContainer : cs.onSurface),
                      const SizedBox(width: 14),
                      Expanded(child: Text(opts[i][1] as String, style: TextStyle(fontWeight: FontWeight.w600, color: i == 0 ? cs.onPrimaryContainer : cs.onSurface))),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      );
    },
  );
}

// ---------- Images / SVG ----------
class ImageView extends StatelessWidget {
  final String path;
  const ImageView({super.key, required this.path});
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        extendBodyBehindAppBar: true,
        appBar: AppBar(backgroundColor: Colors.transparent, foregroundColor: Colors.white, title: Text(base(path), style: const TextStyle(fontSize: 14, color: Colors.white))),
        body: InteractiveViewer(
          minScale: .5, maxScale: 10,
          child: Center(child: Image.file(File(path), fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded, color: Colors.white54, size: 72))),
        ),
      );
}

class SvgView extends StatelessWidget {
  final String path;
  const SvgView({super.key, required this.path});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(base(path), style: const TextStyle(fontSize: 15))),
        body: InteractiveViewer(minScale: .5, maxScale: 10, child: Center(child: Padding(padding: const EdgeInsets.all(20), child: SvgPicture.file(File(path), fit: BoxFit.contain, placeholderBuilder: (_) => const CircularProgressIndicator())))),
      );
}

// ---------- Markdown (GitHub style) ----------
class MdView extends StatelessWidget {
  final String path;
  const MdView({super.key, required this.path});
  @override
  Widget build(BuildContext context) {
    final th = Theme.of(context);
    final cs = th.colorScheme;
    String txt;
    try { txt = utf8.decode(File(path).readAsBytesSync(), allowMalformed: true); } catch (_) { txt = ''; }
    final dir = p.dirname(path);
    final ss = MarkdownStyleSheet.fromTheme(th).copyWith(
      h1: th.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
      h2: th.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      h3: th.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      p: th.textTheme.bodyLarge?.copyWith(height: 1.5),
      a: TextStyle(color: cs.primary, decoration: TextDecoration.underline),
      code: TextStyle(fontFamily: 'monospace', fontSize: 13, backgroundColor: cs.surfaceContainerHighest),
      codeblockPadding: const EdgeInsets.all(14),
      codeblockDecoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(16)),
      blockquoteDecoration: BoxDecoration(border: Border(left: BorderSide(color: cs.outline, width: 4))),
      blockquotePadding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
      horizontalRuleDecoration: BoxDecoration(border: Border(top: BorderSide(color: cs.outlineVariant, width: 2))),
      tableBorder: TableBorder.all(color: cs.outlineVariant),
      tableHead: const TextStyle(fontWeight: FontWeight.w700),
      tableCellsPadding: const EdgeInsets.all(8),
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(base(path), style: const TextStyle(fontSize: 15)),
        actions: [IconButton(icon: const Icon(Icons.edit_rounded), onPressed: () => go(context, Editor(path: path, code: true)))],
      ),
      body: Markdown(
        data: txt,
        selectable: true,
        extensionSet: md.ExtensionSet.gitHubFlavored,
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 60),
        styleSheet: ss,
        onTapLink: (text, href, title) { if (href != null) launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication); },
        imageBuilder: (uri, title, alt) {
          final isSvg = uri.path.toLowerCase().endsWith('.svg');
          if (uri.hasScheme && uri.scheme.startsWith('http')) {
            return isSvg ? SvgPicture.network(uri.toString()) : Image.network(uri.toString(), errorBuilder: (_, __, ___) => const SizedBox.shrink());
          }
          final f = File(p.normalize(p.join(dir, Uri.decodeFull(uri.path))));
          return isSvg ? SvgPicture.file(f) : Image.file(f, errorBuilder: (_, __, ___) => const SizedBox.shrink());
        },
      ),
    );
  }
}

// ---------- Audio / Video ----------
class MediaView extends StatefulWidget {
  final String path;
  const MediaView({super.key, required this.path});
  @override
  State<MediaView> createState() => _MediaViewState();
}

class _MediaViewState extends State<MediaView> {
  late final VideoPlayerController c = VideoPlayerController.file(File(widget.path));
  bool ready = false, err = false;
  bool get video => vidExt.contains(p.extension(widget.path).toLowerCase().replaceFirst('.', ''));

  @override
  void initState() {
    super.initState();
    c.initialize().then((_) { if (mounted) { setState(() => ready = true); c.play(); } }).catchError((_) { if (mounted) setState(() => err = true); });
  }

  @override
  void dispose() { c.dispose(); super.dispose(); }

  String _t(Duration d) => '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(base(widget.path), style: const TextStyle(fontSize: 15))),
      body: err
          ? Center(child: Icon(Icons.error_outline_rounded, size: 72, color: cs.error))
          : !ready
              ? const Center(child: CircularProgressIndicator())
              : SafeArea(
                  child: Column(children: [
                    Expanded(
                      child: Center(
                        child: video
                            ? ClipRRect(borderRadius: BorderRadius.circular(24), child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c)))
                            : Container(width: 220, height: 220, decoration: BoxDecoration(color: cs.primaryContainer, borderRadius: BorderRadius.circular(64)), child: Icon(Icons.music_note_rounded, size: 110, color: cs.onPrimaryContainer)),
                      ),
                    ),
                    ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: c,
                      builder: (_, v, __) {
                        final max = v.duration.inMilliseconds.toDouble().clamp(1, double.infinity).toDouble();
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                          child: Column(children: [
                            Slider(value: v.position.inMilliseconds.toDouble().clamp(0, max).toDouble(), max: max, onChanged: (x) => c.seekTo(Duration(milliseconds: x.round()))),
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(_t(v.position)), Text(_t(v.duration))]),
                            const SizedBox(height: 12),
                            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              IconButton(iconSize: 36, icon: const Icon(Icons.replay_10_rounded), onPressed: () => c.seekTo(v.position - const Duration(seconds: 10))),
                              const SizedBox(width: 12),
                              IconButton.filled(iconSize: 44, onPressed: () => v.isPlaying ? c.pause() : c.play(), icon: Icon(v.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded)),
                              const SizedBox(width: 12),
                              IconButton(iconSize: 36, icon: const Icon(Icons.forward_10_rounded), onPressed: () => c.seekTo(v.position + const Duration(seconds: 10))),
                            ]),
                          ]),
                        );
                      },
                    ),
                  ]),
                ),
    );
  }
}

// ---------- Text / code editor ----------
const _langs = {
  'dart': 'dart', 'js': 'javascript', 'json': 'json', 'plugin': 'json', 'html': 'xml', 'htm': 'xml', 'xml': 'xml', 'css': 'css',
  'py': 'python', 'rs': 'rust', 'kt': 'kotlin', 'java': 'java', 'md': 'markdown', 'yaml': 'yaml', 'yml': 'yaml', 'sh': 'bash',
  'ts': 'typescript', 'c': 'cpp', 'cpp': 'cpp', 'h': 'cpp', 'go': 'go', 'sql': 'sql', 'toml': 'ini', 'ini': 'ini', 'lua': 'lua', 'php': 'php', 'svg': 'xml',
};

class CodeCtl extends TextEditingController {
  final String lang;
  final Map<String, TextStyle> theme;
  CodeCtl(String text, this.lang, this.theme) : super(text: text);
  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    try {
      final r = hl.highlight.parse(text, language: lang);
      return TextSpan(style: style, children: _c(r.nodes ?? []));
    } catch (_) {
      return TextSpan(style: style, text: text);
    }
  }

  List<TextSpan> _c(List<hl.Node> ns) => [
        for (final n in ns)
          if (n.value != null) TextSpan(text: n.value, style: n.className != null ? _s(n.className!) : null)
          else TextSpan(children: _c(n.children ?? []), style: n.className != null ? _s(n.className!) : null)
      ];

  // keep only the color so the background of the theme never clashes with ours
  TextStyle? _s(String k) { final s = theme[k]; return s == null ? null : TextStyle(color: s.color, fontStyle: s.fontStyle, fontWeight: s.fontWeight); }
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
    if (c != null || err) return;
    try {
      final txt = utf8.decode(File(widget.path).readAsBytesSync(), allowMalformed: false);
      final dark = Theme.of(context).brightness == Brightness.dark;
      final lang = _langs[p.extension(widget.path).toLowerCase().replaceFirst('.', '')] ?? 'plaintext';
      c = widget.code ? CodeCtl(txt, lang, Map<String, TextStyle>.from(dark ? atomOneDarkTheme : githubTheme)) : TextEditingController(text: txt);
    } catch (_) { err = true; }
  }

  void _save() {
    try { File(widget.path).writeAsStringSync(c!.text); setState(() => dirty = false); snack(context, t('saved')); } catch (_) { snack(context, t('error')); }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final s = await showDialog<int>(
          context: context,
          builder: (d) => AlertDialog(
            icon: const Icon(Icons.save_rounded, size: 34),
            actionsAlignment: MainAxisAlignment.spaceEvenly,
            actions: [
              IconButton.filledTonal(iconSize: 26, onPressed: () => Navigator.pop(d, 0), icon: const Icon(Icons.close_rounded)),
              IconButton.filledTonal(iconSize: 26, onPressed: () => Navigator.pop(d, 1), icon: const Icon(Icons.delete_outline_rounded)),
              IconButton.filled(iconSize: 26, onPressed: () => Navigator.pop(d, 2), icon: const Icon(Icons.check_rounded)),
            ],
          ),
        );
        if (s == 2) _save();
        if ((s == 1 || s == 2) && mounted) { setState(() => dirty = false); Navigator.pop(context); }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(base(widget.path), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          actions: [if (!err) Padding(padding: const EdgeInsets.only(right: 8), child: IconButton.filledTonal(icon: const Icon(Icons.save_rounded), tooltip: t('save'), onPressed: dirty ? _save : null))],
        ),
        body: err
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.block_rounded, size: 64, color: cs.outline), const SizedBox(height: 12), Text(t('cannot_read'))]))
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: TextField(
                    controller: c, maxLines: null, expands: true,
                    keyboardType: TextInputType.multiline,
                    textAlignVertical: TextAlignVertical.top,
                    onChanged: (_) { if (!dirty) setState(() => dirty = true); },
                    style: widget.code ? const TextStyle(fontFamily: 'monospace', fontSize: 13.5, height: 1.4) : const TextStyle(fontSize: 15, height: 1.45),
                    decoration: const InputDecoration(filled: false, border: InputBorder.none),
                  ),
                ),
              ),
      ),
    );
  }
}

// ---------- HTML ----------
class HtmlView extends StatefulWidget {
  final String path;
  const HtmlView({super.key, required this.path});
  @override
  State<HtmlView> createState() => _HtmlViewState();
}

class _HtmlViewState extends State<HtmlView> {
  late final WebViewController w = WebViewController()..setJavaScriptMode(JavaScriptMode.unrestricted)..loadFile(widget.path);
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text(base(widget.path), style: const TextStyle(fontSize: 15))), body: WebViewWidget(controller: w));
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
      await r.response.addStream(f.openRead());
    } else { r.response.statusCode = 404; }
    await r.response.close();
  });
  await launchUrl(Uri.parse('http://127.0.0.1:${_srv!.port}/${Uri.encodeComponent(p.basename(file))}'), mode: LaunchMode.externalApplication);
}
