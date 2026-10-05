import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:pure_player_lyric/component/foreground.dart';
import 'package:pure_player_lyric/component/word_lyric_text.dart';
import 'package:pure_player_lyric/desktop_lyric_controller.dart';
import 'package:pure_player_lyric/message.dart';

const _lineAWords = <LyricWord>[
  LyricWord(0, 700, 'Flowing '),
  LyricWord(700, 800, 'colors '),
  LyricWord(1500, 900, 'follow '),
  LyricWord(2400, 750, 'every '),
  LyricWord(3150, 1200, 'heartbeat'),
];

const _lineBWords = <LyricWord>[
  LyricWord(0, 650, 'A🎵 '),
  LyricWord(650, 900, 'family 👨‍👩‍👧‍👦 '),
  LyricWord(1550, 850, 'and é '),
  LyricWord(2400, 1200, 'shaped text'),
];

const _lineAText = '流动的色彩跟随每一次心跳';
const _lineBText = 'A🎵 family 👨‍👩‍👧‍👦 and é shaped text';

LyricLineChangedMessage _makeLine(int id) {
  final useA = id.isOdd;
  return LyricLineChangedMessage(
    useA ? _lineAText : _lineBText,
    const Duration(seconds: 8),
    null,
    useA ? _lineAWords : _lineBWords,
    0,
    null,
    null,
    null,
    null,
    null,
    true,
    id,
  );
}

List<FullLyricLine> _makeSnapshot({int count = 32}) {
  return List<FullLyricLine>.generate(count, (index) {
    final id = index + 1;
    final useA = id.isOdd;
    return FullLyricLine(
      id,
      useA ? _lineAText : _lineBText,
      null,
      null,
      index * 8000,
      8000,
      useA ? _lineAWords : _lineBWords,
    );
  });
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _BenchmarkApp());
}

class _BenchmarkApp extends StatefulWidget {
  const _BenchmarkApp();

  @override
  State<_BenchmarkApp> createState() => _BenchmarkAppState();
}

class _BenchmarkAppState extends State<_BenchmarkApp> {
  final _desktopController = DesktopLyricController.instance;
  final _isPlaying = ValueNotifier(true);
  final _progress = ValueNotifier(
    LyricProgressChangedMessage(
      0,
      DateTime.now().millisecondsSinceEpoch,
      1.0,
      true,
      1,
    ),
  );
  final _timings = <FrameTiming>[];
  late LyricLineChangedMessage _currentLine;
  bool _showFullDesktopUi = false;
  bool _disposed = false;
  double _viewportHeight = 180;

