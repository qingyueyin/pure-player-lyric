import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pure_player_lyric/message.dart';

void main() {
  test('decodes fragmented and coalesced newline frames in order', () {
    final decoder = MessageFrameDecoder();
    final messages = <String>[];
    const first = ControlEventMessage(ControlEvent.pause);
    const second = ControlEventMessage(ControlEvent.nextAudio);
    final firstJson = first.buildMessageJson();
    final secondJson = second.buildMessageJson();

    decoder.add(firstJson.substring(0, 8), messages.add);
    decoder.add('${firstJson.substring(8)}\r\n$secondJson\n', messages.add);

    expect(messages, [firstJson, secondJson]);
  });

  test('bounds an unterminated frame buffer', () {
    var overflowCount = 0;
    final decoder = MessageFrameDecoder(
      maxBufferLength: 16,
      onOverflow: () => overflowCount++,
    );

    decoder.add(List.filled(40, 'x').join(), (_) {});

    expect(overflowCount, 1);
  });

  test('preserves desktop lyric layout config fields', () {
    final config = DesktopLyricConfigMessage.fromJson(const {
      'useVerticalDisplayMode': true,
      'showDoubleLine': true,
      'translationPosition': 0,
      'hidePlayedLines': true,
      'fontOpacity': 0.65,
    });

    expect(config.toJson(), {
      'useVerticalDisplayMode': true,
      'showDoubleLine': true,
      'translationPosition': 0,
      'hidePlayedLines': true,
      'fontOpacity': 0.65,
    });
  });

  test('round-trips the full lyric snapshot', () {
    const message = FullLyricChangedMessage([
      FullLyricLine(
        4,
        'line',
        'translation',
        'roman',
        1200,
        3000,
        [LyricWord(0, 1500, 'line')],
        2600,
        880,
      ),
    ]);

    final frame =
        jsonDecode(message.buildMessageJson()) as Map<String, dynamic>;
    final decoded = FullLyricChangedMessage.fromJson(
      frame['message'] as Map<String, dynamic>,
    );
    expect(decoded.lines.single.lineId, 4);
    expect(decoded.lines.single.words!.single.startMs, 0);
    expect(decoded.lines.single.translation, 'translation');
    expect(decoded.lines.single.switchStartMs, 880);
  });
}
