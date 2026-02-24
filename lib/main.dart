import 'package:desktop_lyric/component/desktop_lyric_body.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:win32/win32.dart' as win32;

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  DesktopLyricController.initWithArgs(args);

  WindowOptions windowOptions = const WindowOptions(
    size: Size(800, 122),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
    minimumSize: Size(400, 122),
    maximumSize: Size(2400, 122),
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.show();
    final className = win32.TEXT("FLUTTER_RUNNER_WIN32_WINDOW");
    final windowName = win32.TEXT("desktop_lyric");
    final hWnd = win32.FindWindow(className, windowName);
    win32.free(className);
    win32.free(windowName);
    if (hWnd != 0) {
      final exStyle = win32.GetWindowLongPtr(
        hWnd,
        win32.WINDOW_LONG_PTR_INDEX.GWL_EXSTYLE,
      );
      win32.SetWindowLongPtr(
        hWnd,
        win32.WINDOW_LONG_PTR_INDEX.GWL_EXSTYLE,
        (exStyle | win32.WINDOW_EX_STYLE.WS_EX_TOOLWINDOW) &
            ~win32.WINDOW_EX_STYLE.WS_EX_APPWINDOW,
      );
    }
  });

  runApp(const DesktopLyricApp());
}

class DesktopLyricApp extends StatelessWidget {
  const DesktopLyricApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: DesktopLyricController.instance.isDarkMode,
      builder: (context, isDarkMode, _) => ValueListenableProvider.value(
        value: DesktopLyricController.instance.theme,
        child: MaterialApp(
          themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          supportedLocales: supportedLocales,
          home: const DesktopLyricBody(),
        ),
      ),
    );
  }

  final supportedLocales = const [
    Locale.fromSubtags(languageCode: 'zh'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
    Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    Locale.fromSubtags(
        languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN'),
    Locale.fromSubtags(
        languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW'),
    Locale.fromSubtags(
        languageCode: 'zh', scriptCode: 'Hant', countryCode: 'HK'),
    Locale("en", "US"),
  ];
}
