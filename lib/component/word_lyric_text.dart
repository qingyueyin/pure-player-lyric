import 'dart:math' as math;

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
  final bool vertical;
  final double? maxWidth;

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
    this.vertical = false,
    this.maxWidth,
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
        oldWidget.outlineColor != widget.outlineColor ||
        oldWidget.vertical != widget.vertical ||
        oldWidget.maxWidth != widget.maxWidth ||
        oldWidget.textAlign != widget.textAlign;

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
      vertical: widget.vertical,
      maxWidth: widget.vertical ? null : widget.maxWidth,
      textAlign: widget.textAlign,
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
      width: widget.vertical
          ? cache.totalWidth
          : widget.maxWidth ?? cache.totalWidth,
      height: cache.totalHeight,
      child: CustomPaint(
        painter: _WordLyricPainter(
          cache: cache,
          progress: _progressMs,
          textAlign: widget.textAlign,
          vertical: widget.vertical,
        ),
      ),
    );
  }
}

class _WordSegment {
  final double x;
  final double y;
  final double width;
  final double height;
  final int wordStartMs;
  final int wordLengthMs;
  final List<Rect> boxes;

  const _WordSegment({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.wordStartMs,
    required this.wordLengthMs,
    this.boxes = const [],
  });
}

class _CharLayout {
  final double width;
  final double height;
  final bool rotate;
  final TextPainter dimFillPainter;
  final TextPainter brightFillPainter;
  final TextPainter? strokePainter;

  const _CharLayout({
    required this.width,
    required this.height,
    required this.rotate,
    required this.dimFillPainter,
    required this.brightFillPainter,
    required this.strokePainter,
  });

  void dispose() {
    dimFillPainter.dispose();
    brightFillPainter.dispose();
    strokePainter?.dispose();
  }
}

final RegExp _alphanumericChar = RegExp(
  r'''^[A-Za-z0-9 !"'?.,:;()\[\]\-《》「」（）：/“”]+$''',
);

class _WordLyricRenderCache {
  _WordLyricRenderCache({
    required this.segments,
    required this.dimFillPainter,
    required this.brightFillPainter,
    required this.strokePainter,
    required this.totalWidth,
    required this.totalHeight,
    this.vertical = false,
    this.charLayouts = const [],
  });

  final List<_WordSegment> segments;
  final TextPainter dimFillPainter;
  final TextPainter brightFillPainter;
  final TextPainter? strokePainter;
  final double totalWidth;
  final double totalHeight;
  final bool vertical;
  final List<_CharLayout> charLayouts;

  static TextPainter _layoutLine(
    String content,
    TextStyle style, {
    double? maxWidth,
    TextAlign textAlign = TextAlign.left,
  }) {
    return TextPainter(
      text: TextSpan(text: content, style: style),
      textDirection: TextDirection.ltr,
      textAlign: textAlign,
      maxLines: maxWidth == null ? 1 : null,
    )..layout(maxWidth: maxWidth ?? double.infinity);
  }