  @override
  void initState() {
    super.initState();
    _currentLine = _makeLine(1);
    SchedulerBinding.instance.addTimingsCallback(_collectTimings);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runBenchmark());
    });
  }

  void _collectTimings(List<FrameTiming> values) => _timings.addAll(values);

  Future<void> _runBenchmark() async {
    try {
      await Future<void>.delayed(const Duration(seconds: 2));
      final reports = <Map<String, Object?>>[];
      reports.add(
        await _measurePhase('word_active', const Duration(seconds: 12)),
      );

      _setPlaying(false);
      reports.add(
        await _measurePhase('word_paused', const Duration(seconds: 3)),
      );

      _setPlaying(true);
      reports.add(await _measureLineSwitch('word_line_switch', 16, (index) {
        _setLine(index.isEven ? 1 : 2);
      }));

      setState(() => _showFullDesktopUi = true);
      _setLine(1);
      await Future<void>.delayed(const Duration(seconds: 1));
      reports.add(
        await _measurePhase('desktop_active', const Duration(seconds: 12)),
      );

      _setPlaying(false);
      reports.add(
        await _measurePhase('desktop_paused', const Duration(seconds: 3)),
      );

      _setPlaying(true);
      reports.add(await _measureLineSwitch('desktop_line_switch', 16, (index) {
        _setLine(index.isEven ? 1 : 2);
      }));

      // 不 notifyListeners，避免把多行开关写进用户设置
      textDisplayController.useMultiLineMode = true;
      textDisplayController.showDoubleLine = false;
      _desktopController.fullLines.value = _makeSnapshot();
      setState(() => _viewportHeight = 480);
      _setLine(1);
      await Future<void>.delayed(const Duration(seconds: 1));
      reports.add(
        await _measurePhase('multiline_active', const Duration(seconds: 12)),
      );

      reports.add(await _measurePauseHitch('multiline_pause_hitch'));
      reports.add(
        await _measurePhase('multiline_paused', const Duration(seconds: 3)),
      );

      _setPlaying(true);
      reports.add(await _measureLineSwitch('multiline_line_switch', 16, (index) {
        _setLine(index + 1);
      }));

      debugPrint('DESKTOP_LYRIC_REPORT ${jsonEncode(reports)}');
    } catch (error, stackTrace) {
      debugPrint('DESKTOP_LYRIC_ERROR $error\n$stackTrace');
      exitCode = 1;
    } finally {
      _disposed = true;
      SchedulerBinding.instance.removeTimingsCallback(_collectTimings);
      _desktopController.isPlaying.value = false;
      _isPlaying.dispose();
      _progress.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      exit(exitCode);
    }
  }

  Future<Map<String, Object?>> _measurePhase(
    String name,
    Duration duration,
  ) async {
    debugPrint('DESKTOP_LYRIC_PHASE $name');
    await SchedulerBinding.instance.endOfFrame;
    _timings.clear();
    final rssBefore = ProcessInfo.currentRss;
    await Future<void>.delayed(duration);
    await SchedulerBinding.instance.endOfFrame;
    return {
      'phase': name,
      'frames': _timings.length,
      'rssBeforeMb': _toMb(rssBefore),
      'rssAfterMb': _toMb(ProcessInfo.currentRss),
      ..._frameReport(),
    };
  }

  Future<Map<String, Object?>> _measurePauseHitch(String name) async {
    debugPrint('DESKTOP_LYRIC_PHASE $name');
    await SchedulerBinding.instance.endOfFrame;
    _timings.clear();
    final rssBefore = ProcessInfo.currentRss;
    _setPlaying(false);
    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await SchedulerBinding.instance.endOfFrame;
    return {
      'phase': name,
      'frames': _timings.length,
      'rssBeforeMb': _toMb(rssBefore),
      'rssAfterMb': _toMb(ProcessInfo.currentRss),
      ..._frameReport(),
    };
  }

  Future<Map<String, Object?>> _measureLineSwitch(
    String name,
    int count,
    void Function(int index) switchLine,
  ) async {
    debugPrint('DESKTOP_LYRIC_PHASE $name');
    await SchedulerBinding.instance.endOfFrame;
    _timings.clear();
    final rssBefore = ProcessInfo.currentRss;
    final switchClock = Stopwatch()..start();
    for (var index = 0; index < count; index++) {
      switchLine(index);
      await Future<void>.delayed(const Duration(milliseconds: 450));
    }
    switchClock.stop();
    return {
      'phase': name,
      'frames': _timings.length,
      'rssBeforeMb': _toMb(rssBefore),
      'rssAfterMb': _toMb(ProcessInfo.currentRss),
      'wallMs': switchClock.elapsedMilliseconds,
      ..._frameReport(),
    };
  }

  Map<String, Object?> _frameReport() {
    final buildMs = _timings
        .map((timing) => timing.buildDuration.inMicroseconds / 1000)
        .toList(growable: false);
    final rasterMs = _timings
        .map((timing) => timing.rasterDuration.inMicroseconds / 1000)
        .toList(growable: false);
    final totalMs = _timings
        .map((timing) => timing.totalSpan.inMicroseconds / 1000)
        .toList(growable: false);
    return {
      'buildP95Ms': _percentile(buildMs, 0.95),
      'rasterP95Ms': _percentile(rasterMs, 0.95),
      'totalP95Ms': _percentile(totalMs, 0.95),
      'maxTotalMs': totalMs.isEmpty ? 0 : totalMs.reduce((a, b) => a > b ? a : b),
      'maxBuildMs': buildMs.isEmpty ? 0 : buildMs.reduce((a, b) => a > b ? a : b),
      'maxRasterMs': rasterMs.isEmpty ? 0 : rasterMs.reduce((a, b) => a > b ? a : b),
      'over16ms': totalMs.where((value) => value > 16.67).length,
      'over32ms': totalMs.where((value) => value > 32).length,
    };
  }

  void _setPlaying(bool value) {
    if (_disposed) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    _isPlaying.value = value;
    _desktopController.isPlaying.value = value;
    _progress.value = LyricProgressChangedMessage(
      _progress.value.progressMs,
      now,
      1.0,
      value,
      _progress.value.lineId,
    );
    final lineId = _currentLine.lineId;
    if (lineId != null) {
      final desktopProgress =
          _desktopController.progressForLine(lineId)
              as ValueNotifier<LyricProgressChangedMessage>;
      desktopProgress.value = LyricProgressChangedMessage(
        desktopProgress.value.progressMs,
        now,
        1.0,
        value,
        lineId,
      );
    }
  }

  void _setLine(int id) {
    if (_disposed) return;
    final nextLine = _makeLine(id);
    setState(() => _currentLine = nextLine);
    final progress = LyricProgressChangedMessage(
      0,
      DateTime.now().millisecondsSinceEpoch,
      1.0,
      true,
      id,
    );
    _progress.value = progress;
    final desktopProgress =
        _desktopController.progressForLine(id)
            as ValueNotifier<LyricProgressChangedMessage>;
    desktopProgress.value = progress;
    _desktopController.lyricLine.value = nextLine;
  }

  static double _toMb(int bytes) => bytes / (1024 * 1024);

  static double _percentile(List<double> values, double percentile) {
    if (values.isEmpty) return 0;
    final sorted = List<double>.from(values)..sort();
    final index = (sorted.length * percentile).ceil() - 1;
    return sorted[index.clamp(0, sorted.length - 1)];
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableProvider.value(
      value: _desktopController.theme,
      child: MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Center(
            child: RepaintBoundary(
              child: SizedBox(
                width: 1000,
                height: _viewportHeight,
                child: _showFullDesktopUi
                    ? const DesktopLyricForeground(isHovering: false)
                    : Center(
                        child: WordLyricText(
                          line: _currentLine,
                          color: Colors.white,
                          playedColor: Colors.lightBlueAccent,
                          fontSize: 42,
                          fontWeight: 700,
                          textAlign: TextAlign.center,
                          isPlaying: _isPlaying,
                          progress: _progress,
                          enableOutline: true,
                          outlineColor: Colors.black,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
