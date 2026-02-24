import 'package:desktop_lyric/component/action_row.dart';
import 'package:desktop_lyric/component/lyric_line_view.dart';
import 'package:desktop_lyric/component/now_playing_info.dart';
import 'package:desktop_lyric/desktop_lyric_controller.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

final LYRIC_TEXT_KEY = GlobalKey();
final TRANSLATION_TEXT_KEY = GlobalKey();

final TEXT_DISPLAY_CONTROLLER = TextDisplayController();

bool ALWAYS_SHOW_ACTION_ROW = false;

List<Shadow> lyricTextShadows(Color color) {
  return const [];
}

Color lyricOutlineColor(Color color) {
  return Colors.black.withValues(alpha: 0.85);
}

double lyricOutlineWidth(double fontSize) {
  return (fontSize * 0.07).clamp(1.0, 2.0).toDouble();
}

Widget outlinedText({
  Key? key,
  required String text,
  required TextStyle style,
  required Color outlineColor,
  required double outlineWidth,
  TextAlign? textAlign,
  int? maxLines,
  TextOverflow? overflow,
  bool? softWrap,
}) {
  final strokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = outlineWidth
    ..color = outlineColor;

  return Stack(
    key: key,
    alignment: Alignment.center,
    children: [
      Text(
        text,
        style: style.copyWith(foreground: strokePaint, shadows: const []),
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        softWrap: softWrap,
      ),
      Text(
        text,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
        softWrap: softWrap,
      ),
    ],
  );
}

FontWeight lyricFontWeightFromInt(int weight) {
  final clamped = weight.clamp(100, 900);
  return switch (clamped) {
    100 => FontWeight.w100,
    200 => FontWeight.w200,
    300 => FontWeight.w300,
    400 => FontWeight.w400,
    500 => FontWeight.w500,
    600 => FontWeight.w600,
    700 => FontWeight.w700,
    800 => FontWeight.w800,
    900 => FontWeight.w900,
    _ => FontWeight.values[((clamped / 100).round().clamp(1, 9)) - 1],
  };
}

enum LyricTextAlign {
  left,
  center,
  right,
}

class TextDisplayController extends ChangeNotifier {
  double lyricFontSize = 22.0;
  double translationFontSize = 18.0;
  int lyricFontWeight = 700;
  bool showLyricTranslation = true;
  bool showNowPlayingInfo = true;
  LyricTextAlign lyricTextAlign = LyricTextAlign.center;

  /// true: 使用指定的颜色
  /// false: 跟随播放器主题（默认）
  bool hasSpecifiedColor = false;
  Color specifiedColor = Color(DesktopLyricController.instance.theme.value.primary);

  void increaseLyricFontSize() {
    if (lyricFontSize >= 48) return;
    lyricFontSize += 2;
    translationFontSize = (lyricFontSize - 4).clamp(12, 44).toDouble();
    notifyListeners();
  }

  void decreaseLyricFontSize() {
    if (lyricFontSize <= 16) return;
    lyricFontSize -= 2;
    translationFontSize = (lyricFontSize - 4).clamp(12, 44).toDouble();
    notifyListeners();
  }

  void switchLyricTextAlign() {
    lyricTextAlign = switch (lyricTextAlign) {
      LyricTextAlign.left => LyricTextAlign.center,
      LyricTextAlign.center => LyricTextAlign.right,
      LyricTextAlign.right => LyricTextAlign.left,
    };
    notifyListeners();
  }

  void toggleLyricTranslation() {
    showLyricTranslation = !showLyricTranslation;
    notifyListeners();
  }

  void toggleNowPlayingInfo() {
    showNowPlayingInfo = !showNowPlayingInfo;
    notifyListeners();
  }

  void setFontWeight(int weight) {
    lyricFontWeight = weight.clamp(100, 900);
    notifyListeners();
  }

  void increaseFontWeight({bool smallStep = false}) {
    final step = smallStep ? 10 : 100;
    setFontWeight(lyricFontWeight + step);
  }

  void decreaseFontWeight({bool smallStep = false}) {
    final step = smallStep ? 10 : 100;
    setFontWeight(lyricFontWeight - step);
  }

  /// 指定字体颜色
  void spcifiyColor(Color color) {
    specifiedColor = color;
    hasSpecifiedColor = true;
    notifyListeners();
  }

  /// 让歌词颜色跟随播放器主题
  void usePlayerTheme() {
    hasSpecifiedColor = false;
    notifyListeners();
  }
}

class DesktopLyricForeground extends StatelessWidget {
  final bool isHovering;
  const DesktopLyricForeground({super.key, required this.isHovering});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: ChangeNotifierProvider.value(
        value: TEXT_DISPLAY_CONTROLLER,
        child: Consumer<TextDisplayController>(
          builder: (context, textDisplayController, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: isHovering || ALWAYS_SHOW_ACTION_ROW
                    ? const RepaintBoundary(child: ActionRow())
                    : SizedBox(
                        height: 40,
                        width: double.infinity,
                        child: textDisplayController.showNowPlayingInfo
                            ? const RepaintBoundary(child: NowPlayingInfo())
                            : const SizedBox.shrink(),
                      ),
              ),
              const SizedBox(height: 8),
              const Expanded(child: LyricLineView()),
            ],
          ),
        ),
      ),
    );
  }
}
