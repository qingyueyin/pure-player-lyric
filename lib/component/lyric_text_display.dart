import 'package:pure_player_lyric/component/foreground.dart';
import 'package:flutter/material.dart';

final RegExp _alphanumericChar = RegExp(
  r'''^[A-Za-z0-9 !"'?.,:;()\[\]\-《》「」（）：/“”]+$''',
);

/// 竖排模式下逐字拆分的歌词文本，英文和数字旋转 90 度
class LyricTextDisplay extends StatelessWidget {
  final String text;
  final TextStyle style;
  final bool vertical;
  final Color outlineColor;
  final double outlineWidth;
  final bool enableOutline;
  final TextAlign textAlign;
  final bool wrap;
  final double? maxWidth;

  const LyricTextDisplay({
    super.key,
    required this.text,
    required this.style,
    this.vertical = false,
    this.outlineColor = Colors.black,
    this.outlineWidth = 2.0,
    this.enableOutline = true,
    this.textAlign = TextAlign.center,
    this.wrap = false,
    this.maxWidth,
  });

  Widget _buildText(String char) {
    return outlinedText(
      text: char,
      style: style,
      outlineColor: outlineColor,
      outlineWidth: outlineWidth,
      textAlign: textAlign,
      maxLines: wrap ? null : 1,
      overflow: wrap ? TextOverflow.visible : TextOverflow.clip,
      softWrap: wrap,
      enableOutline: enableOutline,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!vertical) {
      final child = _buildText(text);
      if (maxWidth != null && maxWidth!.isFinite && maxWidth! > 0) {
        return SizedBox(width: maxWidth, child: child);
      }
      return child;
    }
    if (text.length == 1 && !_alphanumericChar.hasMatch(text)) {
      return _buildText(text);
    }
    final mainAxisAlignment = switch (textAlign) {
      TextAlign.left || TextAlign.start => MainAxisAlignment.start,
      TextAlign.center => MainAxisAlignment.center,
      TextAlign.right || TextAlign.end => MainAxisAlignment.end,
      _ => MainAxisAlignment.start,
    };
    return Flex(
      direction: Axis.vertical,
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final char in text.split(''))
          if (_alphanumericChar.hasMatch(char))
            RotatedBox(quarterTurns: 1, child: _buildText(char))
          else
            _buildText(char),
      ],
    );
  }
}
