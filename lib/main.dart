import 'dart:ffi' hide Size;

import 'package:pure_player_lyric/component/desktop_lyric_body.dart';
import 'package:pure_player_lyric/component/foreground.dart';
import 'package:pure_player_lyric/desktop_lyric_controller.dart';
import 'package:flutter/material.dart';
import 'package:ffi/ffi.dart' as ffi;
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:win32/win32.dart' as win32;

int? hWnd;

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  DesktopLyricController.initWithArgs(args);
  textDisplayController.load();

  WindowOptions windowOptions = WindowOptions(
    size: textDisplayController.useVerticalDisplayMode
        ? const Size(220, 900)
        : Size(800, textDisplayController.useMultiLineMode ? 420 : 180),
    center: !textDisplayController.hasWindowBounds,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
    minimumSize: Size(120, 120),
    maximumSize: Size(2400, 2400),
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await _restoreWindowBounds();
    await windowManager.show();
    final className = win32.TEXT("FLUTTER_RUNNER_WIN32_WINDOW");
    final windowName = win32.TEXT("desktop_lyric");
    final foundHWnd = win32.FindWindow(className, windowName);
    win32.free(className);
    win32.free(windowName);
    if (foundHWnd != 0) {
      hWnd = foundHWnd;
      final exStyle = win32.GetWindowLongPtr(foundHWnd, win32.GWL_EXSTYLE);
      win32.SetWindowLongPtr(
        foundHWnd,
        win32.GWL_EXSTYLE,
        (exStyle | win32.WS_EX_TOOLWINDOW) & ~win32.WS_EX_APPWINDOW,
      );
      DesktopLyricController.instance.syncWindowVisibility();
      DesktopLyricController.instance.syncUnlockButtonStyle();
    }
  });

  runApp(const DesktopLyricApp());
}

Future<void> _restoreWindowBounds() async {
  if (!textDisplayController.hasWindowBounds) return;
  final windowHandle = _findWindowHandle();
  if (windowHandle == 0) return;
  final savedLeft = textDisplayController.windowX!.round();
  final savedTop = textDisplayController.windowY!.round();
  final savedWidth = textDisplayController.windowWidth!.round();
  final savedHeight = textDisplayController.windowHeight!.round();
  final point = ffi.calloc<win32.POINT>();
  point.ref.x = savedLeft + savedWidth ~/ 2;
  point.ref.y = savedTop + savedHeight ~/ 2;
  final monitor = win32.MonitorFromPoint(
    point.ref,
    win32.MONITOR_DEFAULTTONEAREST,
  );
  final monitorInfo = ffi.calloc<win32.MONITORINFO>();
  monitorInfo.ref.cbSize = sizeOf<win32.MONITORINFO>();
  final hasMonitor =
      monitor != 0 && win32.GetMonitorInfo(monitor, monitorInfo) != 0;
  if (!hasMonitor) {
    ffi.calloc.free(point);
    ffi.calloc.free(monitorInfo);
    await _restoreDefaultWindowBounds();
    return;
  }
  final workArea = Rect.fromLTRB(
    monitorInfo.ref.rcWork.left.toDouble(),
    monitorInfo.ref.rcWork.top.toDouble(),
    monitorInfo.ref.rcWork.right.toDouble(),
    monitorInfo.ref.rcWork.bottom.toDouble(),
  );
  if (savedWidth <= 0 ||
      savedHeight <= 0 ||
      savedWidth > workArea.width ||
      savedHeight > workArea.height) {
    ffi.calloc.free(point);
    ffi.calloc.free(monitorInfo);
    await _restoreDefaultWindowBounds();
    return;
  }
  final left = savedLeft
      .clamp(workArea.left, workArea.right - savedWidth)
      .toInt();
  final top = savedTop
      .clamp(workArea.top, workArea.bottom - savedHeight)
      .toInt();
  win32.SetWindowPos(
    windowHandle,
    win32.NULL,
    left,
    top,
    savedWidth,
    savedHeight,
    win32.SWP_NOZORDER | win32.SWP_NOACTIVATE,
  );
  ffi.calloc.free(point);
  ffi.calloc.free(monitorInfo);
}

Future<void> _restoreDefaultWindowBounds() async {
  final size = textDisplayController.useVerticalDisplayMode
      ? const Size(220, 900)
      : Size(800, textDisplayController.useMultiLineMode ? 420 : 180);
  await windowManager.setSize(size);
  await windowManager.center();
}

int _findWindowHandle() {
  final className = win32.TEXT("FLUTTER_RUNNER_WIN32_WINDOW");
  final windowName = win32.TEXT("desktop_lyric");
  final found = win32.FindWindow(className, windowName);
  win32.free(className);
  win32.free(windowName);
  return found;
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
          scrollBehavior: const _NoScrollbarBehavior(),
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
      languageCode: 'zh',
      scriptCode: 'Hans',
      countryCode: 'CN',
    ),
    Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hant',
      countryCode: 'TW',
    ),
    Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hans',
      countryCode: 'HK',
    ),
    Locale("en", "US"),
  ];
}

// 歌词窗口不需要自动滚动条，框架默认会给 Windows 上的垂直滚动组件加
class _NoScrollbarBehavior extends MaterialScrollBehavior {
  const _NoScrollbarBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