  static _WordLyricRenderCache create({
    required List<LyricWord> words,
    required double fontSize,
    required FontWeight fontWeight,
    required Color textColor,
    required Color playedColor,
    required Color outlineColor,
    required bool enableOutline,
    required bool vertical,
    required double? maxWidth,
    required TextAlign textAlign,
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
    if (!vertical) {
      final buffer = StringBuffer();
      final wordRanges = <({int start, int end, LyricWord word})>[];
      for (final word in words) {
        final start = buffer.length;
        buffer.write(word.content);
        wordRanges.add((start: start, end: buffer.length, word: word));
      }
      final content = buffer.toString();
      final dimFillPainter = _layoutLine(
        content,
        dimFillStyle,
        maxWidth: maxWidth,
        textAlign: textAlign,
      );
      final brightFillPainter = _layoutLine(
        content,
        brightFillStyle,
        maxWidth: maxWidth,
        textAlign: textAlign,
      );
      final strokePainter = enableOutline
          ? _layoutLine(
              content,
              strokeStyle,
              maxWidth: maxWidth,
              textAlign: textAlign,
            )
          : null;
      final segments = <_WordSegment>[];
      var previousEnd = 0.0;
      for (final range in wordRanges) {
        final boxes = dimFillPainter.getBoxesForSelection(
          TextSelection(baseOffset: range.start, extentOffset: range.end),
        );
        var left = previousEnd;
        var right = previousEnd;
        if (boxes.isNotEmpty) {
          left = boxes.first.left;
          right = boxes.first.right;
          for (final box in boxes.skip(1)) {
            if (box.left < left) left = box.left;
            if (box.right > right) right = box.right;
          }
        }
        segments.add(
          _WordSegment(
            x: left,
            y: 0,
            width: right - left,
            height: dimFillPainter.height,
            wordStartMs: range.word.startMs,
            wordLengthMs: range.word.lengthMs,
            boxes: boxes
                .map(
                  (box) =>
                      Rect.fromLTRB(box.left, box.top, box.right, box.bottom),
                )
                .toList(growable: false),
          ),
        );
        previousEnd = right;
      }

      return _WordLyricRenderCache(
        segments: segments,
        dimFillPainter: dimFillPainter,
        brightFillPainter: brightFillPainter,
        strokePainter: strokePainter,
        totalWidth: dimFillPainter.width,
        totalHeight: dimFillPainter.height,
      );
    }

    final charLayouts = <_CharLayout>[];
    final segments = <_WordSegment>[];
    var totalHeight = 0.0;
    var totalWidth = 0.0;
    for (final word in words) {
      final wordStartY = totalHeight;
      var wordHeight = 0.0;
      var wordWidth = 0.0;
      for (final char in word.content.split('')) {
        final dimFillPainter = _layoutLine(char, dimFillStyle);
        final brightFillPainter = _layoutLine(char, brightFillStyle);
        final strokePainter = enableOutline
            ? _layoutLine(char, strokeStyle)
            : null;
        final rotate = _alphanumericChar.hasMatch(char);
        final charWidth = rotate ? dimFillPainter.height : dimFillPainter.width;
        final charHeight = rotate
            ? dimFillPainter.width
            : dimFillPainter.height;
        charLayouts.add(
          _CharLayout(
            width: charWidth,
            height: charHeight,
            rotate: rotate,
            dimFillPainter: dimFillPainter,
            brightFillPainter: brightFillPainter,
            strokePainter: strokePainter,
          ),
        );
        wordHeight += charHeight;
        if (charWidth > wordWidth) wordWidth = charWidth;
      }
      segments.add(
        _WordSegment(
          x: 0,
          y: wordStartY,
          width: wordWidth,
          height: wordHeight,
          wordStartMs: word.startMs,
          wordLengthMs: word.lengthMs,
        ),
      );
      totalHeight += wordHeight;
      if (wordWidth > totalWidth) totalWidth = wordWidth;
    }

    return _WordLyricRenderCache(
      segments: segments,
      dimFillPainter: _layoutLine('', dimFillStyle),
      brightFillPainter: _layoutLine('', brightFillStyle),
      strokePainter: null,
      totalWidth: totalWidth,
      totalHeight: totalHeight,
      vertical: true,
      charLayouts: charLayouts,
    );
  }

  void paintLayer(Canvas canvas, double startX, {required bool bright}) {
    if (!vertical) {
      final offset = Offset(startX, 0);
      strokePainter?.paint(canvas, offset);
      (bright ? brightFillPainter : dimFillPainter).paint(canvas, offset);
      return;
    }
    var y = 0.0;
    for (final char in charLayouts) {
      final x = startX + (totalWidth - char.width) / 2;
      canvas.save();
      if (char.rotate) {
        canvas.translate(x + char.width, y);
        canvas.rotate(3.141592653589793 / 2);
      } else {
        canvas.translate(x, y);
      }
      char.strokePainter?.paint(canvas, Offset.zero);
      (bright ? char.brightFillPainter : char.dimFillPainter).paint(
        canvas,
        Offset.zero,
      );
      canvas.restore();
      y += char.height;
    }
  }

  void dispose() {
    if (!vertical) {
      dimFillPainter.dispose();
      brightFillPainter.dispose();
      strokePainter?.dispose();
      return;
    }
    for (final char in charLayouts) {
      char.dispose();
    }
  }
}

class _WordLyricPainter extends CustomPainter {
  final _WordLyricRenderCache cache;
  final ValueListenable<int> progress;
  final TextAlign textAlign;
  final bool vertical;

  _WordLyricPainter({
    required this.cache,
    required this.progress,
    required this.textAlign,
    required this.vertical,
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

    if (vertical) {
      final startY = switch (textAlign) {
        TextAlign.left || TextAlign.start => 0.0,
        TextAlign.center => (size.height - cache.totalHeight) / 2,
        TextAlign.right || TextAlign.end => size.height - cache.totalHeight,
        _ => 0.0,
      };
      final centerX = (size.width - cache.totalWidth) / 2;
      double sweepY = startY;
      for (final segment in segments) {
        final wp = _wordProgress(segment.wordStartMs, segment.wordLengthMs);
        if (wp >= 1.0) {
          sweepY = startY + segment.y + segment.height;
        } else if (wp > 0) {
          sweepY = startY + segment.y + segment.height * wp;
          break;
        } else {
          break;
        }
      }

      cache.paintLayer(canvas, centerX, bright: false);
      if (sweepY > startY) {
        canvas.save();
        canvas.clipRect(
          Rect.fromLTRB(-1, startY - 1, size.width + 1, sweepY + 1),
        );
        cache.paintLayer(canvas, centerX, bright: true);
        canvas.restore();
      }
      return;
    }

    cache.paintLayer(canvas, startX, bright: false);
    final highlightPath = Path();
    for (final segment in segments) {
      final wp = _wordProgress(segment.wordStartMs, segment.wordLengthMs);
      if (wp <= 0) break;
      final boxes = segment.boxes;
      if (boxes.isEmpty) {
        final left = startX + segment.x;
        final width = segment.width * wp.clamp(0.0, 1.0);
        if (width > 0) {
          highlightPath.addRect(
            Rect.fromLTWH(left, segment.y, width, segment.height),
          );
        }
      } else {
        var remaining =
            boxes.fold<double>(0.0, (sum, box) => sum + box.width) *
            wp.clamp(0.0, 1.0);
        for (final box in boxes) {
          if (remaining <= 0) break;
          final width = math.min(box.width, remaining);
          if (width > 0) {
            highlightPath.addRect(
              Rect.fromLTWH(startX + box.left, box.top, width, box.height),
            );
          }
          remaining -= box.width;
        }
      }
      if (wp < 1.0) break;
    }
    if (!highlightPath.getBounds().isEmpty) {
      canvas.save();
      canvas.clipPath(highlightPath);
      cache.paintLayer(canvas, startX, bright: true);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _WordLyricPainter oldDelegate) {
    return !identical(oldDelegate.cache, cache) ||
        oldDelegate.textAlign != textAlign ||
        oldDelegate.vertical != vertical ||
        oldDelegate.progress != progress;
  }
}
