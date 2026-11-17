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

List<String> archiveEntries(String path) => _decode(path).files.map((e) => e.name).toList();

Future<int> extractArchive(String path, String destination) async {
  final archive = _decode(path);
  var count = 0;
  final root = Directory(destination)..createSync(recursive: true);
  for (final entry in archive) {
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
