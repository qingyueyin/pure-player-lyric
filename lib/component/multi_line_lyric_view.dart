import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:pure_player_lyric/component/foreground.dart';
import 'package:pure_player_lyric/component/lyric_text_display.dart';
import 'package:pure_player_lyric/component/lyric_transition_dots.dart';
import 'package:pure_player_lyric/component/word_lyric_text.dart';
import 'package:pure_player_lyric/desktop_lyric_controller.dart';
import 'package:pure_player_lyric/message.dart';
import 'package:provider/provider.dart';

const _smoothDuration = Duration(milliseconds: 700);
const _smoothCurve = Cubic(0.25, 0, 0.2, 1);
const _currentLineAlignment = 0.5;
const _inactiveScale = 0.9;
const _secondaryGap = 4.0;
const _playedLineOpacity = 0.45;
const _playedRevealDuration = Duration(seconds: 3);
final _lineSpring = SpringDescription(mass: 1, stiffness: 100, damping: 17);
final _staggerSpring = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: 200,
  ratio: 1.1,
);
int _staggerDelayMs(int itemIndex, int visibleStartIndex) {
  final distance = (itemIndex - visibleStartIndex).abs();
  var step = 50.0;
  var total = 0.0;
  for (var index = 0; index < distance; index++) {
    total += step;
    step /= 1.05;
  }
  return total.toInt();
}

class MultiLineLyricView extends StatefulWidget {
  const MultiLineLyricView({super.key});

  @override
  State<MultiLineLyricView> createState() => _MultiLineLyricViewState();
}

