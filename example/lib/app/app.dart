import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../video/native_video_player_pool.dart';
import '../widget/n_slide_stack.dart';

enum VideoButtonEvent {
  speed('倍速'),
  series('剧集');

  const VideoButtonEvent(this.desc);

  final String desc;
}

class ChewieDemo extends StatefulWidget {
  const ChewieDemo({
    super.key,
    this.title = 'Chewie Demo',
  });

  final String title;

  @override
  State<StatefulWidget> createState() => _ChewieDemoState();
}

class _ChewieDemoState extends State<ChewieDemo> {
  TargetPlatform? _platform;
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  CupertinoControlsController? _cupertinoControlsController;

  final slideStackController = NSlideStackController();
  final fullScreenSlideStackController = NSlideStackController();
  final _chewieKey = GlobalKey();
  final _videoPlayerPool = NativeVideoPlayerPool();
  final videoEventVN = ValueNotifier(VideoButtonEvent.speed);
  final currPlayIndexVN = ValueNotifier<int>(0);

  Future<void> _switchOperation = Future<void>.value();
  bool _isSwitching = false;
  bool _wasFullScreen = false;

  final List<String> srcs = [
    'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
    'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
    'https://media.w3.org/2010/05/sintel/trailer.mp4',
    'https://test-streams.mux.dev/test_001/stream.m3u8',
    'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
  ];

  @override
  void initState() {
    super.initState();
    switchVideo(currPlayIndexVN.value, recreateController: true);
  }

  @override
  void dispose() {
    currPlayIndexVN.dispose();
    videoEventVN.dispose();
    _chewieController?.removeListener(_onChewieFullScreenChanged);
    _videoPlayerPool.releaseAll();
    _chewieController?.dispose();
    super.dispose();
  }

