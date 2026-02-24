import 'dart:async';

import 'package:desktop_lyric/component/foreground.dart';
import 'package:desktop_lyric/component/lyric_line_display_area.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
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
  final scrollController = ScrollController();
  int _scrollToken = 0;
  late VoidCallback _lyricLineListener;

  @override
  void initState() {
    super.initState();

    _lyricLineListener = () {
      final line = DesktopLyricController.instance.lyricLine.value;
      _scrollToken += 1;
      final token = _scrollToken;

      /// 减去启动延时和滚动结束停留时间
      final Duration lastTime = line.length - waitFor - waitFor;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!scrollController.hasClients) return;

        scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
        );
        if (scrollController.position.maxScrollExtent > 0) {
          if (lastTime.isNegative) return;

          Future.delayed(waitFor, () {
            if (!scrollController.hasClients) return;
            if (token != _scrollToken) return;

            scrollController.animateTo(
              scrollController.position.maxScrollExtent,
              duration: lastTime,
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
    final alignment = switch (textDisplayController.lyricTextAlign) {
      LyricTextAlign.left => Alignment.centerLeft,
      LyricTextAlign.center => Alignment.center,
      LyricTextAlign.right => Alignment.centerRight,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            controller: scrollController,
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Align(
                alignment: alignment,
                child: const LyricLineDisplayArea(),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    DesktopLyricController.instance.lyricLine.removeListener(_lyricLineListener);
    scrollController.dispose();
    super.dispose();
  }
}
