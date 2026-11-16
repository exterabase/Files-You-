import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'l10n.dart';
import 'screens.dart';
import 'settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await st.load();
  runApp(const App());
}

ThemeData buildTheme(ColorScheme? dyn) {
  final dark = st.theme > 0;
  final b = dark ? Brightness.dark : Brightness.light;
  var cs = (st.accent == 0 && dyn != null)
      ? dyn
      : ColorScheme.fromSeed(seedColor: Color(st.accent == 0 ? 0xFF6750A4 : st.accent), brightness: b);
  Color scaffold = cs.surface;
  if (!st.accentBg) {
    scaffold = dark ? const Color(0xFF121212) : const Color(0xFFF4F4F4);
    cs = cs.copyWith(surface: scaffold, surfaceContainer: dark ? const Color(0xFF1E1E1E) : Colors.white,
        surfaceContainerHigh: dark ? const Color(0xFF262626) : const Color(0xFFEDEDED));
  }
  if (st.theme == 2) {
    scaffold = Colors.black;
    cs = cs.copyWith(surface: Colors.black, surfaceContainer: const Color(0xFF0B0B0B), surfaceContainerHigh: const Color(0xFF141414));
  } else if (st.bg != 0) {
    scaffold = Color(st.bg);
    cs = cs.copyWith(surface: scaffold);
  }
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: scaffold,
    fontFamily: st.fontFamily,
    appBarTheme: AppBarTheme(backgroundColor: scaffold, surfaceTintColor: Colors.transparent),
    navigationBarTheme: NavigationBarThemeData(backgroundColor: cs.surfaceContainer),
  );
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: st,
        builder: (_, __) => DynamicColorBuilder(
          builder: (l, d) => MaterialApp(
            title: 'Files You',
            debugShowCheckedModeBanner: false,
            theme: buildTheme(st.theme == 0 ? l : d),
            home: const Boot(),
          ),
        ),
      );
}

class Boot extends StatefulWidget {
  const Boot({super.key});
  @override
  State<Boot> createState() => _BootState();
}

class _BootState extends State<Boot> {
  @override
  void initState() {
    super.initState();
    () async {
      if (!await Permission.manageExternalStorage.isGranted) {
        if (await Permission.manageExternalStorage.request().isDenied) {
          await Permission.storage.request();
        }
      }
      if (mounted) setState(() {});
    }();
  }

  @override
  Widget build(BuildContext context) => const Home();
}
