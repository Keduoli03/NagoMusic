import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final double velocity; // pixels per second
  final double blankSpace;

  const MarqueeText(
    this.text, {
    super.key,
    this.style,
    this.velocity = 30.0,
    this.blankSpace = 50.0,
  });

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> with SingleTickerProviderStateMixin {
  late final ScrollController _scrollController;
  late final Ticker _ticker;
  double _textWidth = 0.0;
  double _containerWidth = 0.0;
  
  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _ticker = createTicker(_tick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _tick(Duration elapsed) {
    if (!_scrollController.hasClients) return;
    
    final cycleLength = _textWidth + widget.blankSpace;
    if (cycleLength <= 0) return;

    // Calculate position based on time
    // We want position = (velocity * time) % cycleLength
    final milliseconds = elapsed.inMilliseconds;
    final pixels = (milliseconds / 1000.0) * widget.velocity;
    final offset = pixels % cycleLength;
    
    _scrollController.jumpTo(offset);
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = widget.style ?? DefaultTextStyle.of(context).style;
    
    // Measure text
    final textPainter = TextPainter(
      text: TextSpan(text: widget.text, style: textStyle),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    
    _textWidth = textPainter.width;

    return LayoutBuilder(
      builder: (context, constraints) {
        _containerWidth = constraints.maxWidth;
        final shouldScroll = _textWidth > _containerWidth;

        if (!shouldScroll) {
          if (_ticker.isActive) _ticker.stop();
          return Text(
            widget.text,
            style: textStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          );
        }

        if (!_ticker.isActive) _ticker.start();

        // Ensure we have enough copies to cover the screen plus one cycle
        // But for the seamless loop (0 to cycleLength), we really just need 
        // to see the second copy start appearing as the first one leaves.
        // A safe bet is 2 copies if textWidth > containerWidth (which it is).
        // Actually, if text is huge, 2 copies is fine.
        // If text is slightly larger than container, 2 copies is fine.
        
        return SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          child: Row(
            children: [
              Text(widget.text, style: textStyle),
              SizedBox(width: widget.blankSpace),
              Text(widget.text, style: textStyle),
              SizedBox(width: widget.blankSpace),
              // Add a third just in case of very wide screens vs text? 
              // Usually 2 is enough for the "jump back" logic to work visually 
              // provided container isn't wider than text + space + text.
              // Since text > container, 2 copies = 2 * text + 2 * space > 2 * container.
              // So 2 copies always cover the view.
            ],
          ),
        );
      },
    );
  }
}
