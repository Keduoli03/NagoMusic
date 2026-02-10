import 'dart:async';

import 'package:flutter/material.dart';

import '../common/alphabet_indexer.dart';

class MediaListView extends StatefulWidget {
  final ScrollController controller;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double itemExtent;
  final EdgeInsetsGeometry? padding;
  final bool isLoading;
  final String emptyText;
  final Widget? emptyWidget;
  final Widget? loadingWidget;
  final Widget? floatingButton;
  final double bottomInset;
  final String Function(int index)? indexLabelBuilder;

  const MediaListView({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.itemBuilder,
    required this.itemExtent,
    this.padding,
    this.isLoading = false,
    this.emptyText = '暂无数据',
    this.emptyWidget,
    this.loadingWidget,
    this.floatingButton,
    this.bottomInset = 0,
    this.indexLabelBuilder,
  });

  @override
  State<MediaListView> createState() => _MediaListViewState();
}

class _MediaListViewState extends State<MediaListView> {
  String? _indexPreviewLetter;
  bool _indexPreviewVisible = false;
  Timer? _indexPreviewTimer;

  @override
  void dispose() {
    _indexPreviewTimer?.cancel();
    super.dispose();
  }

  void _activateIndexPreview(String letter) {
    _indexPreviewTimer?.cancel();
    final changed = _indexPreviewLetter != letter;
    if (_indexPreviewVisible && !changed) return;
    setState(() {
      _indexPreviewLetter = letter;
      _indexPreviewVisible = true;
    });
  }

  void _scheduleHideIndexPreview() {
    _indexPreviewTimer?.cancel();
    _indexPreviewTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() {
        _indexPreviewVisible = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return widget.loadingWidget ?? const Center(child: CircularProgressIndicator());
    }

    if (widget.itemCount == 0) {
      return widget.emptyWidget ?? Center(child: Text(widget.emptyText));
    }

    final padding = widget.padding ??
        EdgeInsets.only(right: 4, bottom: widget.bottomInset);
    final showIndexBar = widget.indexLabelBuilder != null;

    return Stack(
      children: [
        ListView.builder(
          controller: widget.controller,
          itemExtent: widget.itemExtent,
          padding: padding,
          itemCount: widget.itemCount,
          itemBuilder: widget.itemBuilder,
        ),
        if (showIndexBar)
          Positioned(
            right: 36,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _indexPreviewVisible && _indexPreviewLetter != null ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _indexPreviewLetter == null
                      ? const SizedBox.shrink()
                      : IndexPreview(
                          text: _indexPreviewLetter!,
                          visible: _indexPreviewVisible,
                        ),
                ),
              ),
            ),
          ),
        if (showIndexBar)
          Positioned(
            right: 2,
            top: 4,
            bottom: 4,
            child: DraggableScrollbar(
              controller: widget.controller,
              itemCount: widget.itemCount,
              itemExtent: widget.itemExtent,
              getLabel: widget.indexLabelBuilder!,
              onIndexChanged: _activateIndexPreview,
              onDragEnd: _scheduleHideIndexPreview,
            ),
          ),
        if (widget.floatingButton != null)
          Positioned(
            right: 24,
            bottom: widget.bottomInset,
            child: widget.floatingButton!,
          ),
      ],
    );
  }
}
