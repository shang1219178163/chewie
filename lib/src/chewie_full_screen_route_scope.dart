import 'package:flutter/material.dart';

/// 标记当前 [PlayerWithControls] 处于全屏 Route 中。
class ChewieFullScreenRouteScope extends InheritedWidget {
  const ChewieFullScreenRouteScope({
    super.key,
    required super.child,
  });

  static bool isFullScreenRoute(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ChewieFullScreenRouteScope>() != null;
  }

  @override
  bool updateShouldNotify(ChewieFullScreenRouteScope oldWidget) {
    return false;
  }
}
