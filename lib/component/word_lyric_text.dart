import 'package:pure_player_lyric/component/foreground.dart';
import 'package:pure_player_lyric/message.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

double desktopLyricHighlightTimeMs({
  required double progressMs,
  required double lastWordEndMs,
  required double? deadlineMs,
  double catchUpDurationMs = 260.0,
  double finishLeadMs = 32.0,
}) {
  if (deadlineMs == null || deadlineMs <= 0) return progressMs;
  if (lastWordEndMs <= deadlineMs - finishLeadMs ||
      progressMs < deadlineMs - catchUpDurationMs) {
    return progressMs;
  }
  final catchUpStart = deadlineMs - catchUpDurationMs;
  final catchUpEnd = deadlineMs - finishLeadMs;
  final t = ((progressMs - catchUpStart) / (catchUpEnd - catchUpStart)).clamp(
    0.0,
    1.0,
  );
  final eased = Curves.easeIn.transform(t);
  final targetEnd = lastWordEndMs > deadlineMs ? lastWordEndMs : deadlineMs;
  return progressMs + (targetEnd - progressMs) * eased;
}

Color applyLyricOpacity(Color color, double alpha) {
  return color.withValues(alpha: color.a * alpha);
}

class WordLyricText extends StatefulWidget {
  final LyricLineChangedMessage line;
  final Color color;
  final Color playedColor;
  final double fontSize;
  final int fontWeight;
  final TextAlign textAlign;
  final ValueListenable<bool> isPlaying;
  final ValueListenable<LyricProgressChangedMessage> progress;
  final double alpha;
  final bool enableOutline;
  final Color outlineColor;

  const WordLyricText({
    super.key,
    required this.line,
    required this.color,
    required this.playedColor,
    required this.fontSize,
    required this.fontWeight,
    required this.textAlign,
    required this.isPlaying,
    required this.progress,
    this.alpha = 1.0,
    this.enableOutline = true,
    this.outlineColor = Colors.black,
  });

  @override
  State<WordLyricText> createState() => _WordLyricTextState();
}