class _MultiLineLyricViewState extends State<MultiLineLyricView>
    with TickerProviderStateMixin {
  final _scrollController = ScrollController();
  final _lineKeys = <int, GlobalKey>{};
  late final AnimationController _scrollAnimation;
  List<FullLyricLine> _displayLines = const [];
  List<double> _itemExtents = const [];
  List<FullLyricLine>? _lastSnapshot;
  int? _lastLineId;
  int _lastLineIndex = -1;
  bool? _lastVertical;
  int _followToken = 0;
  int _layoutToken = 0;
  bool _followPaused = false;
  bool _programmaticScroll = false;
  bool _skipNextStagger = false;
  double _leadingPadding = 0;
  int _layoutSignature = 0;
  int _staggerGeneration = 0;
  int _staggerVisibleStartIndex = 0;
  double _staggerShift = 0;
  bool _revealPlayedLines = false;
  Timer? _playedRevealTimer;

  GlobalKey _keyForLine(int lineId) =>
      _lineKeys.putIfAbsent(lineId, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    _scrollAnimation = AnimationController.unbounded(vsync: this)
      ..addListener(_applyScrollAnimation)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed) {
          _programmaticScroll = false;
        }
      });
  }

  void _applyScrollAnimation() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    _scrollController.jumpTo(
      _scrollAnimation.value
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble(),
    );
  }

  void _pauseFollow() {
    _scrollAnimation.stop();
    _programmaticScroll = false;
    _followPaused = true;
    _skipNextStagger = true;
    final token = ++_followToken;
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (!mounted || token != _followToken) return;
      _followPaused = false;
      _followCurrentLine(animate: true);
    });
  }

  /// 用户滚动期间临时显示已播放歌词，停止滚动超时后恢复隐藏
  void _revealPlayed() {
    _playedRevealTimer?.cancel();
    _playedRevealTimer = Timer(_playedRevealDuration, () {
      if (!mounted) return;
      setState(() => _revealPlayedLines = false);
    });
    if (_revealPlayedLines) return;
    setState(() => _revealPlayedLines = true);
  }

  void _scheduleFollow(int? lineId, bool vertical, {required bool forceJump}) {
    if (lineId == null) return;
    final modeChanged = _lastVertical != null && _lastVertical != vertical;
    final lineChanged = lineId != _lastLineId;
    if (!lineChanged && !modeChanged && !forceJump) return;
    if (modeChanged || forceJump) {
      _scrollAnimation.stop();
      _programmaticScroll = false;
    }
    final animate = _lastVertical != null && !modeChanged && !forceJump;
    _lastLineId = lineId;
    _lastVertical = vertical;
    final token = ++_layoutToken;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _followPaused || token != _layoutToken) return;
      _followCurrentLine(animate: animate);
    });
  }

  double _targetOffset(int index, int lineId) {
    final position = _scrollController.position;
    final targetContext = _lineKeys[lineId]?.currentContext;
    final renderObject = targetContext?.findRenderObject();
    if (renderObject != null) {
      final viewport = RenderAbstractViewport.of(renderObject);
      return viewport
          .getOffsetToReveal(renderObject, _currentLineAlignment)
          .offset
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
    }
    var leadingExtent = _leadingPadding;
    for (var itemIndex = 0; itemIndex < index; itemIndex++) {
      leadingExtent += _itemExtents[itemIndex];
    }
    return (leadingExtent +
            _itemExtents[index] / 2 -
            position.viewportDimension / 2)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
  }

  int _firstVisibleLineIndex() {
    if (!_scrollController.hasClients || _itemExtents.isEmpty) return 0;
    var extent = _leadingPadding;
    final offset = _scrollController.offset;
    for (var index = 0; index < _itemExtents.length; index++) {
      if (extent + _itemExtents[index] > offset) return index;
      extent += _itemExtents[index];
    }
    return _itemExtents.length - 1;
  }

  void _followCurrentLine({required bool animate}) {
    final lineId = DesktopLyricController.instance.lyricLine.value.lineId;
    if (lineId == null || !_scrollController.hasClients) return;
    final index = _displayLines.indexWhere((line) => line.lineId == lineId);
    if (index < 0 || index >= _itemExtents.length) return;
    final position = _scrollController.position;
    final offset = _targetOffset(index, lineId);
    final delta = offset - position.pixels;
    if (delta.abs() < 0.5) {
      _lastLineIndex = index;
      _skipNextStagger = false;
      return;
    }
    _scrollAnimation.stop();
    _programmaticScroll = true;
    if (!animate) {
      _scrollController.jumpTo(offset);
      _lastLineIndex = index;
      _skipNextStagger = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_scrollAnimation.isAnimating) {
          _programmaticScroll = false;
        }
      });
      return;
    }
    if (textDisplayController.multiLineAnimation ==
        MultiLineAnimationStyle.spring) {
      final canStagger =
          !_skipNextStagger &&
          _lastLineIndex >= 0 &&
          (index - _lastLineIndex).abs() <= 10;
      _staggerVisibleStartIndex = _firstVisibleLineIndex();
      _scrollController.jumpTo(offset);
      _programmaticScroll = false;
      if (canStagger) {
        setState(() {
          _staggerShift = textDisplayController.useVerticalDisplayMode
              ? -delta
              : delta;
          _staggerGeneration += 1;
        });
      }
    } else {
      _scrollAnimation.value = position.pixels;
      _scrollAnimation.animateTo(
        offset,
        duration: _smoothDuration,
        curve: _smoothCurve,
      );
    }
    _lastLineIndex = index;
    _skipNextStagger = false;
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<TextDisplayController>();
    final theme = context.watch<ThemeChangedMessage>();
    final vertical = controller.useVerticalDisplayMode;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportExtent = vertical
            ? constraints.maxWidth
            : constraints.maxHeight;
        return ValueListenableBuilder<List<FullLyricLine>>(
          valueListenable: DesktopLyricController.instance.fullLines,
          builder: (context, lines, _) =>
              ValueListenableBuilder<LyricLineChangedMessage>(
                valueListenable: DesktopLyricController.instance.lyricLine,
                builder: (context, lyricLine, _) {
                  final snapshotChanged = !identical(_lastSnapshot, lines);
                  if (snapshotChanged) {
                    _lastSnapshot = lines;
                    _lineKeys.clear();
                    _lastLineId = null;
                    _lastLineIndex = -1;
                    _scrollAnimation.stop();
                    _programmaticScroll = false;
                  }
                  final displayLines = lines
                      .where(
                        (line) =>
                            line.content == null ||
                            line.content!.trim().isNotEmpty,
                      )
                      .toList(growable: false);
                  if (displayLines.isEmpty || !viewportExtent.isFinite) {
                    _displayLines = const [];
                    _itemExtents = const [];
                    return const SizedBox.shrink();
                  }
                  _displayLines = displayLines;
                  _itemExtents = [
                    for (final line in displayLines)
                      _lineExtent(
                        context,
                        line,
                        controller,
                        vertical,
                        constraints.maxWidth,
                      ),
                  ];
                  _leadingPadding = math.max(
                    0.0,
                    (viewportExtent - _itemExtents.first) / 2,
                  );
                  final trailingPadding = math.max(
                    0.0,
                    (viewportExtent - _itemExtents.last) / 2,
                  );
                  final signature = Object.hash(
                    vertical,
                    viewportExtent.round(),
                    Object.hashAll(
                      _itemExtents.map((extent) => extent.round()),
                    ),
                  );
                  final layoutChanged = signature != _layoutSignature;
                  _layoutSignature = signature;
                  _scheduleFollow(
                    lyricLine.lineId,
                    vertical,
                    forceJump: snapshotChanged || layoutChanged,
                  );
                  final currentIndex = displayLines.indexWhere(
                    (line) => line.lineId == lyricLine.lineId,
                  );
                  final padding = vertical
                      ? EdgeInsets.only(
                          right: _leadingPadding,
                          left: trailingPadding,
                        )
                      : EdgeInsets.only(
                          top: _leadingPadding,
                          bottom: trailingPadding,
                        );
                  final list = ListView.builder(
                    controller: _scrollController,
                    reverse: vertical,
                    scrollDirection: vertical ? Axis.horizontal : Axis.vertical,
                    padding: padding,
                    itemCount: displayLines.length,
                    itemExtentBuilder: (index, _) => _itemExtents[index],
                    scrollCacheExtent: ScrollCacheExtent.pixels(
                      vertical ? 480 : 720,
                    ),
                    itemBuilder: (context, index) => _buildLine(
                      displayLines[index],
                      lyricLine,
                      controller,
                      theme,
                      vertical,
                      constraints.maxWidth,
                      _itemExtents[index],
                      index,
                      currentIndex,
                    ),
                  );
                  return NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      final isUserScroll =
                          notification is ScrollStartNotification &&
                              notification.dragDetails != null ||
                          notification is ScrollUpdateNotification &&
                              notification.dragDetails != null ||
                          notification is UserScrollNotification &&
                              notification.direction != ScrollDirection.idle;
                      if (isUserScroll && !_programmaticScroll) _pauseFollow();
                      if (!_programmaticScroll &&
                          (notification is ScrollStartNotification ||
                              notification is ScrollUpdateNotification)) {
                        _revealPlayed();
                      }
                      return false;
                    },
                    child: list,
                  );
                },
              ),
        );
      },
    );
  }

  double _lineExtent(
    BuildContext context,
    FullLyricLine line,
    TextDisplayController controller,
    bool vertical,
    double availableWidth,
  ) {
    final isTransition = line.content == null || line.content!.trim().isEmpty;
    if (isTransition) return (vertical ? 80 : 40) + controller.lineGap;
    final textScaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final defaultStyle = DefaultTextStyle.of(context).style;
    final extents = <double>[
      _textExtent(
        line.content!,
        controller.lyricFontSize,
        controller.lyricFontWeight,
        vertical,
        textScaler,
        direction,
        defaultStyle,
        availableWidth,
      ),
    ];
    if (controller.showRoman && line.romanLyric != null) {
      extents.add(
        _textExtent(
          line.romanLyric!,
          controller.translationFontSize,
          controller.lyricFontWeight,
          vertical,
          textScaler,
          direction,
          defaultStyle,
          availableWidth,
        ),
      );
    }
    if (controller.showLyricTranslation && line.translation != null) {
      extents.add(
        _textExtent(
          line.translation!,
          controller.translationFontSize,
          controller.lyricFontWeight,
          vertical,
          textScaler,
          direction,
          defaultStyle,
          availableWidth,
        ),
      );
    }
    return extents.fold(0.0, (sum, extent) => sum + extent) +
        _secondaryGap * (extents.length - 1) +
        controller.lineGap;
  }

  double _textExtent(
    String text,
    double fontSize,
    int fontWeight,
    bool vertical,
    TextScaler textScaler,
    TextDirection direction,
    TextStyle defaultStyle,
    double availableWidth,
  ) {
    final style = defaultStyle.merge(
      TextStyle(
        fontSize: fontSize,
        fontWeight: lyricFontWeightFromInt(fontWeight),
      ),
    );
    if (!vertical) {
      final painter =
          TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: direction,
            textScaler: textScaler,
          )..layout(
            maxWidth: availableWidth.isFinite && availableWidth > 0
                ? availableWidth
                : double.infinity,
          );
      final height = painter.height;
      painter.dispose();
      return height;
    }
    var width = 0.0;
    for (final char in text.split('')) {
      final painter = TextPainter(
        text: TextSpan(text: char, style: style),
        textDirection: direction,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      final charWidth = char.codeUnitAt(0) <= 0x7f
          ? painter.height
          : painter.width;
      if (charWidth > width) width = charWidth;
      painter.dispose();
    }
    return width;
  }

  Widget _buildLine(
    FullLyricLine line,
    LyricLineChangedMessage current,
    TextDisplayController controller,
    ThemeChangedMessage theme,
    bool vertical,
    double availableWidth,
    double itemExtent,
    int index,
    int currentIndex,
  ) {
    final isCurrent = line.lineId == current.lineId;
    final isTransition = line.content == null || line.content!.trim().isEmpty;
    final isPlayed = currentIndex >= 0 && index < currentIndex;
    final playedColor = controller.hasSpecifiedPlayedColor
        ? controller.playedColor
        : Color(theme.primary);
    final unplayedColor = controller.hasSpecifiedUnplayedColor
        ? controller.unplayedColor
        : playedColor.withValues(alpha: 0.55);
    final color = isCurrent ? playedColor : unplayedColor;
    final lineOpacity = isPlayed
        ? (controller.hidePlayedLines && !_revealPlayedLines
              ? 0.0
              : _playedLineOpacity)
        : 1.0;
    final outlineColor = lyricOutlineColor(controller.useLightOutline);
    final textAlign = switch (controller.lyricTextAlign) {
      LyricTextAlign.left => TextAlign.left,
      LyricTextAlign.center => TextAlign.center,
      LyricTextAlign.right => TextAlign.right,
      LyricTextAlign.separated => TextAlign.center,
    };
    final crossAxisAlignment = switch (controller.lyricTextAlign) {
      LyricTextAlign.left => CrossAxisAlignment.start,
      LyricTextAlign.center => CrossAxisAlignment.center,
      LyricTextAlign.right => CrossAxisAlignment.end,
      LyricTextAlign.separated => CrossAxisAlignment.center,
    };
    final lineAlignment = vertical
        ? switch (controller.lyricTextAlign) {
            LyricTextAlign.left => Alignment.topCenter,
            LyricTextAlign.center => Alignment.center,
            LyricTextAlign.right => Alignment.bottomCenter,
            LyricTextAlign.separated => Alignment.center,
          }
        : switch (controller.lyricTextAlign) {
            LyricTextAlign.left => Alignment.centerLeft,
            LyricTextAlign.center => Alignment.center,
            LyricTextAlign.right => Alignment.centerRight,
            LyricTextAlign.separated => Alignment.center,
          };
    final lyricLine = LyricLineChangedMessage(
      line.content ?? '',
      Duration(milliseconds: line.lengthMs),
      line.translation,
      line.words,
      null,
      null,
      null,
      null,
      line.romanLyric,
      null,
      line.words?.isNotEmpty ?? false,
      line.lineId,
      line.highlightDeadlineMs,
      isCurrent ? current.highlightCatchUpDurationMs : null,
      isCurrent ? current.highlightFinishLeadMs : null,
    );

    Widget lyricWidget;
    if (isTransition) {
      lyricWidget = isCurrent
          ? LyricTransitionDots(
              length: Duration(milliseconds: line.lengthMs),
              progress: DesktopLyricController.instance.progressForLine(
                line.lineId,
              ),
              color: playedColor,
              isPlaying: DesktopLyricController.instance.isPlaying,
              lineId: line.lineId,
            )
          : const SizedBox(width: 80, height: 40);
    } else if (isCurrent && line.words?.isNotEmpty == true) {
      lyricWidget = WordLyricText(
        line: lyricLine,
        color: unplayedColor,
        playedColor: playedColor,
        fontSize: controller.lyricFontSize,
        fontWeight: controller.lyricFontWeight,
        textAlign: textAlign,
        isPlaying: DesktopLyricController.instance.isPlaying,
        progress: DesktopLyricController.instance.progressForLine(line.lineId),
        enableOutline: controller.enableStroke,
        outlineColor: outlineColor,
        vertical: vertical,
        maxWidth: vertical ? null : availableWidth,
      );
    } else {
      lyricWidget = LyricTextDisplay(
        text: line.content ?? '',
        style: TextStyle(
          color: color,
          fontSize: controller.lyricFontSize,
          fontWeight: lyricFontWeightFromInt(controller.lyricFontWeight),
        ),
        vertical: vertical,
        outlineColor: outlineColor,
        outlineWidth: lyricOutlineWidth(controller.lyricFontSize),
        textAlign: textAlign,
        enableOutline: controller.enableStroke,
        wrap: !vertical,
        maxWidth: vertical ? null : availableWidth,
      );
    }

    Widget? romanWidget;
    if (controller.showRoman && line.romanLyric != null) {
      romanWidget = _buildSecondary(
        line.romanLyric!,
        color,
        controller,
        vertical,
        textAlign,
        outlineColor,
        availableWidth,
      );
    }
    Widget? translationWidget;
    if (controller.showLyricTranslation && line.translation != null) {
      translationWidget = _buildSecondary(
        line.translation!,
        color,
        controller,
        vertical,
        textAlign,
        outlineColor,
        availableWidth,
      );
    }
    final children = <Widget>[];
    void add(Widget child) {
      if (children.isNotEmpty) {
        children.add(
          vertical
              ? const SizedBox(width: _secondaryGap)
              : const SizedBox(height: _secondaryGap),
        );
      }
      children.add(child);
    }

    if (romanWidget != null &&
        controller.romanPosition == RomanPosition.aboveText) {
      add(romanWidget);
    }
    if (translationWidget != null &&
        controller.translationPosition == TranslationPosition.beforeText) {
      add(translationWidget);
    }
    add(lyricWidget);
    if (romanWidget != null &&
        controller.romanPosition == RomanPosition.between) {
      add(romanWidget);
    }
    if (translationWidget != null &&
        controller.translationPosition == TranslationPosition.afterText) {
      add(translationWidget);
    }
    if (romanWidget != null &&
        controller.romanPosition == RomanPosition.belowTranslation) {
      add(romanWidget);
    }
    final content = vertical
        ? Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: crossAxisAlignment,
            children: children,
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: crossAxisAlignment,
            children: children,
          );
    final lineWidget = RepaintBoundary(
      child: SizedBox(
        width: vertical ? itemExtent : availableWidth,
        height: vertical ? double.infinity : itemExtent,
        child: Align(alignment: lineAlignment, child: content),
      ),
    );
    final delay =
        textDisplayController.multiLineAnimation ==
            MultiLineAnimationStyle.spring
        ? _staggerDelayMs(index, _staggerVisibleStartIndex)
        : 0;
    return KeyedSubtree(
      key: _keyForLine(line.lineId),
      child: SizedBox(
        key: ValueKey('multi_line_item_${line.lineId}'),
        width: vertical ? itemExtent : null,
        height: vertical ? null : itemExtent,
        child: _MultiLineLineMotion(
          style: controller.multiLineAnimation,
          alignment: lineAlignment,
          isCurrent: isCurrent,
          opacity: lineOpacity,
          vertical: vertical,
          staggerGeneration: _staggerGeneration,
          staggerShift: _staggerShift,
          staggerDelay: Duration(milliseconds: delay),
          child: lineWidget,
        ),
      ),
    );
  }

  Widget _buildSecondary(
    String text,
    Color color,
    TextDisplayController controller,
    bool vertical,
    TextAlign textAlign,
    Color outlineColor,
    double availableWidth,
  ) {
    return LyricTextDisplay(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: controller.translationFontSize,
        fontWeight: lyricFontWeightFromInt(controller.lyricFontWeight),
      ),
      vertical: vertical,
      outlineColor: outlineColor,
      outlineWidth: lyricOutlineWidth(controller.translationFontSize),
      textAlign: textAlign,
      enableOutline: controller.enableStroke,
      wrap: !vertical,
      maxWidth: vertical ? null : availableWidth,
    );
  }

  @override
  void dispose() {
    _followToken++;
    _layoutToken++;
    _playedRevealTimer?.cancel();
    _scrollAnimation.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}

