import 'dart:async';

import 'package:pure_player_lyric/component/foreground.dart';
import 'package:pure_player_lyric/component/lyric_line_display_area.dart';
import 'package:pure_player_lyric/desktop_lyric_controller.dart';
import 'package:pure_player_lyric/message.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LyricLineView extends StatefulWidget {
  const LyricLineView({super.key});

  @override
  State<LyricLineView> createState() => _LyricLineViewState();
}

class _LyricLineViewState extends State<LyricLineView> {
  /// 停留 300ms 后开始滚动，提前 300ms 滚动到底
  final waitFor = const Duration(milliseconds: 300);
  final slotScrollControllers = List.generate(2, (_) => ScrollController());
  int _scrollToken = 0;
  int _lineVersion = 0;
  late VoidCallback _lyricLineListener;

  @override
  void initState() {
    super.initState();

    _lyricLineListener = () {
      final line = DesktopLyricController.instance.lyricLine.value;
      _scrollToken += 1;
      _lineVersion += 1;
      final token = _scrollToken;

      /// 减去启动延时和滚动结束停留时间
      final Duration lastTime = line.length - waitFor - waitFor;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final currentSlot = textDisplayController.showDoubleLine
            ? _lineVersion % 2
            : 0;
        final scrollController = slotScrollControllers[currentSlot];
        if (!scrollController.hasClients) return;

        scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
        if (scrollController.position.maxScrollExtent > 0) {
          if (lastTime.isNegative) return;

          Future.delayed(waitFor, () {
            if (!scrollController.hasClients) return;
            if (token != _scrollToken) return;

            final scrollDuration = Duration(
              milliseconds: (lastTime.inMilliseconds * 0.8)
                  .clamp(200, 800)
                  .toInt(),
            );
            scrollController.animateTo(
              scrollController.position.maxScrollExtent,
              duration: scrollDuration,
              curve: Curves.easeOutQuart,
            );
          });
        }
      });
    };

    DesktopLyricController.instance.lyricLine.addListener(_lyricLineListener);
  }

  @override
  Widget build(BuildContext context) {
    final textDisplayController = context.watch<TextDisplayController>();
    final vertical = textDisplayController.useVerticalDisplayMode;
    final showDoubleLine = textDisplayController.showDoubleLine;

    return ValueListenableBuilder(
      valueListenable: DesktopLyricController.instance.lyricLine,
      builder: (context, lyricLine, _) {
        final nextLine = lyricLine.nextContent == null
            ? null
            : LyricLineChangedMessage(
                lyricLine.nextContent!,
                Duration.zero,
                lyricLine.nextTranslation,
                null,
                null,
                null,
                null,
                null,
                lyricLine.nextRomanLyric,
                null,
                null,
                null,
                null,
                null,
                null,
              );

        Widget slot(
          LyricLineChangedMessage? line,
          bool isNext,
          int slotIndex,
          bool animateTransition,
          bool outgoingOnlyTransition,
        ) => _buildSlot(
          context: context,
          textDisplayController: textDisplayController,
          vertical: vertical,
          showDoubleLine: showDoubleLine,
          line: line,
          isNext: isNext,
          slotIndex: slotIndex,
          animateTransition: animateTransition,
          outgoingOnlyTransition: outgoingOnlyTransition,
          alignmentOverride:
              textDisplayController.lyricTextAlign == LyricTextAlign.separated
              ? (slotIndex == 0 ? LyricTextAlign.left : LyricTextAlign.right)
              : null,
        );

        if (!showDoubleLine) {
          return slot(lyricLine, false, 0, true, false);
        }

        final currentSlotIndex = _lineVersion % 2;
        final first = currentSlotIndex == 0
            ? slot(lyricLine, false, 0, false, false)
            : nextLine == null
            ? const SizedBox.shrink()
            : slot(nextLine, true, 0, true, true);
        final second = currentSlotIndex == 1
            ? slot(lyricLine, false, 1, false, false)
            : nextLine == null
            ? const SizedBox.shrink()
            : slot(nextLine, true, 1, true, true);
        return vertical
            ? Row(
                children: [
                  Expanded(child: first),
                  Expanded(child: second),
                ],
              )
            : Column(
                children: [
                  Expanded(child: first),
                  Expanded(child: second),
                ],
              );
      },
    );
  }

  Widget _buildSlot({
    required BuildContext context,
    required TextDisplayController textDisplayController,
    required bool vertical,
    required bool showDoubleLine,
    required LyricLineChangedMessage? line,
    required bool isNext,
    required int slotIndex,
    required bool animateTransition,
    required bool outgoingOnlyTransition,
    LyricTextAlign? alignmentOverride,
  }) {
    final effectiveAlignment =
        alignmentOverride ?? textDisplayController.lyricTextAlign;
    final alignment = vertical
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

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: 16.0,
        vertical: vertical ? 8.0 : 0.0,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            controller: slotScrollControllers[slotIndex],
            scrollDirection: vertical ? Axis.vertical : Axis.horizontal,
            child: ConstrainedBox(
              constraints: vertical
                  ? BoxConstraints(minHeight: constraints.maxHeight)
                  : BoxConstraints(minWidth: constraints.maxWidth),
              child: Align(
                alignment: alignment,
                child: LyricLineDisplayArea(
                  line: line,
                  isNext: isNext,
                  alignment: effectiveAlignment,
                  animateTransition: animateTransition,
                  outgoingOnlyTransition: outgoingOnlyTransition,
                  slotExtent: showDoubleLine
                      ? (vertical
                            ? constraints.maxWidth
                            : constraints.maxHeight)
                      : null,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    DesktopLyricController.instance.lyricLine.removeListener(
      _lyricLineListener,
    );
    for (final controller in slotScrollControllers) {
      controller.dispose();
    }
    super.dispose();
  }
}
