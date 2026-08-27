import 'dart:collection';
import 'dart:convert';
import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:io';

import 'package:pure_player_lyric/component/foreground.dart';
import 'package:pure_player_lyric/message.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ffi/ffi.dart' as ffi;
import 'package:pure_player_lyric/main.dart' as main_lib show hWnd;
import 'package:win32/win32.dart' as win32;

int? get hWnd => main_lib.hWnd;
set hWnd(int? value) => main_lib.hWnd = value;

const int _setClickThroughMessage = win32.WM_APP + 0x3D1;
const int _setUnlockButtonAlignmentMessage = win32.WM_APP + 0x3D3;
const int _setUnlockButtonColorMessage = win32.WM_APP + 0x3D4;
const MethodChannel _windowChannel = MethodChannel('pure_player_lyric/window');

class DesktopLyricController {
  ValueNotifier<bool> isPlaying = ValueNotifier(false);
  ValueNotifier<bool> isLocked = ValueNotifier(false);
  ValueNotifier<bool> isDarkMode = ValueNotifier(false);
  ValueNotifier<ThemeChangedMessage> theme = ValueNotifier(
    ThemeChangedMessage(
      false,
      Colors.blue.toARGB32(),
      Colors.white.toARGB32(),
      Colors.black.toARGB32(),
    ),
  );
  ValueNotifier<NowPlayingChangedMessage> nowPlaying = ValueNotifier(
    const NowPlayingChangedMessage("", "", ""),
  );
  ValueNotifier<LyricLineChangedMessage> lyricLine = ValueNotifier(
    const LyricLineChangedMessage("", Duration.zero, ""),
  );
  ValueNotifier<List<FullLyricLine>> fullLines = ValueNotifier(const []);
  ValueNotifier<LyricProgressChangedMessage> lyricProgress = ValueNotifier(
    const LyricProgressChangedMessage(0, 0, 1.0, false),
  );
  final LinkedHashMap<int, ValueNotifier<LyricProgressChangedMessage>>
  _lineProgress = LinkedHashMap();
  static const int _maxRetainedLineProgress = 8;
  int? _activeLineId;
  int _activeLineLengthMs = 0;
  bool _windowInteractionActive = false;
  bool _hiddenForVisibility = false;
  Timer? _lineAdvanceTimer;
  double? _absolutePositionMs;
  int _positionSampledAtMs = 0;
  double _playbackRate = 1.0;

  ValueListenable<LyricProgressChangedMessage> progressForLine(int? lineId) {
    if (lineId == null) return lyricProgress;
    return _lineProgress.putIfAbsent(
      lineId,
      () => ValueNotifier(lyricProgress.value),
    );
  }

  void _publishLyricProgress(LyricProgressChangedMessage message) {
    lyricProgress.value = message;
    final lineId = message.lineId;
    if (lineId == null) return;
    final lineProgress = _lineProgress.putIfAbsent(
      lineId,
      () => ValueNotifier(message),
    );
    if (!identical(lineProgress.value, message)) {
      lineProgress.value = message;
    }
    while (_lineProgress.length > _maxRetainedLineProgress) {
      _lineProgress.remove(_lineProgress.keys.first);
    }
  }

  void _handleLyricLineChanged() {
    final line = lyricLine.value;
    final nextLineId = line.lineId;
    final previousLineId = _activeLineId;
    if (previousLineId != null && previousLineId != nextLineId) {
      final lineProgress = _lineProgress[previousLineId];
      if (lineProgress != null) {
        final snapshot = lineProgress.value;
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final transitMs = snapshot.playing
            ? (nowMs - snapshot.sampledAtMs).clamp(0, 60000) *
                  snapshot.playbackRate
            : 0.0;
        final progressMs = (snapshot.progressMs + transitMs)
            .clamp(-60000.0, _activeLineLengthMs.toDouble())
            .round();
        lineProgress.value = LyricProgressChangedMessage(
          progressMs,
          nowMs,
          snapshot.playbackRate,
          false,
          previousLineId,
        );
      }
    }
    _activeLineId = nextLineId;
    _activeLineLengthMs = line.length.inMilliseconds;
  }