class _WordLyricTextState extends State<WordLyricText>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Stopwatch _stopwatch = Stopwatch();
  final ValueNotifier<int> _progressMs = ValueNotifier(0);

  _WordLyricRenderCache? _renderCache;
  double _baseProgressMs = 0;
  double _playbackRate = 1.0;

  late VoidCallback _playingListener;
  late VoidCallback _progressListener;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _playingListener = _syncPlaying;
    _progressListener = _applyProgressSnapshot;
    widget.isPlaying.addListener(_playingListener);
    widget.progress.addListener(_progressListener);
    _resetFromLine();
    _syncPlaying();
  }

  @override
  void didUpdateWidget(covariant WordLyricText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPlaying != widget.isPlaying) {
      oldWidget.isPlaying.removeListener(_playingListener);
      _playingListener = _syncPlaying;
      widget.isPlaying.addListener(_playingListener);
    }
    if (oldWidget.progress != widget.progress) {
      oldWidget.progress.removeListener(_progressListener);
      _progressListener = _applyProgressSnapshot;
      widget.progress.addListener(_progressListener);
    }

    final contentChanged =
        oldWidget.line.content != widget.line.content ||
        oldWidget.line.translation != widget.line.translation ||
        oldWidget.line.romanLyric != widget.line.romanLyric ||
        oldWidget.line.length != widget.line.length ||
        !_sameWords(oldWidget.line.words, widget.line.words);
    final propsChanged =
        oldWidget.fontSize != widget.fontSize ||
        oldWidget.fontWeight != widget.fontWeight ||
        oldWidget.color != widget.color ||
        oldWidget.playedColor != widget.playedColor ||
        oldWidget.alpha != widget.alpha ||
        oldWidget.enableOutline != widget.enableOutline ||
        oldWidget.outlineColor != widget.outlineColor;

    if (contentChanged) {
      _resetFromLine();
      _syncPlaying();
    } else if (propsChanged) {
      _rebuildLayout();
    } else if (oldWidget.progress != widget.progress) {
      _applyProgressSnapshot();
    }
  }

  bool _sameWords(List<LyricWord>? a, List<LyricWord>? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null || a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].startMs != b[i].startMs ||
          a[i].lengthMs != b[i].lengthMs ||
          a[i].content != b[i].content) {
        return false;
      }
    }
    return true;
  }

  void _buildLayout() {
    final words = widget.line.words ?? const [];
    final previous = _renderCache;
    _renderCache = _WordLyricRenderCache.create(
      words: words,
      fontSize: widget.fontSize,
      fontWeight: lyricFontWeightFromInt(widget.fontWeight),
      textColor: applyLyricOpacity(widget.color, widget.alpha),
      playedColor: widget.playedColor.withValues(alpha: widget.alpha),
      outlineColor: applyLyricOpacity(widget.outlineColor, widget.alpha),
      enableOutline: widget.enableOutline,
    );
    previous?.dispose();
  }

  void _resetFromLine() {
    _buildLayout();
    _applyProgressSnapshot();
  }

  void _rebuildLayout() {
    _buildLayout();
  }

  double _currentProgressMs() {
    final elapsed = _stopwatch.elapsedMilliseconds * _playbackRate;
    return _baseProgressMs + elapsed;
  }

  bool _matchesLine(LyricProgressChangedMessage snapshot) {
    final lineId = widget.line.lineId;
    return lineId == null ||
        snapshot.lineId == null ||
        snapshot.lineId == lineId;
  }

  int _highlightProgressMs(double progressMs) {
    final words = widget.line.words;
    if (words == null || words.isEmpty) return progressMs.round();
    final lastWord = words.last;
    return desktopLyricHighlightTimeMs(
      progressMs: progressMs,
      lastWordEndMs: (lastWord.startMs + lastWord.lengthMs).toDouble(),
      deadlineMs: widget.line.highlightDeadlineMs?.toDouble(),
      catchUpDurationMs:
          widget.line.highlightCatchUpDurationMs?.toDouble() ?? 260.0,
      finishLeadMs: widget.line.highlightFinishLeadMs?.toDouble() ?? 32.0,
    ).round();
  }

  void _applyProgressSnapshot() {
    final snapshot = widget.progress.value;
    if (!_matchesLine(snapshot)) {
      if (_stopwatch.isRunning) _stopwatch.stop();
      if (_ticker.isActive) _ticker.stop();
      return;
    }
    if (!snapshot.playing && _stopwatch.isRunning) {
      _stopwatch.stop();
      _stopwatch.reset();
    }
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final transitMs = snapshot.playing
        ? (nowMs - snapshot.sampledAtMs).clamp(0, 60000) * snapshot.playbackRate
        : 0.0;
    final maxProgress = widget.line.length.inMilliseconds.toDouble();
    final target = (snapshot.progressMs + transitMs)
        .clamp(-60000.0, maxProgress)
        .toDouble();
    _stopwatch.reset();
    _baseProgressMs = target;
    _playbackRate = snapshot.playbackRate > 0 ? snapshot.playbackRate : 1.0;
    _progressMs.value = _highlightProgressMs(target);
    _syncPlaying();
  }

  void _syncPlaying() {
    final progress = widget.progress.value;
    final playing =
        widget.isPlaying.value && progress.playing && _matchesLine(progress);
    if (playing) {
      if (!_ticker.isActive) _ticker.start();
      if (!_stopwatch.isRunning) _stopwatch.start();
    } else {
      if (_stopwatch.isRunning) {
        _stopwatch.stop();
        _baseProgressMs = _currentProgressMs();
        _stopwatch.reset();
        _progressMs.value = _highlightProgressMs(_baseProgressMs);
      }
      if (_ticker.isActive) _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    if (!_stopwatch.isRunning) return;
    final rawProgress = _currentProgressMs()
        .clamp(-60000.0, widget.line.length.inMilliseconds.toDouble())
        .toDouble();
    final next = _highlightProgressMs(rawProgress);
    if (next == _progressMs.value) return;
    _progressMs.value = next;
  }

  @override
  void dispose() {
    widget.isPlaying.removeListener(_playingListener);
    widget.progress.removeListener(_progressListener);
    _ticker.dispose();
    _stopwatch.stop();
    _renderCache?.dispose();
    _progressMs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cache = _renderCache;
    if (cache == null || cache.segments.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width: cache.totalWidth,
      height: cache.totalHeight,
      child: CustomPaint(
        painter: _WordLyricPainter(
          cache: cache,
          progress: _progressMs,
          textAlign: widget.textAlign,
        ),
      ),
    );
  }
}

class _WordSegment {
  final double x;
  final double width;
  final int wordStartMs;
  final int wordLengthMs;

  const _WordSegment({
    required this.x,
    required this.width,
    required this.wordStartMs,
    required this.wordLengthMs,
  });
}

class _WordLyricRenderCache {
  _WordLyricRenderCache({
    required this.segments,
    required this.dimFillPainters,
    required this.brightFillPainters,
    required this.strokePainters,
    required this.totalWidth,
    required this.totalHeight,
    required this.enableOutline,
  });

