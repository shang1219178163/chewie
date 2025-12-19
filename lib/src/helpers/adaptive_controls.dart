import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';

class AdaptiveControls extends StatelessWidget {
  const AdaptiveControls({
    super.key,
    this.controlsController,
    this.onSpeed,
  });

  final CupertinoControlsController? controlsController;
  final VoidCallback? onSpeed;

  @override
  Widget build(BuildContext context) {
    switch (Theme.of(context).platform) {
      case TargetPlatform.android:
      case TargetPlatform.fuchsia:
        return const MaterialControls();

      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return const MaterialDesktopControls();

      case TargetPlatform.iOS:
        return CupertinoControls(
          controlsController: controlsController,
          onSpeed: onSpeed,
          backgroundColor: Color.fromRGBO(41, 41, 41, 0.7),
          iconColor: Color.fromARGB(255, 200, 200, 200),
        );
    }
  }
}
