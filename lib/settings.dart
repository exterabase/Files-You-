import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class S extends ChangeNotifier {
  late SharedPreferences pr;
  // theme: 0 system, 1 light, 2 dark, 3 oled
  int theme = 0, accent = 0, folder = 0xFFFFFFFF, bg = 0, _fontN = 0;
  bool accentBg = true;
  String? fontPath;
  String? fontFamily;

  Future<void> load() async {
    pr = await SharedPreferences.getInstance();
    theme = pr.getInt('theme2') ?? 0;
    accent = pr.getInt('accent') ?? 0;
    folder = pr.getInt('folder') ?? 0xFFFFFFFF;
    bg = pr.getInt('bg') ?? 0;
    accentBg = pr.getBool('accentBg') ?? true;
    fontPath = pr.getString('fontPath');
    await loadFont();
  }

  Future<void> loadFont() async {
    if (fontPath == null || !File(fontPath!).existsSync()) {
      fontFamily = null;
      return;
    }
    try {
      final d = ByteData.sublistView(await File(fontPath!).readAsBytes());
      final fam = 'UF${_fontN++}';
      final l = FontLoader(fam)..addFont(Future.value(d));
      await l.load();
      fontFamily = fam;
    } catch (_) {
      fontFamily = null;
    }
  }

  Future<void> setInt(String k, int v) async {
    switch (k) {
      case 'theme': theme = v; k = 'theme2'; break;
      case 'accent': accent = v; break;
      case 'folder': folder = v; break;
      case 'bg': bg = v; break;
    }
    await pr.setInt(k, v);
    notifyListeners();
  }

  Future<void> setAccentBg(bool v) async {
    accentBg = v;
    await pr.setBool('accentBg', v);
    notifyListeners();
  }

  Future<void> setFont(String? path) async {
    fontPath = path;
    if (path == null) { await pr.remove('fontPath'); } else { await pr.setString('fontPath', path); }
    await loadFont();
    notifyListeners();
  }
}

final S st = S();