  final List<_WordSegment> segments;
  final List<TextPainter> dimFillPainters;
  final List<TextPainter> brightFillPainters;
  final List<TextPainter> strokePainters;
  final double totalWidth;
  final double totalHeight;
  final bool enableOutline;

  static TextPainter _layoutWord(String content, TextStyle style) {
    return TextPainter(
      text: TextSpan(text: content, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
  }

  static _WordLyricRenderCache create({
    required List<LyricWord> words,
    required double fontSize,
    required FontWeight fontWeight,
    required Color textColor,
    required Color playedColor,
    required Color outlineColor,
    required bool enableOutline,
  }) {
    final dimFillStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: textColor,
    );
    final brightFillStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: playedColor,
    );
    final strokeStyle = TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lyricOutlineWidth(fontSize)
        ..color = outlineColor,
    );
    final segments = <_WordSegment>[];
    final dimFillPainters = <TextPainter>[];
    final brightFillPainters = <TextPainter>[];
    final strokePainters = <TextPainter>[];
    final gap = fontSize * 0.12;
    var x = 0.0;
    var maxHeight = 0.0;

    for (final word in words) {
      final dimPainter = _layoutWord(word.content, dimFillStyle);
      final brightPainter = _layoutWord(word.content, brightFillStyle);
      final strokePainter = enableOutline
          ? _layoutWord(word.content, strokeStyle)
          : null;
      final width = dimPainter.width;
      if (dimPainter.height > maxHeight) maxHeight = dimPainter.height;
      segments.add(
        _WordSegment(
          x: x,
          width: width,
          wordStartMs: word.startMs,
          wordLengthMs: word.lengthMs,
        ),
      );
      dimFillPainters.add(dimPainter);
      brightFillPainters.add(brightPainter);
      if (strokePainter != null) strokePainters.add(strokePainter);
      x += width + gap;
    }

    return _WordLyricRenderCache(
      segments: segments,
      dimFillPainters: dimFillPainters,
      brightFillPainters: brightFillPainters,
      strokePainters: strokePainters,
      totalWidth: x,
      totalHeight: maxHeight,
      enableOutline: enableOutline,
    );
  }

  void paintLayer(Canvas canvas, double startX, {required bool bright}) {
    final fills = bright ? brightFillPainters : dimFillPainters;
    for (var index = 0; index < segments.length; index++) {
      final offset = Offset(startX + segments[index].x, 0);
      if (enableOutline) strokePainters[index].paint(canvas, offset);
      fills[index].paint(canvas, offset);
    }
  }

  void dispose() {
    for (final painter in dimFillPainters) {
      painter.dispose();
    }
    for (final painter in brightFillPainters) {
      painter.dispose();
    }
    for (final painter in strokePainters) {
      painter.dispose();
    }
  }
}

class _WordLyricPainter extends CustomPainter {
  final _WordLyricRenderCache cache;
  final ValueListenable<int> progress;
  final TextAlign textAlign;

  _WordLyricPainter({
    required this.cache,
    required this.progress,
    required this.textAlign,
  }) : super(repaint: progress);

  int get progressMs => progress.value;

  double _wordProgress(int startMs, int lengthMs) {
    if (progressMs < startMs) return 0.0;
    final endMs = startMs + lengthMs;
    if (progressMs >= endMs) return 1.0;
    if (lengthMs <= 0) return 1.0;
    return (progressMs - startMs) / lengthMs;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final segments = cache.segments;
    if (segments.isEmpty) return;

    final startX = switch (textAlign) {
      TextAlign.left || TextAlign.start => 0.0,
      TextAlign.center => (size.width - cache.totalWidth) / 2,
      TextAlign.right || TextAlign.end => size.width - cache.totalWidth,
      _ => 0.0,
    };

    double sweepX = startX;
    for (final segment in segments) {
      final wp = _wordProgress(segment.wordStartMs, segment.wordLengthMs);
      if (wp >= 1.0) {
        sweepX = startX + segment.x + segment.width;
      } else if (wp > 0) {
        sweepX = startX + segment.x + segment.width * wp;
        break;
      } else {
        break;
      }
    }

    cache.paintLayer(canvas, startX, bright: false);
    if (sweepX > startX) {
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(startX, -1, sweepX + 1, size.height + 1));
      cache.paintLayer(canvas, startX, bright: true);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _WordLyricPainter oldDelegate) {
    return !identical(oldDelegate.cache, cache) ||
        oldDelegate.textAlign != textAlign ||
        oldDelegate.progress != progress;
  }
}
