import 'package:pure_player_lyric/component/foreground.dart';
import 'package:pure_player_lyric/component/lyric_text_display.dart';
import 'package:pure_player_lyric/component/lyric_transition_dots.dart';
import 'package:pure_player_lyric/component/word_lyric_text.dart';
import 'package:pure_player_lyric/message.dart';
import 'package:pure_player_lyric/desktop_lyric_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

const _lyricSwitchDuration = Duration(milliseconds: 700);
const _lyricSwitchCurve = Cubic(0.25, 0, 0.2, 1);
const _verticalTravel = 18.0;
const _horizontalTravel = 28.0;
const _absorbScaleDelta = 0.04;

class LyricLineDisplayArea extends StatelessWidget {
  final LyricLineChangedMessage? line;
  final bool isNext;
  final LyricTextAlign? alignment;

  /// 双行模式下该槽位在切换方向上的尺寸，让动画位移等于槽位间距
  final double? slotExtent;

  const LyricLineDisplayArea({
    super.key,
    this.line,
    this.isNext = false,
    this.alignment,
    this.slotExtent,
  });

  @override
  Widget build(BuildContext context) {
    final textDisplayController = context.watch<TextDisplayController>();
    final theme = context.watch<ThemeChangedMessage>();
    final vertical = textDisplayController.useVerticalDisplayMode;
    final effectiveAlignment =
        alignment ?? textDisplayController.lyricTextAlign;

    final playedColor = textDisplayController.hasSpecifiedPlayedColor
        ? textDisplayController.playedColor
        : Color(theme.primary).withValues(alpha: 1.0);
    final unplayedColor = textDisplayController.hasSpecifiedUnplayedColor
        ? textDisplayController.unplayedColor
        : playedColor;
    final outlineColor = lyricOutlineColor(
      textDisplayController.useLightOutline,
    );
    final textAlign = switch (effectiveAlignment) {
      LyricTextAlign.left => TextAlign.left,
      LyricTextAlign.center => TextAlign.center,
      LyricTextAlign.right => TextAlign.right,
      LyricTextAlign.separated => TextAlign.left,
    };
    final crossAxisAlignment = switch (effectiveAlignment) {
      LyricTextAlign.left => CrossAxisAlignment.start,
      LyricTextAlign.center => CrossAxisAlignment.center,
      LyricTextAlign.right => CrossAxisAlignment.end,
      LyricTextAlign.separated => CrossAxisAlignment.start,
    };
    final switchAlignment = vertical
        ? switch (effectiveAlignment) {
            LyricTextAlign.left => Alignment.topCenter,
            LyricTextAlign.center => Alignment.center,
            LyricTextAlign.right => Alignment.bottomCenter,
            LyricTextAlign.separated => Alignment.topCenter,
          }
        : switch (effectiveAlignment) {
            LyricTextAlign.left => Alignment.centerLeft,
            LyricTextAlign.center => Alignment.center,
            LyricTextAlign.right => Alignment.centerRight,
            LyricTextAlign.separated => Alignment.centerLeft,
          };

    return ValueListenableBuilder(
      valueListenable: DesktopLyricController.instance.lyricLine,
      builder: (context, controllerLine, _) {
        final lyricLine = line ?? controllerLine;
        final lyricProgress = isNext
            ? null
            : DesktopLyricController.instance.progressForLine(lyricLine.lineId);
        final lineColor = isNext ? unplayedColor : playedColor;
        final style = TextStyle(
          color: lineColor,
          fontSize: textDisplayController.lyricFontSize,
          fontWeight: lyricFontWeightFromInt(
            textDisplayController.lyricFontWeight,
          ),
        );
        final hasWords = lyricLine.words?.isNotEmpty ?? false;
        final isTransition =
            lyricLine.content.trim().isEmpty &&
            !hasWords &&
            lyricLine.length > const Duration(seconds: 3);

        final childKey = ValueKey<Object>(
          lyricLine.lineId ??
              (isTransition
                  ? "TRANSITION_${lyricLine.length.inMilliseconds}"
                  : "${lyricLine.content}|${lyricLine.translation}|${lyricLine.romanLyric}"),
        );

        final hasRoman =
            !isTransition &&
            textDisplayController.showRoman &&
            lyricLine.romanLyric != null;
        final hasTranslation =
            !isTransition &&
            textDisplayController.showLyricTranslation &&
            lyricLine.translation != null;

        Widget? romanWidget;
        if (hasRoman) {
          romanWidget = LyricTextDisplay(
            text: lyricLine.romanLyric!,
            style: TextStyle(
              color: lineColor,
              fontSize: textDisplayController.translationFontSize,
              fontWeight: lyricFontWeightFromInt(
                textDisplayController.lyricFontWeight,
              ),
            ),
            vertical: vertical,
            outlineColor: outlineColor,
            outlineWidth: lyricOutlineWidth(
              textDisplayController.translationFontSize,
            ),
            textAlign: textAlign,
            enableOutline: textDisplayController.enableStroke,
          );
        }

        Widget? translationWidget;
        if (hasTranslation) {
          translationWidget = LyricTextDisplay(
            text: lyricLine.translation!,
            style: TextStyle(
              color: lineColor,
              fontSize: textDisplayController.translationFontSize,
              fontWeight: lyricFontWeightFromInt(
                textDisplayController.lyricFontWeight,
              ),
            ),
            vertical: vertical,
            outlineColor: outlineColor,
            outlineWidth: lyricOutlineWidth(
              textDisplayController.translationFontSize,
            ),
            textAlign: textAlign,
            enableOutline: textDisplayController.enableStroke,
          );
        }

        Widget lyricWidget;
        if (isTransition) {
          lyricWidget = LyricTransitionDots(
            length: lyricLine.length,
            progress:
                lyricProgress ??
                DesktopLyricController.instance.progressForLine(null),
            color: lineColor,
            isPlaying: DesktopLyricController.instance.isPlaying,
            lineId: lyricLine.lineId,
          );
        } else if (isNext || !lyricLine.isWordByWord || !hasWords) {
          lyricWidget = LyricTextDisplay(
            text: lyricLine.content,
            style: style,
            vertical: vertical,
            outlineColor: outlineColor,
            outlineWidth: lyricOutlineWidth(
              textDisplayController.lyricFontSize,
            ),
            textAlign: textAlign,
            enableOutline: textDisplayController.enableStroke,
          );
        } else {
          lyricWidget = WordLyricText(
            line: lyricLine,
            color: unplayedColor,
            playedColor: playedColor,
            fontSize: textDisplayController.lyricFontSize,
            fontWeight: textDisplayController.lyricFontWeight,
            textAlign: textAlign,
            isPlaying: DesktopLyricController.instance.isPlaying,
            progress: lyricProgress!,
            enableOutline: textDisplayController.enableStroke,
            outlineColor: outlineColor,
            vertical: vertical,
          );
        }

        final children = <Widget>[
          if (hasRoman &&
              textDisplayController.romanPosition == RomanPosition.aboveText)
            romanWidget!,
          if (hasTranslation &&
              textDisplayController.translationPosition ==
                  TranslationPosition.beforeText)
            translationWidget!,
          lyricWidget,
          if (hasRoman &&
              textDisplayController.romanPosition == RomanPosition.between)
            romanWidget!,
          if (hasTranslation &&
              textDisplayController.translationPosition ==
                  TranslationPosition.afterText)
            translationWidget!,
          if (hasRoman &&
              textDisplayController.romanPosition ==
                  RomanPosition.belowTranslation)
            romanWidget!,
        ];

        final child = vertical
            ? Row(
                key: childKey,
                crossAxisAlignment: crossAxisAlignment,
                children: children,
              )
            : Column(
                key: childKey,
                crossAxisAlignment: crossAxisAlignment,
                children: children,
              );

        return _LyricLineTransition(
          animation: textDisplayController.lyricAnimation,
          alignment: switchAlignment,
          vertical: vertical,
          slotExtent: slotExtent,
          child: child,
        );
      },
    );
  }
}

