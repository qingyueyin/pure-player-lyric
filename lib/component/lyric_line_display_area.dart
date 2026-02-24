import 'package:desktop_lyric/component/foreground.dart';
import 'package:desktop_lyric/component/lyric_transition_dots.dart';
import 'package:desktop_lyric/component/word_lyric_text.dart';
import 'package:desktop_lyric/message.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class LyricLineDisplayArea extends StatelessWidget {
  const LyricLineDisplayArea({super.key});

  @override
  Widget build(BuildContext context) {
    final textDisplayController = context.watch<TextDisplayController>();
    final theme = context.watch<ThemeChangedMessage>();

    final textColor = textDisplayController.hasSpecifiedColor
        ? textDisplayController.specifiedColor
        : Color(theme.primary);
    final textAlign = switch (textDisplayController.lyricTextAlign) {
      LyricTextAlign.left => TextAlign.left,
      LyricTextAlign.center => TextAlign.center,
      LyricTextAlign.right => TextAlign.right,
    };
    final crossAxisAlignment = switch (textDisplayController.lyricTextAlign) {
      LyricTextAlign.left => CrossAxisAlignment.start,
      LyricTextAlign.center => CrossAxisAlignment.center,
      LyricTextAlign.right => CrossAxisAlignment.end,
    };

    return ValueListenableBuilder(
      valueListenable: DesktopLyricController.instance.lyricLine,
      builder: (context, lyricLine, _) {
        final style = TextStyle(
          color: textColor,
          fontSize: textDisplayController.lyricFontSize,
          fontWeight: lyricFontWeightFromInt(
            textDisplayController.lyricFontWeight,
          ),
        );
        final hasWords = lyricLine.words?.isNotEmpty ?? false;
        final isTransition =
            lyricLine.content.trim().isEmpty &&
            !hasWords &&
            lyricLine.length > const Duration(seconds: 5);

        final childKey = ValueKey<String>(
          isTransition
              ? "TRANSITION_${lyricLine.length.inMilliseconds}_${lyricLine.progressMs}"
              : "${lyricLine.content}|${lyricLine.translation}",
        );

        final child = Column(
          key: childKey,
          crossAxisAlignment: crossAxisAlignment,
          children: [
            if (isTransition)
              LyricTransitionDots(
                length: lyricLine.length,
                progressMs: lyricLine.progressMs,
                color: textColor,
                isPlaying: DesktopLyricController.instance.isPlaying,
              )
            else if (hasWords)
              WordLyricText(
                line: lyricLine,
                color: textColor,
                fontSize: textDisplayController.lyricFontSize,
                fontWeight: textDisplayController.lyricFontWeight,
                textAlign: textAlign,
                isPlaying: DesktopLyricController.instance.isPlaying,
              )
            else
              outlinedText(
                key: LYRIC_TEXT_KEY,
                text: lyricLine.content,
                style: style,
                outlineColor: lyricOutlineColor(textColor),
                outlineWidth: lyricOutlineWidth(
                  textDisplayController.lyricFontSize,
                ),
                maxLines: 1,
                overflow: TextOverflow.clip,
                textAlign: textAlign,
                softWrap: false,
              ),
            if (!isTransition &&
                textDisplayController.showLyricTranslation &&
                lyricLine.translation != null)
              outlinedText(
                key: TRANSLATION_TEXT_KEY,
                text: lyricLine.translation!,
                style: TextStyle(
                  color: textColor,
                  fontSize: textDisplayController.translationFontSize,
                  fontWeight: lyricFontWeightFromInt(
                    textDisplayController.lyricFontWeight,
                  ),
                ),
                outlineColor: lyricOutlineColor(textColor),
                outlineWidth: lyricOutlineWidth(
                  textDisplayController.translationFontSize,
                ),
                maxLines: 1,
                overflow: TextOverflow.clip,
                textAlign: textAlign,
                softWrap: false,
              ),
          ],
        );

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: const Cubic(0.2, 0.0, 0.0, 1.0),
          switchOutCurve: const Cubic(0.2, 0.0, 0.0, 1.0),
          transitionBuilder: (child, animation) {
            final fade = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            );
            return FadeTransition(
              opacity: fade,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.0, 0.01),
                  end: Offset.zero,
                ).animate(fade),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.98, end: 1.0).animate(fade),
                  child: child,
                ),
              ),
            );
          },
          child: child,
        );
      },
    );
  }
}
