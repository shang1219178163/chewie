import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
  late final ValueNotifier<double> rightVN = ValueNotifier<double>(-widget.drawerWidth);
  bool _disposed = false;

  bool get isVisible => !_disposed && rightVN.value == 0;

  @override
  void dispose() {
    _disposed = true;
    widget.controller?._detach(this);
    rightVN.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    widget.controller?._attach(this);
  }

  void onToggle() {
    if (_disposed) {
      return;
    }
    // 处于 build/paint 阶段时不能直接改 ValueNotifier（会触发 markNeedsBuild during build），
    // 推迟到帧后再切换。
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyToggle());
      return;
    }
    _applyToggle();
  }

  void _applyToggle() {
    if (_disposed) {
      return;
    }
    rightVN.value = rightVN.value == 0 ? -widget.drawerWidth : 0;
  }

  void onDismiss(double v) {
    if (_disposed) {
      return;
    }
    rightVN.value = -v;
  }

  @override
  void didUpdateWidget(covariant NSlideStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._detach(this);
      widget.controller?._attach(this);
    }
    if (oldWidget.drawerWidth != widget.drawerWidth) {
      onDismiss(widget.drawerWidth);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: rightVN,
      builder: (BuildContext context, double value, Widget? child) {
        return Stack(
          fit: StackFit.expand,
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
      child: widget.childBuilder(onToggle),
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

  bool get isVisible => _anchor?.isVisible ?? false;

  void onToggle() {
    _anchor?.onToggle();
  }
}
