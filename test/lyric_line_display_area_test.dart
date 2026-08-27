import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pure_player_lyric/component/foreground.dart';
import 'package:pure_player_lyric/component/lyric_line_display_area.dart';
import 'package:pure_player_lyric/component/lyric_line_view.dart';
import 'package:pure_player_lyric/component/lyric_text_display.dart';
import 'package:pure_player_lyric/component/lyric_transition_dots.dart';
import 'package:pure_player_lyric/component/word_lyric_text.dart';
import 'package:pure_player_lyric/desktop_lyric_controller.dart';
import 'package:pure_player_lyric/message.dart';

void main() {
  Widget buildSubject() => ChangeNotifierProvider.value(
    value: textDisplayController,
    child: ValueListenableProvider.value(
      value: DesktopLyricController.instance.theme,
      child: const MaterialApp(home: Scaffold(body: LyricLineDisplayArea())),
    ),
  );

  Widget buildLineViewSubject() => ChangeNotifierProvider.value(
    value: textDisplayController,
    child: ValueListenableProvider.value(
      value: DesktopLyricController.instance.theme,
      child: const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 800, height: 180, child: LyricLineView()),
        ),
      ),
    ),
  );

  testWidgets('switches translated lines without duplicate keys', (
    tester,
  ) async {
    DesktopLyricController.instance.lyricLine.value =
        const LyricLineChangedMessage('第一行', Duration(seconds: 3), '翻译一');

    await tester.pumpWidget(buildSubject());

    DesktopLyricController.instance.lyricLine.value =
        const LyricLineChangedMessage('第二行', Duration(seconds: 3), '翻译二');
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('allows translation placement on either side of the lyric', (
    tester,
  ) async {
    final previousVertical = textDisplayController.useVerticalDisplayMode;
    final previousRoman = textDisplayController.showRoman;
    final previousTranslation = textDisplayController.showLyricTranslation;
    final previousPosition = textDisplayController.translationPosition;
    addTearDown(() {
      textDisplayController.useVerticalDisplayMode = previousVertical;
      textDisplayController.showRoman = previousRoman;
      textDisplayController.showLyricTranslation = previousTranslation;
      textDisplayController.translationPosition = previousPosition;
    });
    textDisplayController.useVerticalDisplayMode = true;
    textDisplayController.showRoman = false;
    textDisplayController.showLyricTranslation = true;
    textDisplayController.translationPosition = TranslationPosition.beforeText;
    DesktopLyricController.instance.lyricLine.value =
        const LyricLineChangedMessage('原文', Duration(seconds: 3), '翻译');

    await tester.pumpWidget(buildSubject());
    expect(
      tester
          .widgetList<LyricTextDisplay>(find.byType(LyricTextDisplay))
          .map((widget) => widget.text),
      ['翻译', '原文'],
    );

    textDisplayController.applyConfig({'translationPosition': 1});
    await tester.pump();
    expect(
      tester
          .widgetList<LyricTextDisplay>(find.byType(LyricTextDisplay))
          .map((widget) => widget.text),
      ['原文', '翻译'],
    );
  });

  testWidgets('alternates the current line between double-line slots', (
    tester,
  ) async {
    final previousDoubleLine = textDisplayController.showDoubleLine;
    final previousAlignment = textDisplayController.lyricTextAlign;
    final previousRoman = textDisplayController.showRoman;
    final previousTranslation = textDisplayController.showLyricTranslation;
    addTearDown(() {
      textDisplayController.showDoubleLine = previousDoubleLine;
      textDisplayController.lyricTextAlign = previousAlignment;
      textDisplayController.showRoman = previousRoman;
      textDisplayController.showLyricTranslation = previousTranslation;
    });
    textDisplayController.showDoubleLine = true;
    textDisplayController.lyricTextAlign = LyricTextAlign.separated;
    textDisplayController.showRoman = false;
    textDisplayController.showLyricTranslation = false;
    DesktopLyricController.instance.lyricLine.value =
        LyricLineChangedMessage.fromJson({
          'content': '第一行',
          'length': const Duration(seconds: 3).inMicroseconds,
          'nextContent': '第二行',
        });

    await tester.pumpWidget(buildLineViewSubject());
    await tester.pump(const Duration(milliseconds: 701));
    final firstTop = tester.getTopLeft(
      find.byWidgetPredicate(
        (widget) => widget is LyricTextDisplay && widget.text == '第一行',
      ),
    );
    final secondTop = tester.getTopLeft(
      find.byWidgetPredicate(
        (widget) => widget is LyricTextDisplay && widget.text == '第二行',
      ),
    );
    expect(firstTop.dy, lessThan(secondTop.dy));

    DesktopLyricController.instance.lyricLine.value =
        LyricLineChangedMessage.fromJson({
          'content': '第二行',
          'length': const Duration(seconds: 3).inMicroseconds,
          'nextContent': '第三行',
        });
    await tester.pump(const Duration(milliseconds: 701));
    await tester.pump(const Duration(milliseconds: 701));
    final currentTop = tester.getTopLeft(
      find.byWidgetPredicate(
        (widget) => widget is LyricTextDisplay && widget.text == '第二行',
      ),
    );
    final nextTop = tester.getTopLeft(
      find.byWidgetPredicate(
        (widget) => widget is LyricTextDisplay && widget.text == '第三行',
      ),
    );
    expect(currentTop.dy, greaterThan(nextTop.dy));
  });

  testWidgets('slide transition does not hard-clip moving lyrics', (
    tester,
  ) async {
    final previousAnimation = textDisplayController.lyricAnimation;
    addTearDown(() {
      textDisplayController.lyricAnimation = previousAnimation;
    });
    textDisplayController.lyricAnimation = LyricSwitchAnimation.slideUp;
    DesktopLyricController.instance.lyricLine.value =
        const LyricLineChangedMessage('上一句', Duration(seconds: 3));
    await tester.pumpWidget(buildSubject());

    DesktopLyricController.instance.lyricLine.value =
        const LyricLineChangedMessage('下一句', Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.descendant(
        of: find.byType(LyricLineDisplayArea),
        matching: find.byType(ClipRect),
      ),
      findsNothing,
    );
  });

  testWidgets('double-line switch animates only the departed current line', (
    tester,
  ) async {
    final previousDoubleLine = textDisplayController.showDoubleLine;
    final previousAnimation = textDisplayController.lyricAnimation;
    final previousRoman = textDisplayController.showRoman;
    final previousTranslation = textDisplayController.showLyricTranslation;
    addTearDown(() {
      textDisplayController.showDoubleLine = previousDoubleLine;
      textDisplayController.lyricAnimation = previousAnimation;
      textDisplayController.showRoman = previousRoman;
      textDisplayController.showLyricTranslation = previousTranslation;
    });
    textDisplayController.showDoubleLine = true;
    textDisplayController.lyricAnimation = LyricSwitchAnimation.slideUp;
    textDisplayController.showRoman = false;
    textDisplayController.showLyricTranslation = false;
    DesktopLyricController.instance.lyricLine.value =
        LyricLineChangedMessage.fromJson({
          'content': '第一行',
          'length': const Duration(seconds: 3).inMicroseconds,
          'nextContent': '第二行',
        });

    await tester.pumpWidget(buildLineViewSubject());
    await tester.pump(const Duration(milliseconds: 701));
    DesktopLyricController.instance.lyricLine.value =
        LyricLineChangedMessage.fromJson({
          'content': '第二行',
          'length': const Duration(seconds: 3).inMicroseconds,
          'nextContent': '第三行',
        });
    await tester.pump(const Duration(milliseconds: 200));

    expect(
      find.byWidgetPredicate(
        (widget) => widget is LyricTextDisplay && widget.text == '第一行',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is LyricTextDisplay && widget.text == '第二行',
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 701));
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (widget) => widget is LyricTextDisplay && widget.text == '第一行',
      ),
      findsNothing,
    );
    expect(
      find.byWidgetPredicate(
        (widget) => widget is LyricTextDisplay && widget.text == '第三行',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'fade keeps the departing highlight frozen and removes it on time',
    (tester) async {
      final previousAnimation = textDisplayController.lyricAnimation;
      addTearDown(() {
        textDisplayController.lyricAnimation = previousAnimation;
      });
      textDisplayController.lyricAnimation = LyricSwitchAnimation.fade;
      DesktopLyricController.instance.isPlaying.value = true;
      DesktopLyricController.instance.lyricProgress.value =
          LyricProgressChangedMessage(
            1500,
            DateTime.now().millisecondsSinceEpoch,
            1,
            true,
            1,
          );
      DesktopLyricController.instance.lyricLine.value =
          LyricLineChangedMessage.fromJson({
            'content': 'first',
            'length': const Duration(seconds: 3).inMicroseconds,
            'words': [
              {'startMs': 0, 'lengthMs': 3000, 'content': 'first'},
            ],
            'isWordByWord': true,
            'lineId': 1,
          });
      await tester.pumpWidget(buildSubject());
      final initialPaint = tester.widget<CustomPaint>(
        find.descendant(
          of: find.byType(WordLyricText),
          matching: find.byType(CustomPaint),
        ),
      );
      final initialProgress =
          (initialPaint.painter as dynamic).progressMs as int;
      expect(initialProgress, greaterThanOrEqualTo(1500));

      DesktopLyricController.instance.lyricProgress.value =
          LyricProgressChangedMessage(
            0,
            DateTime.now().millisecondsSinceEpoch,
            1,
            true,
            2,
          );
      DesktopLyricController.instance.lyricLine.value =
          LyricLineChangedMessage.fromJson({
            'content': 'second',
            'length': const Duration(seconds: 3).inMicroseconds,
            'words': [
              {'startMs': 0, 'lengthMs': 3000, 'content': 'second'},
            ],
            'isWordByWord': true,
            'lineId': 2,
          });
      await tester.pump();

      final departingLine = find.byWidgetPredicate(
        (widget) => widget is WordLyricText && widget.line.lineId == 1,
      );
      final departingPaint = tester.widget<CustomPaint>(
        find.descendant(of: departingLine, matching: find.byType(CustomPaint)),
      );
      final frozenProgress =
          (departingPaint.painter as dynamic).progressMs as int;
      expect(frozenProgress, greaterThanOrEqualTo(initialProgress));

      await tester.pump(const Duration(milliseconds: 200));
      final midwayPaint = tester.widget<CustomPaint>(
        find.descendant(of: departingLine, matching: find.byType(CustomPaint)),
      );
      final midwayProgress = (midwayPaint.painter as dynamic).progressMs as int;
      expect(midwayProgress, frozenProgress);

      await tester.pump(const Duration(milliseconds: 501));
      expect(find.byType(WordLyricText), findsOneWidget);
    },
  );

  testWidgets('uses word rendering for an explicit word-by-word lyric', (
    tester,
  ) async {
    DesktopLyricController.instance.lyricLine.value =
        LyricLineChangedMessage.fromJson({
          'content': '逐字歌词',
          'length': const Duration(seconds: 3).inMicroseconds,
          'words': [
            {'startMs': 0, 'lengthMs': 3000, 'content': '逐字歌词'},
          ],
          'isWordByWord': true,
        });

    await tester.pumpWidget(buildSubject());

    expect(find.byType(WordLyricText), findsOneWidget);
  });

  testWidgets('uses line rendering when lyric type is explicitly line-based', (
    tester,
  ) async {
    DesktopLyricController.instance.lyricLine.value =
        LyricLineChangedMessage.fromJson({
          'content': '逐行歌词',
          'length': const Duration(seconds: 3).inMicroseconds,
          'words': [
            {'startMs': 0, 'lengthMs': 3000, 'content': '逐行歌词'},
          ],
          'isWordByWord': false,
        });

    await tester.pumpWidget(buildSubject());

    expect(find.byType(WordLyricText), findsNothing);
    expect(find.text('逐行歌词'), findsWidgets);
  });

  testWidgets('shows the same opening interlude threshold as the player', (
    tester,
  ) async {
    DesktopLyricController.instance.lyricLine.value =
        const LyricLineChangedMessage('', Duration(seconds: 4));

    await tester.pumpWidget(buildSubject());

    expect(find.byType(LyricTransitionDots), findsOneWidget);
  });

  test('infers word-by-word mode for legacy messages', () {
    final message = LyricLineChangedMessage.fromJson({
      'content': '旧消息',
      'length': const Duration(seconds: 3).inMicroseconds,
      'words': [
        {'startMs': 0, 'lengthMs': 3000, 'content': '旧消息'},
      ],
    });

    expect(message.isWordByWord, isTrue);
  });
}
