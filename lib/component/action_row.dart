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
    final lyricTextAlign = context
        .select<TextDisplayController, LyricTextAlign>(
          (controller) => controller.lyricTextAlign,
        );
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
          color: Color(theme.onSurface),
          icon: const Icon(Icons.lock),
        ),
        spacer,
        IconButton(
          onPressed: () {
            DesktopLyricController.sendControlEvent(ControlEvent.previousAudio);
          },
          color: Color(theme.onSurface),
          icon: const Icon(Icons.skip_previous),
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
            color: Color(theme.onSurface),
            icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
          ),
        ),
        spacer,
        IconButton(
          onPressed: () {
            DesktopLyricController.sendControlEvent(ControlEvent.nextAudio);
          },
          color: Color(theme.onSurface),
          icon: const Icon(Icons.skip_next),
        ),
        spacer,
        IconButton(
          onPressed: () {
            DesktopLyricController.sendControlEvent(ControlEvent.close);
          },
          color: Color(theme.onSurface),
          icon: const Icon(Icons.close),
        ),
        if (lyricTextAlign != LyricTextAlign.right) const Spacer(),
      ],
    );
  }
}
