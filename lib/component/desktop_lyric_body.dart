import 'dart:async';
import 'dart:ffi';

import 'package:pure_player_lyric/component/foreground.dart';
import 'package:pure_player_lyric/desktop_lyric_controller.dart';
import 'package:pure_player_lyric/message.dart';
import 'package:ffi/ffi.dart' as ffi;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:win32/win32.dart' as win32;
import 'package:window_manager/window_manager.dart';

const whiteTransparent = Color.fromARGB(0, 255, 255, 255);
const blackTransparent = Color.fromARGB(0, 0, 0, 0);

const double _resizeAreaSize = 12.0;

class DesktopLyricBody extends StatefulWidget {
  const DesktopLyricBody({super.key});

  @override
  State<DesktopLyricBody> createState() => _DesktopLyricBodyState();
}

class _DesktopLyricBodyState extends State<DesktopLyricBody> {
  bool isHovering = false;
  bool _isResizing = false;
  Timer? _resizeReleaseTimer;
  int? _hWnd;
  int? _startCursorX;
  int? _startCursorY;
  int? _startWindowLeft;
  int? _startWindowTop;

  @override
  void initState() {
    super.initState();
    DesktopLyricController.instance.isLocked.addListener(_handleLockChanged);
    textDisplayController.addListener(_syncPinTop);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPinTop());
  }

  @override
  void dispose() {
    _resizeReleaseTimer?.cancel();
    DesktopLyricController.instance.isLocked.removeListener(_handleLockChanged);
    textDisplayController.removeListener(_syncPinTop);
    if (_isResizing) {
      DesktopLyricController.instance.setWindowInteractionActive(false);
    }
    super.dispose();
  }

  void _handleLockChanged() {
    if (!DesktopLyricController.instance.isLocked.value || !isHovering) return;
    setState(() => isHovering = false);
  }

  void _syncPinTop() {
    final hWnd = _ensureHwnd();
    if (hWnd == null) return;
    win32.SetWindowPos(
      hWnd,
      textDisplayController.enablePinTop
          ? win32.HWND_TOPMOST
          : win32.HWND_NOTOPMOST,
      0,
      0,
      0,
      0,
      win32.SWP_NOMOVE | win32.SWP_NOSIZE | win32.SWP_NOACTIVATE,
    );
  }

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
    if (DesktopLyricController.instance.isLocked.value) return;
    final hWnd = _ensureHwnd();
    if (hWnd == null) return;
    DesktopLyricController.instance.setWindowInteractionActive(true);

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

  Rect? _getBoundsForWindow(int hWnd) {
    final rect = ffi.calloc<win32.RECT>();
    win32.GetWindowRect(hWnd, rect);
    final windowRect = Rect.fromLTRB(
      rect.ref.left.toDouble(),
      rect.ref.top.toDouble(),
      rect.ref.right.toDouble(),
      rect.ref.bottom.toDouble(),
    );
    ffi.calloc.free(rect);

    final windowCenterX = windowRect.center.dx;
    final windowCenterY = windowRect.center.dy;

    final point = ffi.calloc<win32.POINT>();
    point.ref.x = windowCenterX.toInt();
    point.ref.y = windowCenterY.toInt();
    var monitor = win32.MonitorFromPoint(
      point.ref,
      win32.MONITOR_DEFAULTTONEAREST,
    );
    ffi.calloc.free(point);

    if (monitor == 0) {
      monitor = win32.MonitorFromWindow(hWnd, win32.MONITOR_DEFAULTTONEAREST);
    }

    if (monitor == 0) return null;

    final monitorInfo = ffi.calloc<win32.MONITORINFO>();
    monitorInfo.ref.cbSize = sizeOf<win32.MONITORINFO>();
    win32.GetMonitorInfo(monitor, monitorInfo);

    final monitorRect = Rect.fromLTRB(
      monitorInfo.ref.rcMonitor.left.toDouble(),
      monitorInfo.ref.rcMonitor.top.toDouble(),
      monitorInfo.ref.rcMonitor.right.toDouble(),
      monitorInfo.ref.rcMonitor.bottom.toDouble(),
    );
    ffi.calloc.free(monitorInfo);

    return monitorRect;
  }

  void _updateMove() {
    if (DesktopLyricController.instance.isLocked.value) return;
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

    var newLeft = _startWindowLeft! + dx;
    var newTop = _startWindowTop! + dy;

    final monitorRect = _getBoundsForWindow(hWnd);
    if (monitorRect != null) {
      final windowWidth = monitorRect.width * 0.3;
      final windowHeight = monitorRect.height * 0.3;

      if (newLeft + windowWidth ~/ 2 < monitorRect.left) {
        newLeft = (monitorRect.left - windowWidth / 2).toInt();
      }
      if (newLeft - windowWidth ~/ 2 > monitorRect.right) {
        newLeft = (monitorRect.right - windowWidth / 2).toInt();
      }
      if (newTop + windowHeight ~/ 2 < monitorRect.top) {
        newTop = (monitorRect.top - windowHeight / 2).toInt();
      }
      if (newTop - windowHeight ~/ 2 > monitorRect.bottom) {
        newTop = (monitorRect.bottom - windowHeight / 2).toInt();
      }
    }

    win32.SetWindowPos(
      hWnd,
      win32.NULL,
      newLeft,
      newTop,
      0,
      0,
      win32.SWP_NOSIZE | win32.SWP_NOZORDER | win32.SWP_NOACTIVATE,
    );
  }

  void _endMove() {
    _startCursorX = null;
    _startCursorY = null;
    _startWindowLeft = null;
    _startWindowTop = null;
    DesktopLyricController.instance.setWindowInteractionActive(false);
  }

  void _startResize(ResizeEdge edge) {
    if (DesktopLyricController.instance.isLocked.value) return;
    _isResizing = true;
    DesktopLyricController.instance.setWindowInteractionActive(true);
    windowManager.startResizing(edge);
    _resizeReleaseTimer?.cancel();
    _resizeReleaseTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (win32.GetAsyncKeyState(win32.VK_LBUTTON) & 0x8000 != 0) return;
      _endResize();
    });
  }

  void _endResize() {
    if (!_isResizing) return;
    _resizeReleaseTimer?.cancel();
    _resizeReleaseTimer = null;
    _isResizing = false;
    DesktopLyricController.instance.setWindowInteractionActive(false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeChangedMessage>();

    return ValueListenableBuilder<bool>(
      valueListenable: DesktopLyricController.instance.isLocked,
      builder: (context, locked, _) => ValueListenableBuilder(
        valueListenable: backgroundOpacity,
        builder: (context, opacity, _) {
          final baseOpacity = opacity;
          final hovering = !locked && isHovering;
          final effectiveOpacity = hovering
              ? (baseOpacity < 0.04 ? 0.04 : baseOpacity)
              : baseOpacity;
          final background = Color(
            theme.surfaceContainer,
          ).withValues(alpha: effectiveOpacity);
          return Scaffold(
            backgroundColor: background,
            body: DragToResizeArea(
              enableResizeEdges: locked
                  ? const []
                  : const [
                      ResizeEdge.left,
                      ResizeEdge.right,
                      ResizeEdge.top,
                      ResizeEdge.bottom,
                      ResizeEdge.topLeft,
                      ResizeEdge.topRight,
                      ResizeEdge.bottomLeft,
                      ResizeEdge.bottomRight,
                    ],
              child: Stack(
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanStart: locked ? null : (_) => _startMove(),
                    onPanUpdate: locked ? null : (_) => _updateMove(),
                    onPanEnd: locked ? null : (_) => _endMove(),
                    onPanCancel: locked ? null : _endMove,
                    child: locked
                        ? const SizedBox(
                            width: double.infinity,
                            height: double.infinity,
                            child: DesktopLyricForeground(isHovering: false),
                          )
                        : MouseRegion(
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
                              child: DesktopLyricForeground(
                                isHovering: isHovering,
                              ),
                            ),
                          ),
                  ),
                  if (!locked) ...[
                    _buildResizeHandle(ResizeEdge.left),
                    _buildResizeHandle(ResizeEdge.right),
                    _buildResizeHandle(ResizeEdge.top),
                    _buildResizeHandle(ResizeEdge.bottom),
                    _buildResizeHandle(ResizeEdge.topLeft),
                    _buildResizeHandle(ResizeEdge.topRight),
                    _buildResizeHandle(ResizeEdge.bottomLeft),
                    _buildResizeHandle(ResizeEdge.bottomRight),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildResizeHandle(ResizeEdge edge) {
    double? left;
    double? right;
    double? top;
    double? bottom;
    double? width;
    double? height;

    switch (edge) {
      case ResizeEdge.left:
        left = 0;
        top = _resizeAreaSize;
        bottom = _resizeAreaSize;
        width = _resizeAreaSize;
      case ResizeEdge.right:
        right = 0;
        top = _resizeAreaSize;
        bottom = _resizeAreaSize;
        width = _resizeAreaSize;
      case ResizeEdge.top:
        top = 0;
        left = _resizeAreaSize;
        right = _resizeAreaSize;
        height = _resizeAreaSize;
      case ResizeEdge.bottom:
        bottom = 0;
        left = _resizeAreaSize;
        right = _resizeAreaSize;
        height = _resizeAreaSize;
      case ResizeEdge.topLeft:
        left = 0;
        top = 0;
      case ResizeEdge.topRight:
        right = 0;
        top = 0;
      case ResizeEdge.bottomLeft:
        left = 0;
        bottom = 0;
      case ResizeEdge.bottomRight:
        right = 0;
        bottom = 0;
    }

    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      width: width,
      height: height,
      child: MouseRegion(
        cursor: _getCursorForEdge(edge),
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: (_) => _startResize(edge),
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }

  SystemMouseCursor _getCursorForEdge(ResizeEdge edge) {
    return switch (edge) {
      ResizeEdge.left || ResizeEdge.right => SystemMouseCursors.resizeLeftRight,
      ResizeEdge.top || ResizeEdge.bottom => SystemMouseCursors.resizeUpDown,
      ResizeEdge.topLeft ||
      ResizeEdge.bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
      ResizeEdge.topRight ||
      ResizeEdge.bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
    };
  }
}