class _MultiLineLineMotion extends StatefulWidget {
  const _MultiLineLineMotion({
    required this.style,
    required this.alignment,
    required this.isCurrent,
    required this.opacity,
    required this.vertical,
    required this.staggerGeneration,
    required this.staggerShift,
    required this.staggerDelay,
    required this.child,
  });

  final MultiLineAnimationStyle style;
  final Alignment alignment;
  final bool isCurrent;
  final double opacity;
  final bool vertical;
  final int staggerGeneration;
  final double staggerShift;
  final Duration staggerDelay;
  final Widget child;

  @override
  State<_MultiLineLineMotion> createState() => _MultiLineLineMotionState();
}

class _MultiLineLineMotionState extends State<_MultiLineLineMotion>
    with TickerProviderStateMixin {
  late final AnimationController _scale;
  late final AnimationController _float;
  late final AnimationController _opacity;
  late final AnimationController _stagger;
  Timer? _staggerTimer;

  double get _targetScale => widget.isCurrent ? 1 : _inactiveScale;
  double get _targetFloat => widget.isCurrent ? 1 : 0;

  @override
  void initState() {
    super.initState();
    _scale = AnimationController.unbounded(vsync: this, value: _targetScale);
    _float = AnimationController.unbounded(vsync: this, value: _targetFloat);
    _opacity = AnimationController.unbounded(
      vsync: this,
      value: widget.opacity,
    );
    _stagger = AnimationController.unbounded(vsync: this);
    _scheduleStagger();
  }

  @override
  void didUpdateWidget(covariant _MultiLineLineMotion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isCurrent != widget.isCurrent ||
        oldWidget.style != widget.style) {
      _animateVisuals();
    }
    if (oldWidget.opacity != widget.opacity ||
        oldWidget.style != widget.style) {
      _animateOpacity();
    }
    if (oldWidget.staggerGeneration != widget.staggerGeneration ||
        oldWidget.vertical != widget.vertical) {
      _scheduleStagger();
    }
  }

  void _animateOpacity() {
    _opacity.stop();
    _opacity.animateTo(
      widget.opacity,
      duration: widget.style == MultiLineAnimationStyle.smooth
          ? _smoothDuration
          : const Duration(milliseconds: 360),
      curve: _smoothCurve,
    );
  }

  void _animateVisuals() {
    _scale.stop();
    _float.stop();
    if (widget.style == MultiLineAnimationStyle.smooth) {
      _scale.animateTo(
        _targetScale,
        duration: _smoothDuration,
        curve: _smoothCurve,
      );
      _float.animateTo(
        _targetFloat,
        duration: _smoothDuration,
        curve: _smoothCurve,
      );
    } else {
      _scale.animateWith(
        SpringSimulation(_lineSpring, _scale.value, _targetScale, 0),
      );
      _float.animateWith(
        SpringSimulation(_lineSpring, _float.value, _targetFloat, 0),
      );
    }
  }

  void _scheduleStagger() {
    _staggerTimer?.cancel();
    _stagger.stop();
    if (widget.style != MultiLineAnimationStyle.spring ||
        widget.staggerGeneration <= 0 ||
        widget.staggerShift.abs() < 0.5) {
      _stagger.value = 0;
      return;
    }
    _stagger.value = widget.staggerShift;
    final generation = widget.staggerGeneration;
    void start() {
      if (!mounted || generation != widget.staggerGeneration) return;
      _stagger.animateWith(
        SpringSimulation(
          _staggerSpring,
          _stagger.value,
          0,
          0,
          tolerance: const Tolerance(distance: 0.5, velocity: 0.1),
        ),
      );
    }

    if (widget.staggerDelay <= Duration.zero) {
      start();
    } else {
      _staggerTimer = Timer(widget.staggerDelay, start);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_scale, _float, _opacity, _stagger]),
      child: widget.child,
      builder: (context, child) {
        final floatShift = _float.value * 4;
        final offset = widget.vertical
            ? Offset(_stagger.value + floatShift, 0)
            : Offset(0, _stagger.value - floatShift);
        return Opacity(
          opacity: _opacity.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: offset,
            child: Transform.scale(
              alignment: widget.alignment,
              scale: _scale.value,
              child: child,
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _staggerTimer?.cancel();
    _scale.dispose();
    _float.dispose();
    _opacity.dispose();
    _stagger.dispose();
    super.dispose();
  }
}