  static void initWithArgs(List<String> args) {
    if (args.length != 1) return;

    _instance = DesktopLyricController._();
    try {
      final initArgs = InitArgsMessage.fromJson(json.decode(args.first));
      _instance!.isPlaying.value = initArgs.isPlaying;
      _instance!.nowPlaying.value = NowPlayingChangedMessage(
        initArgs.title,
        initArgs.artist,
        initArgs.album,
      );

      _instance!.isDarkMode.value = initArgs.darkMode;
      _instance!.theme.value = ThemeChangedMessage(
        initArgs.darkMode,
        initArgs.primary,
        initArgs.surfaceContainer,
        initArgs.onSurface,
      );
    } catch (err, stack) {
      stderr.write(err);
      stderr.write(stack);
    }
  }

  static DesktopLyricController? _instance;
  static DesktopLyricController get instance {
    _instance ??= DesktopLyricController._();
    return _instance!;
  }

  final MessageFrameDecoder _stdinDecoder = MessageFrameDecoder();

  Timer? _fullscreenTimer;

  DesktopLyricController._() {
    lyricLine.addListener(_handleLyricLineChanged);
    isPlaying.addListener(syncWindowVisibility);
    isPlaying.addListener(_syncLocalLineAdvance);
    _windowChannel.setMethodCallHandler(_handleWindowMethod);
    stdin.transform(utf8.decoder).listen((event) {
      _stdinDecoder.add(event, _handleMessageLine);
    });
  }

  void _syncLocalLineAdvance() {
    _lineAdvanceTimer?.cancel();
    _lineAdvanceTimer = null;
    if (!isPlaying.value || !textDisplayController.useMultiLineMode) return;
    _advanceLineFromSnapshot();
  }

  double? _estimatedAbsolutePositionMs() {
    final position = _absolutePositionMs;
    if (position == null) return null;
    if (!isPlaying.value) return position;
    final elapsed =
        DateTime.now().millisecondsSinceEpoch - _positionSampledAtMs;
    return position + elapsed.clamp(0, 60000) * _playbackRate;
  }

  void _anchorAbsolutePosition(
    int? lineId,
    int progressMs,
    int sampledAtMs,
    double playbackRate,
  ) {
    if (lineId == null) return;
    final line = fullLines.value.cast<FullLyricLine?>().firstWhere(
      (item) => item?.lineId == lineId,
      orElse: () => null,
    );
    if (line == null) return;
    _absolutePositionMs = line.startMs + progressMs.toDouble();
    _positionSampledAtMs = sampledAtMs;
    _playbackRate = playbackRate;
    _syncLocalLineAdvance();
  }

  void _advanceLineFromSnapshot() {
    _lineAdvanceTimer?.cancel();
    _lineAdvanceTimer = null;
    final position = _estimatedAbsolutePositionMs();
    final lines = fullLines.value;
    if (position == null || lines.isEmpty) return;
    var currentIndex = -1;
    for (var index = 0; index < lines.length; index++) {
      if ((lines[index].switchStartMs ?? lines[index].startMs) > position) {
        break;
      }
      currentIndex = index;
    }
    if (currentIndex >= 0) {
      final line = lines[currentIndex];
      if (line.lineId != lyricLine.value.lineId) {
        FullLyricLine? nextLine;
        for (var index = currentIndex + 1; index < lines.length; index++) {
          final content = lines[index].content;
          if (content != null && content.trim().isNotEmpty) {
            nextLine = lines[index];
            break;
          }
        }
        final progressMs = (position - line.startMs).round().clamp(
          -60000,
          line.lengthMs,
        );
        final message = LyricLineChangedMessage(
          line.content ?? '',
          Duration(milliseconds: line.lengthMs),
          line.translation,
          line.words,
          progressMs,
          nextLine?.content,
          nextLine?.translation,
          null,
          line.romanLyric,
          nextLine?.romanLyric,
          line.words?.isNotEmpty ?? false,
          line.lineId,
          line.highlightDeadlineMs,
          260,
          32,
        );
        _publishLyricProgress(
          LyricProgressChangedMessage(
            progressMs,
            DateTime.now().millisecondsSinceEpoch,
            _playbackRate,
            isPlaying.value,
            line.lineId,
          ),
        );
        lyricLine.value = message;
      }
    }
    if (!isPlaying.value || _playbackRate <= 0) return;
    final nextIndex = currentIndex + 1;
    if (nextIndex >= lines.length) return;
    final nextSwitch =
        lines[nextIndex].switchStartMs ?? lines[nextIndex].startMs;
    final delayMs = ((nextSwitch - position) / _playbackRate).clamp(16, 60000);
    _lineAdvanceTimer = Timer(
      Duration(milliseconds: delayMs.ceil()),
      _advanceLineFromSnapshot,
    );
  }

