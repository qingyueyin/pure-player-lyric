import 'package:pure_player_lyric/component/foreground.dart';
import 'package:pure_player_lyric/message.dart';
import 'package:pure_player_lyric/desktop_lyric_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ActionRow extends StatelessWidget {
  const ActionRow({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeChangedMessage>();
    final textDisplayController = context.watch<TextDisplayController>();
    final lyricTextAlign = textDisplayController.lyricTextAlign;
    // 图标颜色独立于歌词文字配色：开 → 主题色，关 → 固定前景色
    final color = textDisplayController.iconFollowThemeColor
        ? Color(theme.primary)
        : Color(theme.onSurface);
    // 图标没有描边，用同色系光晕兜底，保证任意桌面背景下可见
    final iconShadows = [
      Shadow(
        color: lyricOutlineColor(textDisplayController.useLightOutline),
        blurRadius: 3,
      ),
    ];
    const spacer = SizedBox(width: 8);

    final mainAlignment = switch (lyricTextAlign) {
      LyricTextAlign.left => MainAxisAlignment.start,
      LyricTextAlign.center => MainAxisAlignment.center,
      LyricTextAlign.right => MainAxisAlignment.end,
      LyricTextAlign.separated => MainAxisAlignment.center,
    };

    return Row(
      mainAxisAlignment: mainAlignment,
      children: [
        if (lyricTextAlign != LyricTextAlign.left) const Spacer(),
        IconButton(
          onPressed: () {
            DesktopLyricController.instance.setLocked(true);
            DesktopLyricController.sendControlEvent(ControlEvent.lock);
          },
          color: color,
          icon: Icon(Icons.lock, shadows: iconShadows),
        ),
        spacer,
        IconButton(
          onPressed: () {
            DesktopLyricController.sendControlEvent(ControlEvent.previousAudio);
          },
          color: color,
          icon: Icon(Icons.skip_previous, shadows: iconShadows),
        ),
        spacer,
        ValueListenableBuilder(
          valueListenable: DesktopLyricController.instance.isPlaying,
          builder: (context, isPlaying, _) => IconButton(
            onPressed: () {
              DesktopLyricController.sendControlEvent(
                isPlaying ? ControlEvent.pause : ControlEvent.start,
              );
            },
            color: color,
            icon: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              shadows: iconShadows,
            ),
          ),
        ),
        spacer,
        IconButton(
          onPressed: () {
            DesktopLyricController.sendControlEvent(ControlEvent.nextAudio);
          },
          color: color,
          icon: Icon(Icons.skip_next, shadows: iconShadows),
        ),
        spacer,
        IconButton(
          onPressed: () {
            DesktopLyricController.sendControlEvent(ControlEvent.close);
          },
          color: color,
          icon: Icon(Icons.close, shadows: iconShadows),
        ),
        if (lyricTextAlign != LyricTextAlign.right) const Spacer(),
      ],
    );
  }
}
