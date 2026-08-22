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
    });

    expect(config.toJson(), {
      'useVerticalDisplayMode': true,
      'showDoubleLine': true,
      'translationPosition': 0,
    });
  });
}
