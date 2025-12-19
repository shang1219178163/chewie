//
//  NSlideStack.dart
//
//
//  Created by shang on 2025/12/15 14:52.
//  Copyright © 2025/12/15 shang. All rights reserved.
//

import 'package:flutter/material.dart';

typedef NSlideStackPopupBuilder = Widget Function(
  BuildContext context,
  bool fromRight,
  double drawerWidth,
  Widget Function(VoidCallback onToggle) drawerBuilder,
  Widget Function(VoidCallback onToggle) childBuilder,
);

class NSlideStack extends StatefulWidget {
  const NSlideStack({
    super.key,
    this.controller,
    this.fromRight = true,
    this.drawerWidth = 200,
    required this.drawerBuilder,
    required this.childBuilder,
  });

  final NSlideStackController? controller;

  final bool fromRight;
  final double drawerWidth;
  final Widget Function(VoidCallback onToggle) drawerBuilder;

  final Widget Function(VoidCallback onToggle) childBuilder;

  @override
  State<NSlideStack> createState() => _NSlideStackState();
}

class _NSlideStackState extends State<NSlideStack> {
  late final rightVN = ValueNotifier(-widget.drawerWidth);

  bool get isVisible => rightVN.value == 0;

  @override
  void dispose() {
    widget.controller?._detach(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
  }

  void onToggle() {
    rightVN.value = rightVN.value == 0 ? -widget.drawerWidth : 0;
  }

  void onDismiss(double v) {
    rightVN.value = -v;
  }

  @override
  void didUpdateWidget(covariant NSlideStack oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.drawerWidth != widget.drawerWidth ||
        oldWidget.drawerBuilder != widget.drawerBuilder ||
        oldWidget.fromRight != widget.fromRight ||
        oldWidget.childBuilder != widget.childBuilder) {
      if (oldWidget.drawerWidth != widget.drawerWidth) {
        onDismiss(widget.drawerWidth);
      }
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: rightVN,
      child: widget.childBuilder(onToggle),
      builder: (context, value, child) {
        return Stack(
          children: [
            child ?? const SizedBox(),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              right: widget.fromRight ? value : null,
              left: !widget.fromRight ? value : null,
              top: 0,
              bottom: 0,
              child: SizedBox(
                width: widget.drawerWidth,
                child: widget.drawerBuilder(onToggle),
              ),
            ),
          ],
        );
      },
    );
  }
}

class NSlideStackController {
  _NSlideStackState? _anchor;

  void _attach(_NSlideStackState anchor) {
    _anchor = anchor;
  }

  void _detach(_NSlideStackState anchor) {
    if (_anchor == anchor) {
      _anchor = null;
    }
  }

  bool get isVisible => _anchor!.isVisible;

  void onToggle() {
    assert(_anchor != null);
    _anchor!.onToggle();
  }
}
