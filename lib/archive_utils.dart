import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

bool isArchiveExt(String ext) => const {'zip', 'tar', 'gz', 'tgz', '7z'}.contains(ext);

Archive _decode(String path) {
  final bytes = File(path).readAsBytesSync();
  final ext = p.extension(path).toLowerCase();
  if (ext == '.zip') return ZipDecoder().decodeBytes(bytes);
  if (ext == '.gz' || ext == '.tgz') return TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes));
  if (ext == '.tar') return TarDecoder().decodeBytes(bytes);
  throw UnsupportedError('7z');
}

class ArchiveEntry {
  final String name;
  final bool isFile;
  final int size;
  const ArchiveEntry(this.name, this.isFile, this.size);
}

List<ArchiveEntry> archiveEntries(String path) => _decode(path).files
    .map((e) => ArchiveEntry(e.name.replaceAll('\\', '/'), e.isFile, e.size))
    .toList();

List<ArchiveEntry> archiveEntriesAt(String path, String prefix) {
  final root = prefix.isEmpty ? '' : '${prefix.replaceAll('\\', '/').replaceAll(RegExp(r'^/+|/+$'), '')}/';
  final children = <String, ArchiveEntry>{};
  for (final entry in archiveEntries(path)) {
    if (!entry.name.startsWith(root) || entry.name == root) continue;
    final rest = entry.name.substring(root.length);
    final slash = rest.indexOf('/');
    if (slash < 0) {
      children[rest] = entry;
    } else {
      final name = rest.substring(0, slash);
      children[name] = ArchiveEntry('$root$name/', false, 0);
    }
  }
  return children.values.toList()..sort((a, b) {
    final dirs = (a.isFile ? 1 : 0).compareTo(b.isFile ? 1 : 0);
    return dirs != 0 ? dirs : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
}

Future<int> extractArchive(String path, String destination) async {
  return extractArchiveEntries(path, destination, null);
}

Future<int> extractArchiveEntries(String path, String destination, Set<String>? selected) async {
  final archive = _decode(path);
  var count = 0;
  final root = Directory(destination)..createSync(recursive: true);
  final names = selected?.map((s) => s.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '')).toSet();
  for (final entry in archive) {
    if (names != null && names.isNotEmpty && !names.any((s) => entry.name == s || entry.name.startsWith('$s/'))) continue;
    final target = p.normalize(p.join(root.path, entry.name));
    if (!p.isWithin(root.path, target) && target != root.path) {
      throw const FormatException('Archive contains an unsafe path');
    }
    if (!entry.isFile) {
      Directory(target).createSync(recursive: true);
      continue;
    }
    final file = File(target)..parent.createSync(recursive: true);
    file.writeAsBytesSync(entry.content as List<int>);
    count++;
  }
  return count;
}
