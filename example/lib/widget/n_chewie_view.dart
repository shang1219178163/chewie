import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../video/native_video_player_pool.dart';
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
    return _switchVideo?.call(index, recreateController: recreateController) ??
        Future<bool>.value(false);
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
    this.activeColor = Colors.amber,
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

  /// 剧集 / 倍速侧栏选中高亮色。
  final Color activeColor;
  final Duration? progressIndicatorDelay;
  final ValueChanged<int>? onIndexChanged;
  final void Function(int index, Object error)? onLoadFailed;

  @override
  State<NChewieView<T>> createState() => _NChewieViewState<T>();
}

class _NChewieViewState<T> extends State<NChewieView<T>> {
  ChewieController? _chewieController;
  CupertinoControlsController? _cupertinoControlsController;

  final slideStackController = NSlideStackController();
  final fullScreenSlideStackController = NSlideStackController();
  final _videoPlayerPool = NativeVideoPlayerPool();
  final drawerEventVN = ValueNotifier(NChewieDrawerEvent.speed);
  final currPlayIndexVN = ValueNotifier<int>(0);

  Future<void> _switchOperation = Future<void>.value();
  bool _isSwitching = false;
  bool _wasFullScreen = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _bindController(widget.controller);
    if (widget.items.isNotEmpty) {
      final int index = widget.initialIndex.clamp(0, widget.items.length - 1);
      switchVideo(index, recreateController: true);
    }
  }

  @override
  void didUpdateWidget(covariant NChewieView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?._unbind();
      _bindController(widget.controller);
    }
    if (oldWidget.items != widget.items || oldWidget.urlOf != widget.urlOf) {
      _onItemsChanged();
    }
  }

  @override
  void dispose() {
    _closed = true;
    widget.controller?._unbind();
    drawerEventVN.dispose();
    currPlayIndexVN.dispose();
    _chewieController?.removeListener(_onChewieFullScreenChanged);
    unawaited(_videoPlayerPool.releaseAll());
    _chewieController?.dispose();
    super.dispose();
  }

  void _bindController(NChewieViewController? controller) {
    controller?._bind(
      switchVideo: switchVideo,
      currentIndex: () => currPlayIndexVN.value,
      chewieController: () => _chewieController,
    );
  }

  void _onItemsChanged() {
    if (widget.items.isEmpty) {
      _chewieController?.removeListener(_onChewieFullScreenChanged);
      unawaited(_videoPlayerPool.releaseAll());
      _chewieController?.dispose();
      _chewieController = null;
      _cupertinoControlsController = null;
      if (mounted) {
        setState(() {});
      }
      return;
    }
    final int next = currPlayIndexVN.value.clamp(0, widget.items.length - 1);
    switchVideo(next, recreateController: true);
  }

  String _urlAt(int index) => widget.urlOf(widget.items[index]);

  String _titleAt(int index) =>
      widget.titleOf?.call(widget.items[index], index) ?? '视频 ${index + 1}';

  /// 串行切集，避免并发创建多个原生播放器。
  Future<bool> switchVideo(int index, {bool recreateController = false}) {
    if (_closed || index < 0 || index >= widget.items.length) {
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
      if (_closed || (!recreateController && index == currPlayIndexVN.value)) {
        if (mounted && _isSwitching) {
          _isSwitching = false;
          setState(() {});
        }
        completer.complete(false);
        return;
      }
      try {
        completer.complete(
          await _performSwitchVideo(index, recreateController: recreateController),
        );
      } on Object catch (error, stack) {
        debugPrint('NChewieView switchVideo queue error: $error\n$stack');
        if (!completer.isCompleted) {
          completer.complete(false);
        }
      }
    });
    return completer.future;
  }

  Future<bool> _performSwitchVideo(int index, {bool recreateController = false}) async {
    if (_closed) {
      return false;
    }
    _isSwitching = true;
    if (mounted) {
      setState(() {});
    }
    try {
      // dispose-first：先藏表面再创建，保证 initialize 时最多 1 个 AVPlayer。
      _chewieController?.setHideVideoSurface(true);
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      if (_closed) {
        return false;
      }

      final VideoPlayerController player =
          await _videoPlayerPool.acquireForSwitch(Uri.parse(_urlAt(index)));
      if (_closed || !mounted) {
        await _videoPlayerPool.releaseAll();
        return false;
      }

      await _adoptVideoPlayer(player, recreateController: recreateController);
      currPlayIndexVN.value = index;
      widget.onIndexChanged?.call(index);
      return true;
    } on Object catch (error, stack) {
      debugPrint('NChewieView switch failed: $error\n$stack');
      widget.onLoadFailed?.call(index, error);
      if (mounted && widget.onLoadFailed == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_titleAt(index)} 加载失败，请稍后重试'),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      await _recoverCurrentVideo();
      return false;
    } finally {
      if (mounted) {
        _isSwitching = false;
        setState(() {});
      }
    }
  }

  Future<void> _recoverCurrentVideo() async {
    if (_closed || widget.items.isEmpty) {
      return;
    }
    try {
      final VideoPlayerController recovered =
          await _videoPlayerPool.acquireForSwitch(Uri.parse(_urlAt(currPlayIndexVN.value)));
      if (_closed || !mounted) {
        await _videoPlayerPool.releaseAll();
        return;
      }
      await _adoptVideoPlayer(recovered);
    } on Object catch (error) {
      debugPrint('NChewieView recover failed: $error');
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _adoptVideoPlayer(
    VideoPlayerController player, {
    bool recreateController = false,
  }) async {
    final ChewieController? oldChewie = _chewieController;
    if (oldChewie == null || recreateController) {
      oldChewie?.removeListener(_onChewieFullScreenChanged);
      if (recreateController) {
        _cupertinoControlsController = null;
      }
      _createChewieController(player);
      if (mounted) {
        setState(() {});
      }
      await _disposeChewieSafely(oldChewie);
      return;
    }
    await oldChewie.replaceVideoPlayerController(player, autoPlay: widget.autoPlay);
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _disposeChewieSafely(ChewieController? chewie) async {
    if (chewie == null || chewie == _chewieController) {
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    if (chewie != _chewieController) {
      chewie.dispose();
    }
  }

  void _createChewieController(VideoPlayerController player) {
    final CupertinoControlsController controls =
        _cupertinoControlsController ??= CupertinoControlsController();

    _chewieController = ChewieController(
      videoPlayerController: player,
      aspectRatio: widget.aspectRatio,
      autoPlay: widget.autoPlay,
      looping: widget.looping,
      progressIndicatorDelay: widget.progressIndicatorDelay,
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
        final NSlideStackController stackController =
            ChewieController.of(context).isFullScreen
                ? fullScreenSlideStackController
                : slideStackController;
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
        final NSlideStackController stackController =
            (_chewieController?.isFullScreen ?? false)
                ? fullScreenSlideStackController
                : slideStackController;
        stackController.onToggle();
      },
      cupertinoControlsController: controls,
    );
    _chewieController!.addListener(_onChewieFullScreenChanged);
  }

  void _onChewieFullScreenChanged() {
    final bool isFull = _chewieController?.isFullScreen ?? false;
    if (_wasFullScreen && !isFull && fullScreenSlideStackController.isVisible) {
      fullScreenSlideStackController.onToggle();
    }
    _wasFullScreen = isFull;
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? player = _chewieController?.videoPlayerController;
    final bool isVideoReady =
        player != null && player.value.isInitialized && !player.value.hasError;

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
                childBuilder: (_) => Chewie(controller: _chewieController!),
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
              builder: (BuildContext context, NChewieDrawerEvent value, _) {
                return value == NChewieDrawerEvent.series
                    ? _buildSeriesList(onToggle: onToggle)
                    : _buildSpeedView(onToggle: onToggle);
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
        final Color activeColor = widget.activeColor;
        return Scrollbar(
          child: ListView.separated(
            itemCount: widget.items.length,
            separatorBuilder: (_, __) =>
                Divider(color: Colors.white.withValues(alpha: 0.25), height: 1),
            itemBuilder: (BuildContext context, int i) {
              final bool isSelected = i == selectedIndex;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  if (i == currPlayIndexVN.value) {
                    onToggle?.call();
                    return;
                  }
                  if (await switchVideo(i)) {
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
                            color: isSelected ? activeColor : Colors.white,
                          ),
                        ),
                      ),
                      if (isSelected)
                        Icon(Icons.play_arrow, color: activeColor, size: 20),
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
    final List<double> items =
        _chewieController?.playbackSpeeds ?? widget.playbackSpeeds;
    final VideoPlayerController? player =
        _chewieController?.videoPlayerController;
    final Color activeColor = widget.activeColor;

    Widget buildList(double currentSpeed) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(
          children: [
            for (final double speed in items)
              Expanded(
                child: GestureDetector(
                  onTap: () async {
                    await player?.setPlaybackSpeed(speed);
                    onToggle?.call();
                  },
                  child: Center(
                    child: Text(
                      '${speed}x',
                      style: TextStyle(
                        color: (currentSpeed - speed).abs() < 0.001
                            ? activeColor
                            : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    if (player == null) {
      return buildList(1.0);
    }
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: player,
      builder: (BuildContext context, VideoPlayerValue value, _) {
        return buildList(value.playbackSpeed);
      },
    );
  }
}
