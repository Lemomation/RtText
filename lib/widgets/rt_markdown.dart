import 'package:flutter/material.dart';

/// Inline markdown for chat bubbles: **bold**, *italic*, `code`, plus
/// normalization of "* " / "- " list markers into bullets. Deliberately
/// tiny — no package dependency, no block layout; everything is TextSpans.
class RtMarkdownText extends StatelessWidget {
  const RtMarkdownText(this.data, {super.key, this.baseStyle});

  final String data;
  final TextStyle? baseStyle;

  static final _tokenPattern = RegExp(
    r'(\*\*[^*\n]+\*\*)' // bold
    r'|(\*[^*\n]+\*)' // italic
    r'|(`[^`\n]+`)', // inline code
    multiLine: true,
  );

  @override
  Widget build(BuildContext context) {
    final base = baseStyle ?? DefaultTextStyle.of(context).style;
    final bold = base.copyWith(fontWeight: FontWeight.w700);
    final italic = base.copyWith(fontStyle: FontStyle.italic);
    final code = base.copyWith(
      fontFamily: 'monospace',
      fontSize: (base.fontSize ?? 14) - 1,
      backgroundColor:
          DefaultTextStyle.of(context).style.color?.withValues(alpha: 0.10),
    );

    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in _tokenPattern.allMatches(data)) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: data.substring(cursor, match.start)));
      }
      final text = match.group(0)!;
      if (text.startsWith('**')) {
        spans.add(TextSpan(text: text.substring(2, text.length - 2), style: bold));
      } else if (text.startsWith('`')) {
        spans.add(TextSpan(text: text.substring(1, text.length - 1), style: code));
      } else {
        spans.add(TextSpan(text: text.substring(1, text.length - 1), style: italic));
      }
      cursor = match.end;
    }
    if (cursor < data.length) {
      spans.add(TextSpan(text: data.substring(cursor)));
    }

    return Text.rich(
      TextSpan(children: _withListMarkers(spans, base)),
    );
  }

  /// Rewrites leading "* " / "- " markers on line starts into "•  ".
  List<TextSpan> _withListMarkers(List<TextSpan> spans, TextStyle base) {
    final out = <TextSpan>[];
    var atLineStart = true;
    for (final span in spans) {
      final text = span.text;
      if (text == null || text.isEmpty) {
        out.add(span);
        continue;
      }
      final buffer = StringBuffer();
      for (var i = 0; i < text.length; i++) {
        if (atLineStart &&
            (text.startsWith('* ', i) || text.startsWith('- ', i))) {
          buffer.write('•  ');
          i++; // skip the marker char ('*' or '-'); the space is written
          atLineStart = false;
          continue;
        }
        final ch = text[i];
        buffer.write(ch);
        atLineStart = ch == '\n';
      }
      out.add(TextSpan(
        text: buffer.toString(),
        style: span.style,
        children: span.children,
      ));
    }
    return out;
  }
}
