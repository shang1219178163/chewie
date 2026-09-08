import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'n_slide_stack.dart';

enum NChewieDrawerEvent {
  speed('倍速'),
  series('剧集');

  const NChewieDrawerEvent(this.desc);

  final String desc;
}

/// 控制 [NChewieView] 切集 / 重建。
class NChewieViewController {
  Future<bool> Function(int index, {bool recreateController})? _switchVideo;
  int Function()? _currentIndex;
  ChewieController? Function()? _chewieController;

  void _bind({
    required Future<bool> Function(int index, {bool recreateController}) switchVideo,
    required int Function() currentIndex,
    required ChewieController? Function() chewieController,
  }) {
    _switchVideo = switchVideo;
    _currentIndex = currentIndex;
    _chewieController = chewieController;
  }

  void _unbind() {
    _switchVideo = null;
    _currentIndex = null;
    _chewieController = null;
  }

  int get currentIndex => _currentIndex?.call() ?? 0;

  ChewieController? get chewieController => _chewieController?.call();

  Future<bool> switchVideo(int index, {bool recreateController = false}) {
    return _switchVideo?.call(index, recreateController: recreateController) ?? Future<bool>.value(false);
  }
}

/// 带侧栏剧集 / 倍速的 Chewie 播放视图。
///
/// [items] 为泛型视频列表；[urlOf] 从条目中取出播放地址。
class NChewieView<T> extends StatefulWidget {
  const NChewieView({
    super.key,
    required this.items,
    required this.urlOf,
    this.titleOf,
    this.initialIndex = 0,
    this.controller,
    this.aspectRatio = 16 / 9,
    this.autoPlay = true,
    this.looping = true,
    this.playbackSpeeds = const [0.5, 1.0, 1.25, 1.5, 2.0],
    this.progressIndicatorDelay,
    this.onIndexChanged,
    this.onLoadFailed,
  });

  final List<T> items;

  /// 从泛型条目解析视频 URL。
  final String Function(T item) urlOf;

  /// 侧栏剧集标题；默认 `视频 ${index + 1}`。
  final String Function(T item, int index)? titleOf;

  final int initialIndex;
  final NChewieViewController? controller;
  final double aspectRatio;
  final bool autoPlay;
  final bool looping;
  final List<double> playbackSpeeds;
  final Duration? progressIndicatorDelay;
  final ValueChanged<int>? onIndexChanged;
  final void Function(int index, Object error)? onLoadFailed;

  @override
  State<NChewieView<T>> createState() => _NChewieViewState<T>();
}