  static void sendMessage(Message message) {
    stdout.writeln(message.buildMessageJson());
  }

  static void sendControlEvent(ControlEvent event) {
    sendMessage(ControlEventMessage(event));
  }

  Future<void> _handleWindowMethod(MethodCall call) async {
    if (call.method != 'unlock') return;
    setLocked(false);
    sendMessage(const UnlockMessage());
  }

  void setLocked(bool value) {
    isLocked.value = value;
    final windowHwnd = hWnd;
    if (windowHwnd == null || windowHwnd == 0) return;
    syncUnlockButtonStyle();
    win32.PostMessage(windowHwnd, _setClickThroughMessage, value ? 1 : 0, 0);
  }

  void syncUnlockButtonStyle() {
    final windowHwnd = hWnd;
    if (windowHwnd == null || windowHwnd == 0) return;
    final currentTheme = theme.value;
    win32.PostMessage(
      windowHwnd,
      _setUnlockButtonAlignmentMessage,
      textDisplayController.lyricTextAlign.index,
      0,
    );
    win32.PostMessage(
      windowHwnd,
      _setUnlockButtonColorMessage,
      currentTheme.onSurface,
      0,
    );
  }

  void setWindowInteractionActive(bool value) {
    _windowInteractionActive = value;
    if (!value) syncWindowVisibility();
  }

  void syncWindowVisibility() {
    _updateFullscreenTimer();
    final windowHwnd = hWnd;
    if (windowHwnd == null || windowHwnd == 0) return;
    final shouldHide =
        (textDisplayController.hideOnPause && !isPlaying.value) ||
        (textDisplayController.fullscreenHide && _isFullscreenForeground());
    if (shouldHide && _windowInteractionActive) return;
    if (_hiddenForVisibility == shouldHide) return;
    win32.ShowWindow(windowHwnd, shouldHide ? win32.SW_HIDE : win32.SW_SHOWNA);
    _hiddenForVisibility = shouldHide;
  }

  /// 全屏状态没有事件通知，只在开关开启时轮询；关闭时顺带由
  /// syncWindowVisibility 按剩余条件恢复显示
  void _updateFullscreenTimer() {
    if (!textDisplayController.fullscreenHide) {
      _fullscreenTimer?.cancel();
      _fullscreenTimer = null;
      return;
    }
    _fullscreenTimer ??= Timer.periodic(
      const Duration(seconds: 1),
      (_) => syncWindowVisibility(),
    );
  }

  bool _isFullscreenForeground() {
    final foreground = win32.GetForegroundWindow();
    if (foreground == 0 || foreground == hWnd) return false;
    final windowRect = ffi.calloc<win32.RECT>();
    if (win32.GetWindowRect(foreground, windowRect) == 0) {
      ffi.calloc.free(windowRect);
      return false;
    }
    final monitor = win32.MonitorFromWindow(
      foreground,
      win32.MONITOR_DEFAULTTONEAREST,
    );
    final monitorInfo = ffi.calloc<win32.MONITORINFO>();
    monitorInfo.ref.cbSize = sizeOf<win32.MONITORINFO>();
    final hasMonitor =
        monitor != 0 && win32.GetMonitorInfo(monitor, monitorInfo) != 0;
    final isFullscreen =
        hasMonitor &&
        windowRect.ref.left == monitorInfo.ref.rcMonitor.left &&
        windowRect.ref.top == monitorInfo.ref.rcMonitor.top &&
        windowRect.ref.right == monitorInfo.ref.rcMonitor.right &&
        windowRect.ref.bottom == monitorInfo.ref.rcMonitor.bottom;
    ffi.calloc.free(windowRect);
    ffi.calloc.free(monitorInfo);
    return isFullscreen;
  }

