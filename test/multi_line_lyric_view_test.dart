import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pure_player_lyric/component/foreground.dart';
import 'package:pure_player_lyric/component/multi_line_lyric_view.dart';
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
      child: const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 800, height: 420, child: MultiLineLyricView()),
        ),
      ),
    ),
  );

  testWidgets('renders snapshot lines and highlights the current line', (
    tester,
  ) async {
    final previousMode = textDisplayController.useVerticalDisplayMode;
    final previousRoman = textDisplayController.showRoman;
    final previousTranslation = textDisplayController.showLyricTranslation;
    addTearDown(() {
      textDisplayController.useVerticalDisplayMode = previousMode;
      textDisplayController.showRoman = previousRoman;
      textDisplayController.showLyricTranslation = previousTranslation;
      DesktopLyricController.instance.fullLines.value = const [];
    });
    textDisplayController.useVerticalDisplayMode = false;
    textDisplayController.showRoman = false;
    textDisplayController.showLyricTranslation = false;
    DesktopLyricController.instance.fullLines.value = const [
      FullLyricLine(1, 'first', null, null, 0, 3000, null),
      FullLyricLine(2, 'second', null, null, 3000, 3000, [
        LyricWord(0, 3000, 'second'),
      ]),
      FullLyricLine(3, 'third', null, null, 6000, 3000, null),
    ];
    DesktopLyricController.instance.lyricLine.value =
        const LyricLineChangedMessage(
          'second',
          Duration(seconds: 3),
          null,
          [LyricWord(0, 3000, 'second')],
          null,
          null,
          null,
          null,
          null,
          null,
          true,
          2,
        );

    await tester.pumpWidget(buildSubject());

    expect(find.byType(LyricTextDisplay), findsNWidgets(2));
    expect(find.byType(WordLyricText), findsOneWidget);
    expect(find.text('first'), findsNWidgets(2));
    expect(find.text('third'), findsNWidgets(2));
  });

  testWidgets('skips empty snapshot lines', (tester) async {
    DesktopLyricController.instance.fullLines.value = const [
      FullLyricLine(1, '', null, null, 0, 3000, null),
      FullLyricLine(2, 'visible', null, null, 3000, 3000, null),
    ];
    DesktopLyricController.instance.lyricLine.value =
        const LyricLineChangedMessage(
          'visible',
          Duration(seconds: 3),
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          false,
          2,
        );
    addTearDown(() {
      DesktopLyricController.instance.fullLines.value = const [];
    });

    await tester.pumpWidget(buildSubject());

    expect(find.text('visible'), findsNWidgets(2));
    expect(find.text(''), findsNothing);
  });

  testWidgets('wraps long horizontal lines within the viewport', (
    tester,
  ) async {
    final previousMode = textDisplayController.useVerticalDisplayMode;
    final previousRoman = textDisplayController.showRoman;
    final previousTranslation = textDisplayController.showLyricTranslation;
    final previousFontSize = textDisplayController.lyricFontSize;
    addTearDown(() {
      textDisplayController.useVerticalDisplayMode = previousMode;
      textDisplayController.showRoman = previousRoman;
      textDisplayController.showLyricTranslation = previousTranslation;
      textDisplayController.lyricFontSize = previousFontSize;
      DesktopLyricController.instance.fullLines.value = const [];
    });
    textDisplayController.useVerticalDisplayMode = false;
    textDisplayController.showRoman = false;
    textDisplayController.showLyricTranslation = false;
    textDisplayController.lyricFontSize = 22;
    const content =
        'This is a deliberately long lyric line that should wrap across multiple lines in the desktop lyric viewport.';
    DesktopLyricController.instance.fullLines.value = const [
      FullLyricLine(1, content, null, null, 0, 3000, null),
    ];
    DesktopLyricController.instance.lyricLine.value =
        const LyricLineChangedMessage(
          content,
          Duration(seconds: 3),
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          false,
          1,
        );

    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    final display = tester.getRect(find.byType(LyricTextDisplay));
    expect(display.width, 800);
    expect(display.height, greaterThan(22));
    expect(find.text(content), findsNWidgets(2));
  });

  testWidgets('wraps long word-by-word lines within the viewport', (
    tester,
  ) async {
    final previousMode = textDisplayController.useVerticalDisplayMode;
    final previousRoman = textDisplayController.showRoman;
    final previousTranslation = textDisplayController.showLyricTranslation;
    final previousFontSize = textDisplayController.lyricFontSize;
    addTearDown(() {
      textDisplayController.useVerticalDisplayMode = previousMode;
      textDisplayController.showRoman = previousRoman;
      textDisplayController.showLyricTranslation = previousTranslation;
      textDisplayController.lyricFontSize = previousFontSize;
      DesktopLyricController.instance.fullLines.value = const [];
    });
    textDisplayController.useVerticalDisplayMode = false;
    textDisplayController.showRoman = false;
    textDisplayController.showLyricTranslation = false;
    textDisplayController.lyricFontSize = 22;
    const content =
        'This is a deliberately long karaoke lyric line that should wrap across multiple lines in the desktop lyric viewport.';
    DesktopLyricController.instance.fullLines.value = const [
      FullLyricLine(1, content, null, null, 0, 3000, [
        LyricWord(0, 3000, content),
      ]),
    ];
    DesktopLyricController.instance.lyricLine.value =
        const LyricLineChangedMessage(
          content,
          Duration(seconds: 3),
          null,
          [LyricWord(0, 3000, content)],
          null,
          null,
          null,
          null,
          null,
          null,
          true,
          1,
        );

    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    final display = tester.getRect(find.byType(WordLyricText));
    expect(display.width, 800);
    expect(display.height, greaterThan(22));
  });

  testWidgets('aligns the complete row at the requested edge', (tester) async {
    final previousMode = textDisplayController.useVerticalDisplayMode;
    final previousAlign = textDisplayController.lyricTextAlign;
    final previousRoman = textDisplayController.showRoman;
    final previousTranslation = textDisplayController.showLyricTranslation;
    addTearDown(() {
      textDisplayController.useVerticalDisplayMode = previousMode;
      textDisplayController.lyricTextAlign = previousAlign;
      textDisplayController.showRoman = previousRoman;
      textDisplayController.showLyricTranslation = previousTranslation;
      DesktopLyricController.instance.fullLines.value = const [];
    });
    textDisplayController.useVerticalDisplayMode = false;
    textDisplayController.showRoman = false;
    textDisplayController.showLyricTranslation = false;
    DesktopLyricController.instance.fullLines.value = const [
      FullLyricLine(1, 'a', null, null, 0, 3000, null),
      FullLyricLine(2, 'a much longer line', null, null, 3000, 3000, null),
    ];
    DesktopLyricController.instance.lyricLine.value =
        const LyricLineChangedMessage(
          'a',
          Duration(seconds: 3),
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          false,
          1,
        );

    textDisplayController.lyricTextAlign = LyricTextAlign.left;
    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();
    var displays = find.byType(LyricTextDisplay);
    var first = tester.getRect(displays.at(0));
    var second = tester.getRect(displays.at(1));
    expect((first.left - second.left).abs(), lessThan(1));

    textDisplayController.lyricTextAlign = LyricTextAlign.right;
    textDisplayController.notifyListeners();
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    displays = find.byType(LyricTextDisplay);
    first = tester.getRect(displays.at(0));
    second = tester.getRect(displays.at(1));
    expect((first.right - second.right).abs(), lessThan(1));
  });

  testWidgets('aligns word-by-word and static rows to the same edge', (
    tester,
  ) async {
    final previousMode = textDisplayController.useVerticalDisplayMode;
    final previousAlign = textDisplayController.lyricTextAlign;
    final previousRoman = textDisplayController.showRoman;
    final previousTranslation = textDisplayController.showLyricTranslation;
    addTearDown(() {
      textDisplayController.useVerticalDisplayMode = previousMode;
      textDisplayController.lyricTextAlign = previousAlign;
      textDisplayController.showRoman = previousRoman;
      textDisplayController.showLyricTranslation = previousTranslation;
      DesktopLyricController.instance.fullLines.value = const [];
    });
    textDisplayController.useVerticalDisplayMode = false;
    textDisplayController.showRoman = false;
    textDisplayController.showLyricTranslation = false;
    DesktopLyricController.instance.fullLines.value = const [
      FullLyricLine(1, 'word by word', null, null, 0, 3000, [
        LyricWord(0, 3000, 'word by word'),
      ]),
      FullLyricLine(2, 'static row', null, null, 3000, 3000, null),
    ];
    DesktopLyricController.instance.lyricLine.value =
        const LyricLineChangedMessage(
          'word by word',
          Duration(seconds: 3),
          null,
          [LyricWord(0, 3000, 'word by word')],
          null,
          null,
          null,
          null,
          null,
          null,
          true,
          1,
        );

    for (final alignment in [LyricTextAlign.left, LyricTextAlign.right]) {
      textDisplayController.lyricTextAlign = alignment;
      textDisplayController.notifyListeners();
      await tester.pumpWidget(buildSubject());
      await tester.pumpAndSettle();
      final currentRect = tester.getRect(find.byType(WordLyricText));
      final staticRect = tester.getRect(find.byType(LyricTextDisplay).last);
      if (alignment == LyricTextAlign.left) {
        expect(currentRect.left, closeTo(staticRect.left, 0.5));
      } else {
        expect(currentRect.right, closeTo(staticRect.right, 0.5));
      }
    }
  });

  testWidgets('renders an interlude snapshot line as transition dots', (
    tester,
  ) async {
    DesktopLyricController.instance.fullLines.value = const [
      FullLyricLine(1, null, null, null, 0, 5000, null),
      FullLyricLine(2, 'visible', null, null, 5000, 3000, null),
    ];
    DesktopLyricController.instance.lyricLine.value =
        const LyricLineChangedMessage(
          '',
          Duration(seconds: 5),
          null,
          null,
          0,
          null,
          null,
          null,
          null,
          null,
          false,
          1,
        );
    addTearDown(() {
      DesktopLyricController.instance.fullLines.value = const [];
    });

    await tester.pumpWidget(buildSubject());

    expect(find.byType(LyricTransitionDots), findsOneWidget);
  });

  testWidgets('includes interlude height in the scroll layout', (tester) async {
    final previousMode = textDisplayController.useVerticalDisplayMode;
    final previousGap = textDisplayController.lineGap;
    addTearDown(() {
      textDisplayController.useVerticalDisplayMode = previousMode;
      textDisplayController.lineGap = previousGap;
      DesktopLyricController.instance.fullLines.value = const [];
    });
    textDisplayController.useVerticalDisplayMode = false;
    textDisplayController.lineGap = 4;
    DesktopLyricController.instance.fullLines.value = const [
      FullLyricLine(1, 'before', null, null, 0, 3000, null),
      FullLyricLine(2, null, null, null, 3000, 5000, null),
      FullLyricLine(3, 'after', null, null, 8000, 3000, null),
    ];
    DesktopLyricController.instance.lyricLine.value =
        const LyricLineChangedMessage(
          '',
          Duration(seconds: 5),
          null,
          null,
          0,
          null,
          null,
          null,
          null,
          null,
          false,
          2,
        );

    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();

    final itemRect = tester.getRect(
      find.byKey(const ValueKey('multi_line_item_2')),
    );
    final dotsRect = tester.getRect(find.byType(LyricTransitionDots));
    expect(
      itemRect.height,
      closeTo(dotsRect.height + textDisplayController.lineGap, 0.5),
    );
    final viewportRect = tester.getRect(find.byType(MultiLineLyricView));
    expect(itemRect.center.dy, closeTo(viewportRect.center.dy, 0.5));
  });

  testWidgets('centers the first and last current lines', (tester) async {
    final previousMode = textDisplayController.useVerticalDisplayMode;
    final previousRoman = textDisplayController.showRoman;
    final previousTranslation = textDisplayController.showLyricTranslation;
    addTearDown(() {
      textDisplayController.useVerticalDisplayMode = previousMode;
      textDisplayController.showRoman = previousRoman;
      textDisplayController.showLyricTranslation = previousTranslation;
      DesktopLyricController.instance.fullLines.value = const [];
    });
    textDisplayController.useVerticalDisplayMode = false;
    textDisplayController.showRoman = false;
    textDisplayController.showLyricTranslation = false;
    DesktopLyricController.instance.fullLines.value = const [
      FullLyricLine(1, 'first', null, null, 0, 3000, null),
      FullLyricLine(2, 'middle', null, null, 3000, 3000, null),
      FullLyricLine(3, 'last', null, null, 6000, 3000, null),
    ];
    DesktopLyricController.instance.lyricLine.value =
        const LyricLineChangedMessage(
          'first',
          Duration(seconds: 3),
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          false,
          1,
        );

    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();
    final viewportRect = tester.getRect(find.byType(MultiLineLyricView));
    var itemRect = tester.getRect(
      find.byKey(const ValueKey('multi_line_item_1')),
    );
    expect(itemRect.center.dy, closeTo(viewportRect.center.dy, 0.5));

    DesktopLyricController.instance.lyricLine.value =
        const LyricLineChangedMessage(
          'last',
          Duration(seconds: 3),
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          false,
          3,
        );
    await tester.pumpAndSettle();
    itemRect = tester.getRect(find.byKey(const ValueKey('multi_line_item_3')));
    expect(itemRect.center.dy, closeTo(viewportRect.center.dy, 0.5));
  });

  testWidgets('applies line gap between lyric groups', (tester) async {
    final previousMode = textDisplayController.useVerticalDisplayMode;
    final previousGap = textDisplayController.lineGap;
    final previousRoman = textDisplayController.showRoman;
    final previousTranslation = textDisplayController.showLyricTranslation;
    addTearDown(() {
      textDisplayController.useVerticalDisplayMode = previousMode;
      textDisplayController.lineGap = previousGap;
      textDisplayController.showRoman = previousRoman;
      textDisplayController.showLyricTranslation = previousTranslation;
      DesktopLyricController.instance.fullLines.value = const [];
    });
    textDisplayController.useVerticalDisplayMode = false;
    textDisplayController.lineGap = 0;
    textDisplayController.showRoman = false;
    textDisplayController.showLyricTranslation = true;
    DesktopLyricController.instance.fullLines.value = const [
      FullLyricLine(1, 'original', 'translation', null, 0, 3000, null),
      FullLyricLine(2, 'next', null, null, 3000, 3000, null),
    ];
    DesktopLyricController.instance.lyricLine.value =
        const LyricLineChangedMessage(
          'original',
          Duration(seconds: 3),
          'translation',
          null,
          null,
          null,
          null,
          null,
          null,
          null,
          false,
          1,
        );

    await tester.pumpWidget(buildSubject());
    await tester.pumpAndSettle();
    final compactItemRect = tester.getRect(
      find.byKey(const ValueKey('multi_line_item_1')),
    );
    final originalRect = tester.getRect(
      find.byWidgetPredicate(
        (widget) => widget is LyricTextDisplay && widget.text == 'original',
      ),
    );
    final translationRect = tester.getRect(
      find.byWidgetPredicate(
        (widget) => widget is LyricTextDisplay && widget.text == 'translation',
      ),
    );
    expect(
      compactItemRect.height,
      closeTo(originalRect.height + translationRect.height + 4, 0.5),
    );

    textDisplayController.lineGap = 12;
    textDisplayController.notifyListeners();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    final spacedItemRect = tester.getRect(
      find.byKey(const ValueKey('multi_line_item_1')),
    );
    expect(spacedItemRect.height - compactItemRect.height, closeTo(12, 0.5));
  });

  testWidgets('dims completed lines and can hide them without reflow', (
    tester,
  ) async {
    final previousMode = textDisplayController.useVerticalDisplayMode;
    final previousRoman = textDisplayController.showRoman;
    final previousTranslation = textDisplayController.showLyricTranslation;
    final previousHasPlayed = textDisplayController.hasSpecifiedPlayedColor;
    final previousPlayed = textDisplayController.playedColor;
    final previousHasUnplayed = textDisplayController.hasSpecifiedUnplayedColor;
    final previousUnplayed = textDisplayController.unplayedColor;
    final previousHidePlayed = textDisplayController.hidePlayedLines;
    addTearDown(() {
      textDisplayController.useVerticalDisplayMode = previousMode;
      textDisplayController.showRoman = previousRoman;
      textDisplayController.showLyricTranslation = previousTranslation;
      textDisplayController.hasSpecifiedPlayedColor = previousHasPlayed;
      textDisplayController.playedColor = previousPlayed;
      textDisplayController.hasSpecifiedUnplayedColor = previousHasUnplayed;
      textDisplayController.unplayedColor = previousUnplayed;
      textDisplayController.hidePlayedLines = previousHidePlayed;
      DesktopLyricController.instance.fullLines.value = const [];
    });
    textDisplayController.useVerticalDisplayMode = false;
    textDisplayController.showRoman = false;
    textDisplayController.showLyricTranslation = false;
    textDisplayController.hasSpecifiedPlayedColor = true;
    textDisplayController.playedColor = Colors.red;
    textDisplayController.hasSpecifiedUnplayedColor = true;
    textDisplayController.unplayedColor = Colors.grey;
    textDisplayController.hidePlayedLines = false;
    DesktopLyricController.instance.fullLines.value = const [
      FullLyricLine(1, 'played', null, null, 0, 3000, [
        LyricWord(0, 3000, 'played'),
      ]),
      FullLyricLine(2, 'current', null, null, 3000, 3000, [
        LyricWord(0, 3000, 'current'),
      ]),
      FullLyricLine(3, 'future', null, null, 6000, 3000, [
        LyricWord(0, 3000, 'future'),
      ]),
    ];
    DesktopLyricController.instance.lyricLine.value =
        const LyricLineChangedMessage(
          'current',
          Duration(seconds: 3),
          null,
          [LyricWord(0, 3000, 'current')],
          null,
          null,
          null,
          null,
          null,
          null,
          true,
          2,
        );

    await tester.pumpWidget(buildSubject());

    final displays = tester.widgetList<LyricTextDisplay>(
      find.byType(LyricTextDisplay),
    );
    expect(
      displays.singleWhere((display) => display.text == 'played').style.color,
      Colors.grey,
    );
    expect(
      displays.singleWhere((display) => display.text == 'future').style.color,
      Colors.grey,
    );
    final playedItem = find.byKey(const ValueKey('multi_line_item_1'));
    final playedOpacity = find.descendant(
      of: playedItem,
      matching: find.byType(Opacity),
    );
    expect(tester.widget<Opacity>(playedOpacity.first).opacity, 0.45);
    final originalSize = tester.getSize(playedItem);

    textDisplayController.hidePlayedLines = true;
    textDisplayController.notifyListeners();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.widget<Opacity>(playedOpacity.first).opacity, 0);
    expect(tester.getSize(playedItem), originalSize);
  });
}
