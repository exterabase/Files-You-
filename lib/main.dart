import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'home.dart';
import 'other.dart';
import 'settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  await st.load();
  runApp(const App());
}

ThemeData mk(Brightness b, ColorScheme? dyn) {
  final dark = b == Brightness.dark;
  final seed = st.accent == 0xFFFFFFFF ? const Color(0xFF00897B) : Color(st.accent == 0 ? 0xFF6750A4 : st.accent);
  var cs = (st.accent == 0 && dyn != null)
      ? dyn
      : ColorScheme.fromSeed(seedColor: seed, brightness: b);
  Color scaffold = cs.surface;
  if (dark && st.theme == 3) {
    scaffold = Colors.black;
    cs = cs.copyWith(surface: Colors.black, surfaceContainer: const Color(0xFF0C0C0C), surfaceContainerHigh: const Color(0xFF161616), surfaceContainerHighest: const Color(0xFF202020));
  } else if (st.bg != 0) {
    final bg = Color(st.bg);
    scaffold = bg;
    Color m(double a) => Color.lerp(bg, cs.onSurface, a)!;
    cs = cs.copyWith(surface: bg, surfaceContainer: m(.05), surfaceContainerHigh: m(.09), surfaceContainerHighest: m(.14));
  } else if (!st.accentBg) {
    scaffold = dark ? const Color(0xFF121212) : const Color(0xFFF4F4F4);
    cs = cs.copyWith(
      surface: scaffold,
      surfaceContainer: dark ? const Color(0xFF1C1C1C) : Colors.white,
      surfaceContainerHigh: dark ? const Color(0xFF242424) : const Color(0xFFECECEC),
      surfaceContainerHighest: dark ? const Color(0xFF2E2E2E) : const Color(0xFFE4E4E4),
    );
  }
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    scaffoldBackgroundColor: scaffold,
    fontFamily: st.fontFamily,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(backgroundColor: scaffold, surfaceTintColor: Colors.transparent, scrolledUnderElevation: 0, centerTitle: false),
    cardTheme: CardThemeData(elevation: 0, color: cs.surfaceContainer, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)), margin: EdgeInsets.zero),
    dialogTheme: DialogThemeData(backgroundColor: cs.surfaceContainerHigh, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32))),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: cs.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
    ),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(64, 56), shape: const StadiumBorder())),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size(64, 52), shape: const StadiumBorder())),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerHigh,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide.none),
    ),
    snackBarTheme: SnackBarThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
  );
}

class App extends StatelessWidget {
  const App({super.key});

  ThemeMode _mode() {
    if (st.theme == 3) return ThemeMode.dark;
    if (st.bg != 0) return Color(st.bg).computeLuminance() < .5 ? ThemeMode.dark : ThemeMode.light;
    return const [ThemeMode.system, ThemeMode.light, ThemeMode.dark][st.theme];
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: st,
        builder: (_, __) => DynamicColorBuilder(
          builder: (l, d) => MaterialApp(
            title: 'Files You',
            debugShowCheckedModeBanner: false,
            themeMode: _mode(),
            theme: mk(Brightness.light, l),
            darkTheme: mk(Brightness.dark, d),
            builder: (c, child) {
              final dark = Theme.of(c).brightness == Brightness.dark;
              final ic = dark ? Brightness.light : Brightness.dark;
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  systemNavigationBarColor: Colors.transparent,
                  systemNavigationBarContrastEnforced: false,
                  statusBarIconBrightness: ic,
                  systemNavigationBarIconBrightness: ic,
                ),
                child: child!,
              );
            },
            home: const Boot(),
          ),
        ),
      );
}