  void _handleMessageLine(String raw) {
    try {
      final Map messageMap = json.decode(raw);
      final String type = messageMap["type"];
      final content = messageMap["message"] as Map<String, dynamic>;

      if (type == getMessageTypeName<PlayerStateChangedMessage>()) {
        final playerState = PlayerStateChangedMessage.fromJson(content);
        isPlaying.value = playerState.playing;
      } else if (type == getMessageTypeName<NowPlayingChangedMessage>()) {
        final nowPlayingMessage = NowPlayingChangedMessage.fromJson(content);
        nowPlaying.value = nowPlayingMessage;
        _lineAdvanceTimer?.cancel();
        _lineAdvanceTimer = null;
        _absolutePositionMs = null;
        fullLines.value = const [];
        _publishLyricProgress(
          LyricProgressChangedMessage(
            0,
            DateTime.now().millisecondsSinceEpoch,
            1.0,
            isPlaying.value,
          ),
        );
        lyricLine.value = const LyricLineChangedMessage("", Duration.zero);
      } else if (type == getMessageTypeName<FullLyricChangedMessage>()) {
        final fullLyricMessage = FullLyricChangedMessage.fromJson(content);
        fullLines.value = List.unmodifiable(fullLyricMessage.lines);
        final progress = lyricProgress.value;
        _anchorAbsolutePosition(
          lyricLine.value.lineId,
          progress.progressMs,
          progress.sampledAtMs,
          progress.playbackRate,
        );
      } else if (type == getMessageTypeName<LyricLineChangedMessage>()) {
        final lyricLineMessage = LyricLineChangedMessage.fromJson(content);
        final currentProgress = lyricProgress.value;
        final sampledAtMs = DateTime.now().millisecondsSinceEpoch;
        final snapshotControlsLine =
            textDisplayController.useMultiLineMode &&
            fullLines.value.isNotEmpty;
        _publishLyricProgress(
          LyricProgressChangedMessage(
            lyricLineMessage.progressMs ?? 0,
            sampledAtMs,
            currentProgress.playbackRate,
            isPlaying.value,
            lyricLineMessage.lineId,
          ),
        );
        if (!snapshotControlsLine) lyricLine.value = lyricLineMessage;
        _anchorAbsolutePosition(
          lyricLineMessage.lineId,
          lyricLineMessage.progressMs ?? 0,
          sampledAtMs,
          currentProgress.playbackRate,
        );
      } else if (type == getMessageTypeName<LyricProgressChangedMessage>()) {
        final progressMessage = LyricProgressChangedMessage.fromJson(content);
        final snapshotControlsLine =
            textDisplayController.useMultiLineMode &&
            fullLines.value.isNotEmpty;
        if (!snapshotControlsLine &&
            progressMessage.lineId != null &&
            progressMessage.lineId != lyricLine.value.lineId) {
          return;
        }
        _publishLyricProgress(progressMessage);
        _anchorAbsolutePosition(
          progressMessage.lineId,
          progressMessage.progressMs,
          progressMessage.sampledAtMs,
          progressMessage.playbackRate,
        );
      } else if (type == getMessageTypeName<ThemeChangedMessage>()) {
        final themeMessage = ThemeChangedMessage.fromJson(content);
        isDarkMode.value = themeMessage.darkMode;
        theme.value = themeMessage;
        syncUnlockButtonStyle();
      } else if (type == getMessageTypeName<DesktopLyricConfigMessage>()) {
        final config = DesktopLyricConfigMessage.fromJson(content);
        textDisplayController.applyConfig(config.toJson());
        _syncLocalLineAdvance();
        syncUnlockButtonStyle();
        syncWindowVisibility();
      } else if (type == getMessageTypeName<UnlockMessage>()) {
        setLocked(false);
      }
    } catch (err, stack) {
      stderr.write(err);
      stderr.write(stack);
    }
  }
}
