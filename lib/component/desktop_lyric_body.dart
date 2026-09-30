import 'dart:async';
import 'dart:ffi' hide Size;

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
  Timer? _pinTimer;
  Timer? _hoverHideTimer;
  bool _hoverHidden = false;
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
    textDisplayController.addListener(_syncWindowSizeForMode);
    textDisplayController.addListener(_handleDisplaySettingsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncPinTop();
      _syncWindowSizeForMode();
      _updateHoverHideTimer();
    });
    _pinTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!textDisplayController.enablePinTop) return;
      final hWnd = _ensureHwnd();
      if (hWnd == null) return;
      win32.SetWindowPos(
        hWnd,
        win32.HWND_TOPMOST,
        0,
        0,
        0,
        0,
        win32.SWP_NOMOVE | win32.SWP_NOSIZE | win32.SWP_NOACTIVATE,
      );
    });
  }

  @override
  void dispose() {
    _resizeReleaseTimer?.cancel();
    _pinTimer?.cancel();
    _hoverHideTimer?.cancel();
    DesktopLyricController.instance.isLocked.removeListener(_handleLockChanged);
    textDisplayController.removeListener(_syncPinTop);
    textDisplayController.removeListener(_syncWindowSizeForMode);
    textDisplayController.removeListener(_handleDisplaySettingsChanged);
    if (_isResizing) {
      DesktopLyricController.instance.setWindowInteractionActive(false);
    }
    super.dispose();
  }

  void _handleLockChanged() {
    if (!DesktopLyricController.instance.isLocked.value && isHovering) {
      setState(() => isHovering = false);
    }
    _updateHoverHideTimer();
  }

  void _handleDisplaySettingsChanged() {
    _updateHoverHideTimer();
  }

  void _updateHoverHideTimer() {
    final shouldPoll =
        DesktopLyricController.instance.isLocked.value &&
        textDisplayController.hoverHide;
    if (shouldPoll) {
      _pollHoverHide();
      _hoverHideTimer ??= Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => _pollHoverHide(),
      );
    } else {
      _hoverHideTimer?.cancel();
      _hoverHideTimer = null;
      if (_hoverHidden) setState(() => _hoverHidden = false);
    }
  }

  void _pollHoverHide() {
    final hWnd = _ensureHwnd();
    if (hWnd == null) return;
    final point = ffi.calloc<win32.POINT>();
    final rect = ffi.calloc<win32.RECT>();
    final hasCursor = win32.GetCursorPos(point) != 0;
    final hasWindow = win32.GetWindowRect(hWnd, rect) != 0;
    final inside =
        hasCursor &&
        hasWindow &&
        point.ref.x >= rect.ref.left &&
        point.ref.x < rect.ref.right &&
        point.ref.y >= rect.ref.top &&
        point.ref.y < rect.ref.bottom;
    ffi.calloc.free(point);
    ffi.calloc.free(rect);
    final hidden = inside;
    if (_hoverHidden == hidden || !mounted) return;
    setState(() => _hoverHidden = hidden);
  }

  void _saveWindowBounds() {
    final hWnd = _ensureHwnd();
    if (hWnd == null) return;
    final rect = ffi.calloc<win32.RECT>();
    if (win32.GetWindowRect(hWnd, rect) != 0) {
      textDisplayController.updateWindowBounds(
        x: rect.ref.left.toDouble(),
        y: rect.ref.top.toDouble(),
        width: (rect.ref.right - rect.ref.left).toDouble(),
        height: (rect.ref.bottom - rect.ref.top).toDouble(),
      );
    }
    ffi.calloc.free(rect);
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

  bool? _lastVerticalMode;
  bool? _lastMultiLineMode;

  /// 竖排/横排切换时自动调整窗口尺寸，让竖排歌词有足够高度
  void _syncWindowSizeForMode() {
    final vertical = textDisplayController.useVerticalDisplayMode;
    final multiLine = textDisplayController.useMultiLineMode;
    final isInitialSync =
        _lastVerticalMode == null && _lastMultiLineMode == null;
    if (_lastVerticalMode == vertical && _lastMultiLineMode == multiLine) {
      return;
    }
    _lastVerticalMode = vertical;
    _lastMultiLineMode = multiLine;
    if (isInitialSync && textDisplayController.hasWindowBounds) return;
    windowManager.setSize(
      vertical
          ? const Size(220, 900)
          : Size(800, textDisplayController.useMultiLineMode ? 420 : 180),
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

    final windowRect = ffi.calloc<win32.RECT>();
    if (win32.GetWindowRect(hWnd, windowRect) != 0) {
      final windowWidth = windowRect.ref.right - windowRect.ref.left;
      final windowHeight = windowRect.ref.bottom - windowRect.ref.top;
      final targetPoint = ffi.calloc<win32.POINT>();
      targetPoint.ref.x = newLeft + windowWidth ~/ 2;
      targetPoint.ref.y = newTop + windowHeight ~/ 2;
      final monitor = win32.MonitorFromPoint(
        targetPoint.ref,
        win32.MONITOR_DEFAULTTONEAREST,
      );
      final monitorInfo = ffi.calloc<win32.MONITORINFO>();
      monitorInfo.ref.cbSize = sizeOf<win32.MONITORINFO>();
      if (monitor != 0 && win32.GetMonitorInfo(monitor, monitorInfo) != 0) {
        final monitorRect = monitorInfo.ref.rcMonitor;
        const visibleBand = 60;
        final minLeft = monitorRect.left - windowWidth + visibleBand;
        final maxLeft = monitorRect.right - visibleBand;
        final minTop = monitorRect.top - windowHeight + visibleBand;
        final maxTop = monitorRect.bottom - visibleBand;
        newLeft = minLeft <= maxLeft
            ? newLeft.clamp(minLeft, maxLeft).toInt()
            : monitorRect.left;
        newTop = minTop <= maxTop
            ? newTop.clamp(minTop, maxTop).toInt()
            : monitorRect.top;
      }
      ffi.calloc.free(monitorInfo);
      ffi.calloc.free(targetPoint);
    }
    ffi.calloc.free(windowRect);

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
    _saveWindowBounds();
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
    _saveWindowBounds();
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
          final effectiveOpacity = !locked && isHovering
              ? (baseOpacity < 0.12 ? 0.12 : baseOpacity)
              : 0.0;
          final background = Color(
            theme.surfaceContainer,
          ).withValues(alpha: effectiveOpacity);
          return AnimatedOpacity(
            opacity: locked && _hoverHidden ? 0.05 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: Scaffold(
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