class _NChewieViewState<T> extends State<NChewieView<T>> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  CupertinoControlsController? _cupertinoControlsController;

  final slideStackController = NSlideStackController();
  final fullScreenSlideStackController = NSlideStackController();
  final _chewieKey = GlobalKey();
  final drawerEventVN = ValueNotifier(NChewieDrawerEvent.speed);
  final currPlayIndexVN = ValueNotifier<int>(0);

  Future<void> _switchOperation = Future<void>.value();
  bool _isSwitching = false;

  int get currPlayIndex => currPlayIndexVN.value;

  @override
  void initState() {
    super.initState();
    widget.controller?._bind(
      switchVideo: switchVideo,
      currentIndex: () => currPlayIndex,
      chewieController: () => _chewieController,
    );
    final int index = widget.initialIndex.clamp(0, widget.items.isEmpty ? 0 : widget.items.length - 1);
    if (widget.items.isNotEmpty) {
      switchVideo(index, recreateController: true);
    }
  }

  @override
  void didUpdateWidget(covariant NChewieView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._unbind();
      widget.controller?._bind(
        switchVideo: switchVideo,
        currentIndex: () => currPlayIndex,
        chewieController: () => _chewieController,
      );
    }
  }

  @override
  void dispose() {
    widget.controller?._unbind();
    drawerEventVN.dispose();
    currPlayIndexVN.dispose();
    _videoPlayerController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  String _urlAt(int index) => widget.urlOf(widget.items[index]);

  String _titleAt(int index) {
    final titleOf = widget.titleOf;
    if (titleOf != null) {
      return titleOf(widget.items[index], index);
    }
    return '视频 ${index + 1}';
  }

  /// 串行切集：先释放旧播放器，再创建新播放器。
  Future<bool> switchVideo(int index, {bool recreateController = false}) {
    if (index < 0 || index >= widget.items.length) {
      return Future<bool>.value(false);
    }
    if (!recreateController && index == currPlayIndexVN.value) {
      return Future<bool>.value(false);
    }
    final Completer<bool> completer = Completer<bool>();
    if (!_isSwitching && mounted) {
      _isSwitching = true;
      setState(() {});
    }
    _switchOperation = _switchOperation.then((_) async {
      if (!recreateController && index == currPlayIndexVN.value) {
        completer.complete(false);
        return;
      }
      try {
        completer.complete(
          await _performSwitchVideo(index, recreateController: recreateController),
        );
      } on Object catch (error, stack) {
        debugPrint('NChewieView switchVideo failed: $error\n$stack');
        if (!completer.isCompleted) {
          completer.complete(false);
        }
      }
    });
    return completer.future;
  }

  Future<bool> _performSwitchVideo(int index, {bool recreateController = false}) async {
    _isSwitching = true;
    if (mounted) {
      setState(() {});
    }
    final VideoPlayerController? oldPlayer = _videoPlayerController;
    try {
      try {
        await oldPlayer?.pause();
      } catch (_) {}
      await WidgetsBinding.instance.endOfFrame;
      try {
        await oldPlayer?.dispose();
      } catch (_) {}
      _videoPlayerController = null;

      final VideoPlayerController player = VideoPlayerController.networkUrl(Uri.parse(_urlAt(index)));
      await player.initialize();
      if (!mounted) {
        await player.dispose();
        return false;
      }
      _videoPlayerController = player;
      if (_chewieController == null || recreateController) {
        _cupertinoControlsController = null;
        _createChewieController();
      } else {
        await _chewieController!.replaceVideoPlayerController(
          player,
          autoPlay: widget.autoPlay,
        );
      }
      currPlayIndexVN.value = index;
      widget.onIndexChanged?.call(index);
      return true;
    } on Object catch (error, stack) {
      debugPrint('NChewieView switchVideo error: $error\n$stack');
      widget.onLoadFailed?.call(index, error);
      if (mounted && widget.onLoadFailed == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_titleAt(index)} 加载失败'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    } finally {
      if (mounted) {
        _isSwitching = false;
        setState(() {});
      }
    }
  }

  void _createChewieController() {
    final CupertinoControlsController controls = _cupertinoControlsController ??= CupertinoControlsController();
    final ChewieController? oldChewie = _chewieController;
    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController!,
      aspectRatio: widget.aspectRatio,
      autoPlay: widget.autoPlay,
      looping: widget.looping,
      progressIndicatorDelay: widget.progressIndicatorDelay,
      additionalOptions: (BuildContext context) {
        return <OptionItem>[
          OptionItem(
            onTap: (BuildContext context) {
              switchVideo((currPlayIndexVN.value + 1) % widget.items.length);
            },
            iconData: Icons.live_tv_sharp,
            title: 'Toggle Video Src',
          ),
        ];
      },
      hideControlsTimer: const Duration(seconds: 3),
      showControls: true,
      allowPlaySkip: false,
      allowFullScreen: true,
      deviceOrientationsOnEnterFullScreen: const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
      deviceOrientationsAfterFullScreen: const [
        DeviceOrientation.portraitUp,
      ],
      routePageBuilder: (
        BuildContext context,
        Animation<double> animation,
        Animation<double> secondaryAnimation,
        ChewieControllerProvider controllerProvider,
      ) {
        if (fullScreenSlideStackController.isVisible) {
          fullScreenSlideStackController.onToggle();
        }
        return AnimatedBuilder(
          animation: animation,
          builder: (BuildContext context, Widget? child) {
            return Scaffold(
              resizeToAvoidBottomInset: false,
              body: _buildSlideHost(
                controller: fullScreenSlideStackController,
                childBuilder: (_) => Container(
                  alignment: Alignment.center,
                  color: Colors.black,
                  child: controllerProvider,
                ),
              ),
            );
          },
        );
      },
      playbackSpeeds: widget.playbackSpeeds,
      spacerBuilder: (
        BuildContext context,
        PlayerNotifier notifier,
        double barHeight,
        EdgeInsets buttonPadding,
        Color backgroundColor,
        Color iconColor,
      ) {
        final stackController =
            ChewieController.of(context).isFullScreen ? fullScreenSlideStackController : slideStackController;
        return Align(
          alignment: Alignment.bottomRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 100),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final NChewieDrawerEvent e in NChewieDrawerEvent.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: CupertinoControlsExt.button(
                      notifier: notifier,
                      barHeight: barHeight,
                      buttonPadding: buttonPadding,
                      backgroundColor: backgroundColor,
                      child: Text(e.desc, style: TextStyle(color: iconColor)),
                      onTap: () {
                        drawerEventVN.value = e;
                        stackController.onToggle();
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
      onSpeed: () {
        drawerEventVN.value = NChewieDrawerEvent.speed;
        _chewieController?.cupertinoControlsController?.notifier.hideStuff = true;
        final stackController =
            (_chewieController?.isFullScreen ?? false) ? fullScreenSlideStackController : slideStackController;
        stackController.onToggle();
      },
      cupertinoControlsController: controls,
    );
    oldChewie?.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? player = _chewieController?.videoPlayerController;
    final bool isVideoReady = player != null && player.value.isInitialized && !player.value.hasError;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          if (_chewieController != null)
            Offstage(
              offstage: _chewieController!.isFullScreen || _isSwitching || !isVideoReady,
              child: _buildSlideHost(
                controller: slideStackController,
                childBuilder: (_) => Chewie(
                  key: _chewieKey,
                  controller: _chewieController!,
                ),
              ),
            ),
          if (_isSwitching || !isVideoReady)
            const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                Text('Loading', style: TextStyle(color: Colors.white)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildSlideHost({
    required NSlideStackController controller,
    required Widget Function(VoidCallback onToggle) childBuilder,
  }) {
    return NSlideStack(
      controller: controller,
      drawerWidth: MediaQuery.orientationOf(context) == Orientation.portrait ? 150 : 200,
      drawerBuilder: (VoidCallback onToggle) => TapRegion(
        onTapOutside: (_) {
          if (controller.isVisible) {
            controller.onToggle();
          }
        },
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.6),
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            removeBottom: true,
            removeLeft: true,
            removeRight: true,
            child: ValueListenableBuilder<NChewieDrawerEvent>(
              valueListenable: drawerEventVN,
              builder: (BuildContext context, NChewieDrawerEvent value, Widget? child) {
                if (value == NChewieDrawerEvent.series) {
                  return _buildSeriesList(onToggle: onToggle);
                }
                return _buildSpeedView(onToggle: onToggle);
              },
            ),
          ),
        ),
      ),
      childBuilder: childBuilder,
    );
  }

  Widget _buildSeriesList({VoidCallback? onToggle}) {
    return ValueListenableBuilder<int>(
      valueListenable: currPlayIndexVN,
      builder: (BuildContext context, int selectedIndex, Widget? child) {
        final Color highlight = Colors.white.withValues(alpha: 0.12);
        return Scrollbar(
          child: ListView.separated(
            itemCount: widget.items.length,
            separatorBuilder: (_, __) => Divider(color: Colors.white.withValues(alpha: 0.25), height: 1),
            itemBuilder: (BuildContext context, int i) {
              final bool isSelected = i == selectedIndex;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  if (i == currPlayIndexVN.value) {
                    onToggle?.call();
                    return;
                  }
                  final bool ok = await switchVideo(i);
                  if (ok) {
                    onToggle?.call();
                  }
                },
                child: Container(
                  height: 60,
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  color: isSelected ? highlight : Colors.transparent,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _titleAt(i),
                          style: TextStyle(
                            color: isSelected ? Colors.amber : Colors.white,
                          ),
                        ),
                      ),
                      if (isSelected) const Icon(Icons.play_arrow, color: Colors.amber, size: 20),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildSpeedView({VoidCallback? onToggle}) {
    final List<double> items = _chewieController?.playbackSpeeds ?? widget.playbackSpeeds;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          for (final double speed in items)
            Expanded(
              child: GestureDetector(
                onTap: () async {
                  await _chewieController?.videoPlayerController.setPlaybackSpeed(speed);
                  onToggle?.call();
                },
                child: Center(
                  child: Text(
                    '${speed}x',
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
