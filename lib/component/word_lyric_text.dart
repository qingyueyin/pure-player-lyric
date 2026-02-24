import 'dart:math';

import 'package:desktop_lyric/component/foreground.dart';
import 'package:desktop_lyric/message.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class WordLyricText extends StatefulWidget {
  final LyricLineChangedMessage line;
  final Color color;
  final double fontSize;
  final int fontWeight;
  final TextAlign textAlign;
  final ValueListenable<bool> isPlaying;

  const WordLyricText({
    super.key,
    required this.line,
    required this.color,
    required this.fontSize,
    required this.fontWeight,
    required this.textAlign,
    required this.isPlaying,
  });

  @override
  State<WordLyricText> createState() => _WordLyricTextState();
}

class _WordLyricTextState extends State<WordLyricText> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Stopwatch _stopwatch = Stopwatch();
  final ValueNotifier<int> _progressMs = ValueNotifier(0);

  List<_WordLayout> _layouts = const [];
  double _textWidth = 0;
  double _textHeight = 0;
  int _baseProgressMs = 0;

  late VoidCallback _playingListener;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _playingListener = _syncPlaying;
    widget.isPlaying.addListener(_playingListener);
    _resetFromLine(widget.line);
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
    if (oldWidget.line != widget.line ||
        oldWidget.fontSize != widget.fontSize ||
        oldWidget.fontWeight != widget.fontWeight ||
        oldWidget.color != widget.color) {
      _resetFromLine(widget.line);
      _syncPlaying();
    }
  }

  void _resetFromLine(LyricLineChangedMessage line) {
    _stopwatch.reset();
    _baseProgressMs = line.progressMs ?? 0;
    _progressMs.value = _baseProgressMs;
    final words = line.words ?? const [];
    final fontWeight = lyricFontWeightFromInt(widget.fontWeight);

    final inactive = widget.color.withValues(alpha: 0.22);
    final active = widget.color;
    final outline = lyricOutlineColor(widget.color);
    final outlineWidth = lyricOutlineWidth(widget.fontSize);

    final layouts = <_WordLayout>[];
    double x = 0;
    double maxH = 0;
    for (final w in words) {
      final baseSpan = TextSpan(
        text: w.content,
        style: TextStyle(
          fontSize: widget.fontSize,
          fontWeight: fontWeight,
          color: inactive,
        ),
      );
      final activeSpan = TextSpan(
        text: w.content,
        style: TextStyle(
          fontSize: widget.fontSize,
          fontWeight: fontWeight,
          color: active,
        ),
      );

      final basePainter = TextPainter(
        text: baseSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
        maxLines: 1,
      )..layout();
      final activePainter = TextPainter(
        text: activeSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
        maxLines: 1,
      )..layout();

      final strokePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = outlineWidth
        ..color = outline;
      final outlinePainter = TextPainter(
        text: TextSpan(
          text: w.content,
          style: TextStyle(
            fontSize: widget.fontSize,
            fontWeight: fontWeight,
            foreground: strokePaint,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
        maxLines: 1,
      )..layout();

      final width = max(basePainter.width, max(activePainter.width, outlinePainter.width));
      final height = max(basePainter.height, max(activePainter.height, outlinePainter.height));
      maxH = max(maxH, height);

      layouts.add(
        _WordLayout(
          startMs: w.startMs,
          lengthMs: w.lengthMs,
          x: x,
          width: width,
          height: height,
          outline: outlinePainter,
          inactive: basePainter,
          active: activePainter,
        ),
      );
      x += width;
    }

    _layouts = layouts;
    _textWidth = x;
    _textHeight = maxH;
  }

  void _syncPlaying() {
    final playing = widget.isPlaying.value;
    if (playing) {
      if (!_ticker.isActive) _ticker.start();
      if (!_stopwatch.isRunning) _stopwatch.start();
    } else {
      if (_stopwatch.isRunning) {
        _stopwatch.stop();
        _baseProgressMs += _stopwatch.elapsedMilliseconds;
        _stopwatch.reset();
        _progressMs.value = _baseProgressMs;
      }
      if (_ticker.isActive) _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    if (!_stopwatch.isRunning) return;
    final next = _baseProgressMs + _stopwatch.elapsedMilliseconds;
    if (next == _progressMs.value) return;
    _progressMs.value = next;
  }

  @override
  void dispose() {
    widget.isPlaying.removeListener(_playingListener);
    _ticker.dispose();
    _stopwatch.stop();
    _progressMs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _progressMs,
      builder: (context, progress, _) {
        if (_layouts.isEmpty) {
          return const SizedBox.shrink();
        }

        return SizedBox(
          width: _textWidth,
          height: _textHeight,
          child: CustomPaint(
            painter: _WordLyricPainter(
              layouts: _layouts,
              progressMs: progress,
              textAlign: widget.textAlign,
            ),
          ),
        );
      },
    );
  }
}

class _WordLyricPainter extends CustomPainter {
  final List<_WordLayout> layouts;
  final int progressMs;
  final TextAlign textAlign;

  _WordLyricPainter({
    required this.layouts,
    required this.progressMs,
    required this.textAlign,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (layouts.isEmpty) return;
    final totalW = layouts.last.x + layouts.last.width;
    final startX = switch (textAlign) {
      TextAlign.left || TextAlign.start => 0.0,
      TextAlign.center => (size.width - totalW) / 2,
      TextAlign.right || TextAlign.end => size.width - totalW,
      _ => 0.0,
    };

    for (final w in layouts) {
      final dx = startX + w.x;
      final dy = 0.0;

      final outlineOffset = Offset(dx, dy);
      w.outline.paint(canvas, outlineOffset);
      w.inactive.paint(canvas, outlineOffset);

      final wordLen = max(w.lengthMs, 0);
      final wordStart = w.startMs.toDouble();
      final wordEnd = wordStart + wordLen;
      final pos = progressMs.toDouble();
      final p = wordLen <= 0
          ? (pos >= wordEnd ? 1.0 : 0.0)
          : ((pos - wordStart) / wordLen).clamp(0.0, 1.0);
      if (p <= 0.0) continue;

      final rect = Rect.fromLTWH(dx, dy, w.width, w.height);
      final fade = (p + 0.05).clamp(0.0, 1.0);

      canvas.saveLayer(rect, Paint());
      w.outline.paint(canvas, outlineOffset);
      w.active.paint(canvas, outlineOffset);
      final maskPaint = Paint()
        ..blendMode = BlendMode.dstIn
        ..shader = LinearGradient(
          colors: const [
            Colors.white,
            Colors.white,
            Colors.transparent,
            Colors.transparent,
          ],
          stops: [0.0, p, fade, 1.0],
        ).createShader(rect);
      canvas.drawRect(rect, maskPaint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _WordLyricPainter oldDelegate) {
    return oldDelegate.progressMs != progressMs ||
        oldDelegate.layouts != layouts ||
        oldDelegate.textAlign != textAlign;
  }
}

class _WordLayout {
  final int startMs;
  final int lengthMs;
  final double x;
  final double width;
  final double height;
  final TextPainter outline;
  final TextPainter inactive;
  final TextPainter active;

  const _WordLayout({
    required this.startMs,
    required this.lengthMs,
    required this.x,
    required this.width,
    required this.height,
    required this.outline,
    required this.inactive,
    required this.active,
  });
}
