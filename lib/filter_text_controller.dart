import 'package:flutter/material.dart';

final hiddenChars = {
  0x0011,
  0x0010,
  0x0001,
  0x0002,
  0x0003,
  0x0004,
  0x0005,
  0x0006,
  0x0007,
  0x0008,
  0x0009,
};

class FilterTextController extends TextEditingController {
  /// 需要隐藏的字符集合
  final Set<int> hiddenRunes;

  FilterTextController({
    String? text,
    required this.hiddenRunes,
  }) : super(text: text);

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final List<InlineSpan> children = [];

    final runes = text.runes;

    for (final r in runes) {
      if (hiddenRunes.contains(r)) {
        // ⭐ 完全不渲染 = 真0宽
        children.add(const TextSpan(text: ""));
      } else {
        children.add(TextSpan(text: String.fromCharCode(r)));
      }
    }

    return TextSpan(style: style, children: children);
  }
}
