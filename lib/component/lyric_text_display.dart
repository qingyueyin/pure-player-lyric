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

  const LyricTextDisplay({
    super.key,
    required this.text,
    required this.style,
    this.vertical = false,
    this.outlineColor = Colors.black,
    this.outlineWidth = 2.0,
    this.enableOutline = true,
    this.textAlign = TextAlign.center,
  });

  Widget _buildText(String char) {
    return outlinedText(
      text: char,
      style: style,
      outlineColor: outlineColor,
      outlineWidth: outlineWidth,
      textAlign: textAlign,
      maxLines: 1,
      overflow: TextOverflow.clip,
      softWrap: false,
      enableOutline: enableOutline,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!vertical) {
      return _buildText(text);
    }
    if (text.length == 1 && !_alphanumericChar.hasMatch(text)) {
      return _buildText(text);
    }
    return Flex(
      direction: Axis.vertical,
      mainAxisAlignment: MainAxisAlignment.center,
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