  /// 串行切集，避免并发创建多个原生播放器。
  Future<bool> switchVideo(int index, {bool recreateController = false}) {
    if (index < 0 || index >= srcs.length) {
      return Future<bool>.value(false);
    }
    if (!recreateController && index == currPlayIndexVN.value) {
      return Future<bool>.value(false);
    }
    final Completer<bool> completer = Completer<bool>();
    // 用户发起切集那一刻即显示进度条，而不是等队列真正执行到 _performSwitchToVideo
    // 才置 true（前置任务排队时进度条会有明显延迟）。复位由 _performSwitchToVideo 的 finally 负责。
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
        debugPrint('switchToVideo queue error: $error\n$stack');
        if (!completer.isCompleted) {
          completer.complete(false);
        }
      }
    });
    return completer.future;
  }

  Future<bool> _performSwitchVideo(int index, {bool recreateController = false}) async {
    _isSwitching = true;
    setState(() {});
    try {
      // dispose-first：先藏表面再创建，保证 initialize 时最多 1 个 AVPlayer。
      _chewieController?.setHideVideoSurface(true);
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;
      final VideoPlayerController player = await _videoPlayerPool.acquireForSwitch(Uri.parse(srcs[index]));
      if (!mounted) {
        await _videoPlayerPool.releaseAll();
        return false;
      }
      await _adoptVideoPlayer(player, recreateController: recreateController);
      currPlayIndexVN.value = index;
      debugPrint('switchToVideo ok index=$index pool=${_videoPlayerPool.activeCount}');
      return true;
    } on Object catch (error, stack) {
      debugPrint('switchToVideo failed: $error\n$stack');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('视频 ${index + 1} 加载失败，请稍后重试'),
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
    try {
      final VideoPlayerController recovered =
          await _videoPlayerPool.acquireForSwitch(Uri.parse(srcs[currPlayIndexVN.value]));
      if (!mounted) {
        await _videoPlayerPool.releaseAll();
        return;
      }
      await _adoptVideoPlayer(recovered);
    } on Object catch (error) {
      debugPrint('switchToVideo recover failed: $error');
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
      _videoPlayerController = player;
      _createChewieController();
      if (mounted) {
        setState(() {});
      }
      await _disposeChewieSafely(oldChewie);
      return;
    }
    await oldChewie.replaceVideoPlayerController(player, autoPlay: true);
    _videoPlayerController = player;
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

  void _createChewieController() {
    final VideoPlayerController player = _videoPlayerController!;
    final CupertinoControlsController controls = _cupertinoControlsController ??= CupertinoControlsController();

    _chewieController = ChewieController(
      videoPlayerController: player,
      aspectRatio: 16 / 9,
      autoPlay: true,
      looping: true,
      additionalOptions: (context) => <OptionItem>[
        OptionItem(
          onTap: (context) {
            switchVideo((currPlayIndexVN.value + 1) % srcs.length);
          },
          iconData: Icons.live_tv_sharp,
          title: 'Toggle Video Src',
        ),
      ],
      subtitle: Subtitles([
        Subtitle(
          index: 0,
          start: Duration.zero,
          end: const Duration(seconds: 10),
          text: const TextSpan(
            children: [
              TextSpan(text: 'Hello', style: TextStyle(color: Colors.red, fontSize: 22)),
              TextSpan(text: ' from ', style: TextStyle(color: Colors.green, fontSize: 20)),
              TextSpan(text: 'subtitles', style: TextStyle(color: Colors.blue, fontSize: 18)),
            ],
          ),
        ),
        Subtitle(
          index: 0,
          start: const Duration(seconds: 10),
          end: const Duration(seconds: 20),
          text: 'Whats up? :)',
        ),
      ]),
      showSubtitles: true,
      subtitleBuilder: (context, dynamic subtitle) => Container(
        padding: const EdgeInsets.all(10),
        child: subtitle is InlineSpan
            ? RichText(text: subtitle)
            : Text(subtitle.toString(), style: const TextStyle(color: Colors.black)),
      ),
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
      routePageBuilder: (context, animation, secondaryAnimation, controllerProvider) {
        if (fullScreenSlideStackController.isVisible) {
          fullScreenSlideStackController.onToggle();
        }
        return AnimatedBuilder(
          animation: animation,
          builder: (BuildContext context, Widget? child) {
            return Scaffold(
              resizeToAvoidBottomInset: false,
              body: buildChewie(
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
      playbackSpeeds: const [0.5, 1.0, 1.25, 1.5, 2.0],
      onClose: () => debugPrint('onClose'),
      spacerBuilder: (context, notifier, barHeight, buttonPadding, backgroundColor, iconColor) {
        final NSlideStackController stackController =
            ChewieController.of(context).isFullScreen ? fullScreenSlideStackController : slideStackController;
        return Align(
          alignment: Alignment.bottomRight,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 100),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final VideoButtonEvent e in VideoButtonEvent.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: CupertinoControlsExt.button(
                      notifier: notifier,
                      barHeight: barHeight,
                      buttonPadding: buttonPadding,
                      backgroundColor: backgroundColor,
                      child: Text(e.desc, style: TextStyle(color: iconColor)),
                      onTap: () {
                        videoEventVN.value = e;
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
        videoEventVN.value = VideoButtonEvent.speed;
        _chewieController?.cupertinoControlsController?.notifier.hideStuff = true;
        final NSlideStackController stackController =
            (_chewieController?.isFullScreen ?? false) ? fullScreenSlideStackController : slideStackController;
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
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? player = _chewieController?.videoPlayerController;
    final bool isVideoReady = player != null && player.value.isInitialized && !player.value.hasError;
    return Theme(
      data: Theme.of(context).copyWith(platform: _platform ?? Theme.of(context).platform),
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            IconButton(
              onPressed: () async {
                await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
                await switchVideo(currPlayIndexVN.value, recreateController: true);
              },
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            Expanded(
              child: ColoredBox(
                color: Colors.black,
                child: Center(
                  child: _isSwitching || !isVideoReady
                      ? const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 20),
                            Text('Loading'),
                          ],
                        )
                      : Offstage(
                          offstage: _chewieController!.isFullScreen,
                          child: buildChewie(
                            controller: slideStackController,
                            childBuilder: (_) => Chewie(
                              key: _chewieKey,
                              controller: _chewieController!,
                            ),
                          ),
                        ),
                ),
              ),
            ),
            buildBottom(),
          ],
        ),
      ),
    );
  }

  Widget buildChewie({
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
            child: ValueListenableBuilder<VideoButtonEvent>(
              valueListenable: videoEventVN,
              builder: (BuildContext context, VideoButtonEvent value, Widget? child) {
                return value == VideoButtonEvent.series
                    ? buildListView(onToggle: onToggle)
                    : buildSpeedView(onToggle: onToggle);
              },
            ),
          ),
        ),
      ),
      childBuilder: childBuilder,
    );
  }

  Widget buildListView({VoidCallback? onToggle}) {
    return ValueListenableBuilder<int>(
      valueListenable: currPlayIndexVN,
      builder: (context, selectedIndex, child) {
        final Color dividerColor = Colors.white.withValues(alpha: 0.1);
        return Scrollbar(
          child: ListView.separated(
            itemCount: srcs.length,
            separatorBuilder: (_, __) => Divider(color: dividerColor, height: 1),
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
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  color: isSelected ? dividerColor : Colors.transparent,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '视频 ${i + 1}',
                          style: TextStyle(color: isSelected ? Colors.amber : Colors.white),
                        ),
                      ),
                      if (isSelected) const Icon(Icons.play_arrow, color: Colors.amber),
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

  Widget buildSpeedView({VoidCallback? onToggle}) {
    final List<double> items = _chewieController!.playbackSpeeds;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          for (final double speed in items)
            Expanded(
              child: GestureDetector(
                onTap: () async {
                  await _chewieController!.videoPlayerController.setPlaybackSpeed(speed);
                  onToggle?.call();
                },
                child: Center(
                  child: Text('${speed}x', style: const TextStyle(color: Colors.white)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget buildBottom() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () {
                  final VideoPlayerController? player = _videoPlayerController;
                  if (player == null) {
                    return;
                  }
                  player.pause();
                  player.seekTo(Duration.zero);
                  _chewieController?.removeListener(_onChewieFullScreenChanged);
                  _chewieController?.dispose();
                  _cupertinoControlsController = null;
                  _createChewieController();
                  setState(() {});
                },
                child: const Text('Landscape Video'),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: () => SystemChrome.setPreferredOrientations(
                  [DeviceOrientation.portraitUp],
                ),
                child: const Text('Portrait Video'),
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: TextButton(
                onPressed: () {
                  _platform = TargetPlatform.android;
                  setState(() {});
                },
                child: const Text('Android controls'),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: () {
                  _platform = TargetPlatform.iOS;
                  setState(() {});
                },
                child: const Text('iOS controls'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
