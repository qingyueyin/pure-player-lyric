import 'dart:ffi';

import 'package:desktop_lyric/component/foreground.dart';
import 'package:desktop_lyric/message.dart';
import 'package:ffi/ffi.dart' as ffi;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:win32/win32.dart' as win32;
import 'package:window_manager/window_manager.dart';

const WHITE_TRANSPARENT = Color.fromARGB(0, 255, 255, 255);
const BLACK_TRANSPARENT = Color.fromARGB(0, 0, 0, 0);
final ValueNotifier<double> BACKGROUND_OPACITY = ValueNotifier(0);

class DesktopLyricBody extends StatefulWidget {
  const DesktopLyricBody({super.key});

  @override
  State<DesktopLyricBody> createState() => _DesktopLyricBodyState();
}

class _DesktopLyricBodyState extends State<DesktopLyricBody> {
  bool isHovering = false;
  int? _hWnd;
  int? _startCursorX;
  int? _startCursorY;
  int? _startWindowLeft;
  int? _startWindowTop;

  int? _ensureHwnd() {
    if (_hWnd != null && _hWnd != 0) return _hWnd;
    final className = win32.TEXT("FLUTTER_RUNNER_WIN32_WINDOW");
    final windowName = win32.TEXT("desktop_lyric");
    final found = win32.FindWindow(className, windowName);
    win32.free(className);
    win32.free(windowName);
    _hWnd = found != 0 ? found : null;
    return _hWnd;
  }

  void _startMove() {
    final hWnd = _ensureHwnd();
    if (hWnd == null) return;

    final pt = ffi.calloc<win32.POINT>();
    win32.GetCursorPos(pt);
    _startCursorX = pt.ref.x;
    _startCursorY = pt.ref.y;
    ffi.calloc.free(pt);

    final rect = ffi.calloc<win32.RECT>();
    win32.GetWindowRect(hWnd, rect);
    _startWindowLeft = rect.ref.left;
    _startWindowTop = rect.ref.top;
    ffi.calloc.free(rect);
  }

  void _updateMove() {
    final hWnd = _ensureHwnd();
    if (hWnd == null) return;
    if (_startCursorX == null ||
        _startCursorY == null ||
        _startWindowLeft == null ||
        _startWindowTop == null) {
      return;
    }

    final pt = ffi.calloc<win32.POINT>();
    win32.GetCursorPos(pt);
    final dx = pt.ref.x - _startCursorX!;
    final dy = pt.ref.y - _startCursorY!;
    ffi.calloc.free(pt);

    win32.SetWindowPos(
      hWnd,
      win32.NULL,
      _startWindowLeft! + dx,
      _startWindowTop! + dy,
      0,
      0,
      win32.SET_WINDOW_POS_FLAGS.SWP_NOSIZE |
          win32.SET_WINDOW_POS_FLAGS.SWP_NOZORDER |
          win32.SET_WINDOW_POS_FLAGS.SWP_NOACTIVATE,
    );
  }

  void _endMove() {
    _startCursorX = null;
    _startCursorY = null;
    _startWindowLeft = null;
    _startWindowTop = null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeChangedMessage>();

    return ValueListenableBuilder(
      valueListenable: BACKGROUND_OPACITY,
      builder: (context, opacity, _) {
        final baseOpacity = opacity;
        final effectiveOpacity = isHovering
            ? (baseOpacity < 0.12 ? 0.12 : baseOpacity)
            : baseOpacity;
        final background = Color(
          theme.surfaceContainer,
        ).withValues(alpha: effectiveOpacity);
        return Scaffold(
          backgroundColor: background,
          body: DragToResizeArea(
            enableResizeEdges: const [],
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: (_) => _startMove(),
              onPanUpdate: (_) => _updateMove(),
              onPanEnd: (_) => _endMove(),
              onPanCancel: _endMove,
              child: MouseRegion(
                onEnter: (_) {
                  setState(() {
                    isHovering = true;
                  });
                },
                onExit: (_) {
                  setState(() {
                    isHovering = false;
                  });
                },
                child: SizedBox(
                  width: double.infinity,
                  height: double.infinity,
                  child: DesktopLyricForeground(isHovering: isHovering),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