class _LyricLineTransition extends StatefulWidget {
  const _LyricLineTransition({
    required this.animation,
    required this.alignment,
    required this.vertical,
    required this.child,
    this.slotExtent,
  });

  final LyricSwitchAnimation animation;
  final Alignment alignment;
  final bool vertical;
  final Widget child;
  final double? slotExtent;

  /// 双行模式下纵向动画位移等于槽位高度，让上一行滑出的终点与下一行滑入的起点衔接
  double get _verticalTravelFor =>
      vertical ? _verticalTravel : (slotExtent ?? _verticalTravel);

  /// 竖排双行模式下横向动画位移等于槽位宽度
  double get _horizontalTravelFor =>
      vertical ? (slotExtent ?? _horizontalTravel) : _horizontalTravel;

  @override
  State<_LyricLineTransition> createState() => _LyricLineTransitionState();
}

class _LyricLineTransitionState extends State<_LyricLineTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Widget _currentChild;
  Widget? _previousChild;

  @override
  void initState() {
    super.initState();
    _currentChild = widget.child;
    _controller =
        AnimationController(vsync: this, duration: _lyricSwitchDuration)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed && mounted) {
              setState(() => _previousChild = null);
            }
          });
  }

  @override
  void didUpdateWidget(covariant _LyricLineTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_currentChild.key == widget.child.key) {
      _currentChild = widget.child;
      return;
    }
    _previousChild = _currentChild;
    _currentChild = widget.child;
    _controller.forward(from: 0);
  }

  Widget _buildLayer(
    Widget child,
    double motion,
    double fade, {
    required bool isPrevious,
  }) {
    final opacity = isPrevious ? 1.0 - fade : fade;
    switch (widget.animation) {
      case LyricSwitchAnimation.slideUp:
        final travel = widget._verticalTravelFor;
        return Transform.translate(
          offset: Offset(
            0,
            isPrevious
                ? -motion * travel
                : (1.0 - motion) * travel,
          ),
          child: Opacity(opacity: opacity, child: child),
        );
      case LyricSwitchAnimation.slideDown:
        final travel = widget._verticalTravelFor;
        return Transform.translate(
          offset: Offset(
            0,
            isPrevious
                ? motion * travel
                : (motion - 1.0) * travel,
          ),
          child: Opacity(opacity: opacity, child: child),
        );
      case LyricSwitchAnimation.fade:
        return Opacity(opacity: opacity, child: child);
      case LyricSwitchAnimation.absorb:
        final scale = isPrevious
            ? 1.0 - motion * _absorbScaleDelta
            : 1.0 - (1.0 - motion) * _absorbScaleDelta;
        return Transform.scale(
          alignment: widget.alignment,
          scale: scale,
          child: Opacity(opacity: opacity, child: child),
        );
      case LyricSwitchAnimation.slideLeft:
        final travel = widget._horizontalTravelFor;
        return Transform.translate(
          offset: Offset(
            isPrevious
                ? -motion * travel
                : (1.0 - motion) * travel,
            0,
          ),
          child: Opacity(opacity: opacity, child: child),
        );
      case LyricSwitchAnimation.slideRight:
        final travel = widget._horizontalTravelFor;
        return Transform.translate(
          offset: Offset(
            isPrevious
                ? motion * travel
                : (motion - 1.0) * travel,
            0,
          ),
          child: Opacity(opacity: opacity, child: child),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final previousChild = _previousChild;
    final animated = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (previousChild == null) {
          return Stack(
            clipBehavior: Clip.none,
            alignment: widget.alignment,
            children: [_currentChild],
          );
        }
        final motion = _lyricSwitchCurve.transform(_controller.value);
        final fade = Curves.easeInOutSine.transform(_controller.value);
        return Stack(
          clipBehavior: Clip.none,
          alignment: widget.alignment,
          children: [
            _buildLayer(previousChild, motion, fade, isPrevious: true),
            _buildLayer(_currentChild, motion, fade, isPrevious: false),
          ],
        );
      },
    );
    final slotExtent = widget.slotExtent;
    if (slotExtent == null) return animated;

    /// 双行模式固定切换区域尺寸，行高变化时歌词保持槽位居中不跳动
    return SizedBox(
      width: widget.vertical ? slotExtent : null,
      height: widget.vertical ? null : slotExtent,
      child: animated,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}