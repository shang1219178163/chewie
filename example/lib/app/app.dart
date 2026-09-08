import 'dart:async';
import 'dart:ui' as ui;

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../video/native_video_player_pool.dart';
import '../widget/n_slide_stack.dart';

enum VideoButtonEvent {
  speed("倍速"),
  series("剧集");

  const VideoButtonEvent(this.desc);

  final String desc;
}

class _SwitchTask {
  const _SwitchTask({
    required this.index,
    required this.recreateController,
    required this.completer,
  });

  final int index;
  final bool recreateController;
  final Completer<bool> completer;
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
  /// 旧视频原生表面 detach 的兜底等待时长，避免释放旧播放器后新播放器无法绑定纹理。
  static const surfaceDetachSettle = Duration(milliseconds: 120);

  TargetPlatform? _platform;
  late VideoPlayerController _videoPlayerController1;
  ChewieController? _chewieController;
  CupertinoControlsController? _cupertinoControlsController;
  int? bufferDelay;

  bool get isPortrait => MediaQuery.of(context).orientation == Orientation.portrait;

  final slideStackController = NSlideStackController();
  final fullScreenSlideStackController = NSlideStackController();
  final _chewieKey = GlobalKey();
  final _videoPlayerPool = NativeVideoPlayerPool(maxPlayerCount: 2);

  final videoEventVN = ValueNotifier(VideoButtonEvent.speed);

  @override
  void initState() {
    super.initState();
    initializePlayer();
  }

  @override
  void dispose() {
    currPlayIndexVN.dispose();
    if (_fullScreenListenerAttached) {
      _chewieController?.removeListener(_onChewieFullScreenChanged);
      _fullScreenListenerAttached = false;
    }
    _videoPlayerPool.releaseAll();
    _chewieController?.dispose();
    super.dispose();
  }

  /// 使用稳定 HTTPS 演示源；旧源（w3school / vjs）常返回 HTTP 502。
  List<String> srcs = [
    'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
    'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
    'https://media.w3.org/2010/05/sintel/trailer.mp4',
    'https://test-streams.mux.dev/test_001/stream.m3u8',
    'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
  ];

  Future<void> initializePlayer() async {
    await switchToVideo(currPlayIndex, recreateController: true);
  }

  int currPlayIndex = 0;
  final currPlayIndexVN = ValueNotifier<int>(0);
  final _pendingSwitches = <_SwitchTask>[];
  bool _isProcessingSwitch = false;
  bool _isSwitching = false;

  Future<bool> switchToVideo(int index, {bool recreateController = false}) async {
    if (index < 0 || index >= srcs.length) {
      return false;
    }
    if (!recreateController && index == currPlayIndex) {
      return false;
    }
    final Completer<bool> completer = Completer<bool>();
    _pendingSwitches.add(
      _SwitchTask(
        index: index,
        recreateController: recreateController,
        completer: completer,
      ),
    );
    unawaited(_processSwitchQueue());
    return completer.future;
  }

  Future<void> _processSwitchQueue() async {
    if (_isProcessingSwitch) {
      return;
    }
    _isProcessingSwitch = true;
    try {
      while (_pendingSwitches.isNotEmpty) {
        // 再次合并：执行前只取队列末尾（最新）任务。
        while (_pendingSwitches.length > 1) {
          final _SwitchTask skipped = _pendingSwitches.removeAt(0);
          if (!skipped.completer.isCompleted) {
            skipped.completer.complete(false);
          }
        }
        final _SwitchTask task = _pendingSwitches.removeAt(0);
        try {
          if (!task.recreateController && task.index == currPlayIndex) {
            task.completer.complete(false);
            continue;
          }
          final bool success = await _performSwitchToVideo(
            task.index,
            recreateController: task.recreateController,
          );
          if (!task.completer.isCompleted) {
            task.completer.complete(success);
          }
        } on Object catch (error, stack) {
          debugPrint('switchToVideo queue error: $error\n$stack');
          if (!task.completer.isCompleted) {
            task.completer.complete(false);
          }
        }
      }
    } finally {
      _isProcessingSwitch = false;
      if (_pendingSwitches.isNotEmpty) {
        unawaited(_processSwitchQueue());
      }
    }
  }

  /// 等待多个渲染帧后再释放旧播放器。
  ///
  /// 原生视频表面（iOS 为 AVPlayerLayer）从 widget 树中移除后，
  /// 平台层的 detach 是异步的。若不等表面彻底 detach 就 dispose 旧
  /// AVPlayer，新播放器初始化时可能无法绑定视频纹理，导致切换后画面
  /// 仍停留在旧视频。这里除等待两帧外，再让出一小段时间确保 detach 落盘。
  Future<void> _waitForVideoSurfaceDetach() async {
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(surfaceDetachSettle);
  }

  Future<bool> _performSwitchToVideo(int index, {bool recreateController = false}) async {
    final Uri url = Uri.parse(srcs[index]);
    VideoPlayerController? newVideoPlayerController;
    _isSwitching = true;
    setState(() {});
    try {
      // 1. 先隐藏原生表面，再释放旧播放器，保证 initialize 时最多 1 个 AVPlayer。
      _chewieController?.setHideVideoSurface(true);
      await _waitForVideoSurfaceDetach();
      newVideoPlayerController = await _videoPlayerPool.acquireForSwitch(url);
      if (!mounted) {
        await _videoPlayerPool.releaseAll();
        return false;
      }
      await _adoptVideoPlayer(
        newVideoPlayerController,
        recreateController: recreateController,
      );
      currPlayIndex = index;
      currPlayIndexVN.value = index;
      debugPrint([
        runtimeType,
        'switchToVideo ok',
        _chewieController?.videoPlayerController.hashCode,
        _chewieController?.videoPlayerController.dataSource,
        'pool=${_videoPlayerPool.activeCount}',
      ].join(', '));
      return true;
    } catch (error, stack) {
      debugPrint('switchToVideo failed: $error\n$stack');
      _showSwitchFailHint(index);
      await _recoverCurrentVideo();
      return false;
    } finally {
      if (mounted) {
        _isSwitching = false;
        setState(() {});
      }
    }
  }

  /// 切到无效/不可达视频源时用 SnackBar 提示用户。
  void _showSwitchFailHint(int index) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('视频 ${index + 1} 加载失败，请稍后重试'),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// dispose-first 失败后按当前索引重新拉起播放器，避免界面卡死。
  Future<void> _recoverCurrentVideo() async {
    try {
      final VideoPlayerController recovered = await _videoPlayerPool.acquireForSwitch(Uri.parse(srcs[currPlayIndex]));
      if (!mounted) {
        await _videoPlayerPool.releaseAll();
        return;
      }
      await _adoptVideoPlayer(recovered);
    } on Object catch (error) {
      debugPrint('switchToVideo recover failed: $error');
      // 双失败后旧播放器已被 pool dispose，videoPlayerController 指向已释放控制器。
      // 保持表面隐藏，由 _isVideoReady() 显示 Loading 兜底，避免绘制无效纹理。
      if (mounted) {
        setState(() {});
      }
    }
  }

  /// 把 [newVideoPlayerController] 挂到 Chewie 上：重建或复用现有 controller。
  Future<void> _adoptVideoPlayer(
    VideoPlayerController newVideoPlayerController, {
    bool recreateController = false,
  }) async {
    final ChewieController? oldChewieController = _chewieController;
    if (oldChewieController == null || recreateController) {
      if (recreateController) {
        _cupertinoControlsController = null;
      }
      _videoPlayerController1 = newVideoPlayerController;
      _createChewieController();
      if (mounted) {
        setState(() {});
      }
      await _disposeChewieSafely(oldChewieController);
    } else {
      await oldChewieController.replaceVideoPlayerController(
        newVideoPlayerController,
        autoPlay: true,
      );
      _videoPlayerController1 = newVideoPlayerController;
      if (mounted) {
        setState(() {});
      }
    }
  }

  bool _isVideoReady() {
    final ChewieController? controller = _chewieController;
    if (controller == null) {
      return false;
    }
    final VideoPlayerController player = controller.videoPlayerController;
    return player.value.isInitialized && !player.value.hasError;
  }

  Future<void> _disposeChewieSafely(ChewieController? chewieController) async {
    if (chewieController == null || chewieController == _chewieController) {
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    if (chewieController == _chewieController) {
      return;
    }
    chewieController.dispose();
  }

  void _createChewieController() {
    // final subtitles = [
    //     Subtitle(
    //       index: 0,
    //       start: Duration.zero,
    //       end: const Duration(seconds: 10),
    //       text: 'Hello from subtitles',
    //     ),
    //     Subtitle(
    //       index: 0,
    //       start: const Duration(seconds: 10),
    //       end: const Duration(seconds: 20),
    //       text: 'Whats up? :)',
    //     ),
    //   ];

    final subtitles = [
      Subtitle(
        index: 0,
        start: Duration.zero,
        end: const Duration(seconds: 10),
        text: const TextSpan(
          children: [
            TextSpan(
              text: 'Hello',
              style: TextStyle(color: Colors.red, fontSize: 22),
            ),
            TextSpan(
              text: ' from ',
              style: TextStyle(color: Colors.green, fontSize: 20),
            ),
            TextSpan(
              text: 'subtitles',
              style: TextStyle(color: Colors.blue, fontSize: 18),
            )
          ],
        ),
      ),
      Subtitle(
        index: 0,
        start: const Duration(seconds: 10),
        end: const Duration(seconds: 20),
        text: 'Whats up? :)',
        // text: const TextSpan(
        //   text: 'Whats up? :)',
        //   style: TextStyle(color: Colors.amber, fontSize: 22, fontStyle: FontStyle.italic),
        // ),
      ),
    ];

    final cupertinoControlsController = _cupertinoControlsController ??= CupertinoControlsController();

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController1,
      aspectRatio: 16 / 9,
      autoPlay: true,
      looping: true,
      progressIndicatorDelay: bufferDelay != null ? Duration(milliseconds: bufferDelay!) : null,
      additionalOptions: (context) {
        return <OptionItem>[
          OptionItem(
            onTap: (context) => toggleVideo(),
            iconData: Icons.live_tv_sharp,
            title: 'Toggle Video Src',
          ),
        ];
      },
      subtitle: Subtitles(subtitles),
      showSubtitles: true,
      subtitleBuilder: (context, dynamic subtitle) => Container(
        padding: const EdgeInsets.all(10.0),
        child: subtitle is InlineSpan
            ? RichText(
                text: subtitle,
              )
            : Text(
                subtitle.toString(),
                style: const TextStyle(color: Colors.black),
              ),
      ),
      hideControlsTimer: const Duration(seconds: 3),
      showControls: true,
      // materialProgressColors: ChewieProgressColors(
      //   playedColor: Colors.red,
      //   handleColor: Colors.blue,
      //   backgroundColor: Colors.grey,
      //   bufferedColor: Colors.lightGreen,
      // ),
      // placeholder: Container(
      //   color: Colors.grey,
      // ),
      // autoInitialize: true,
      // allowMuting: false,
      allowPlaySkip: false,
      allowFullScreen: true,
      deviceOrientationsOnEnterFullScreen: [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
      deviceOrientationsAfterFullScreen: [
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
              body: buildChewie(
                controller: fullScreenSlideStackController,
                childBuilder: (onToggle) => Container(
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
      onClose: () {
        print("onClose");
      },
      spacerBuilder: (context, notifier, barHeight, buttonPadding, backgroundColor, iconColor) {
        final NSlideStackController stackController =
            ChewieController.of(context).isFullScreen ? fullScreenSlideStackController : slideStackController;

        // final items = List.generate(3, (i) => "选项$i");
        const items = VideoButtonEvent.values;

        const constraints = BoxConstraints(
          maxWidth: 100,
          // maxHeight: 200.0,
        );

        return Align(
          alignment: Alignment.bottomRight,
          child: Container(
            constraints: constraints,
            // clipBehavior: Clip.hardEdge,
            // decoration: BoxDecoration(
            // color: Colors.green,
            // border: Border.all(color: Colors.blue),
            // borderRadius: BorderRadius.all(Radius.circular(0)),
            // ),
            child: Column(
              // mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Container(
                //   decoration: const BoxDecoration(
                //     color: Colors.green,
                //   ),
                //   child: Text("${constraints.maxWidth},${constraints.maxHeight},"),
                // ),
                ...items.map(
                  (e) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: CupertinoControlsExt.button(
                        notifier: notifier,
                        // width: 100,
                        barHeight: barHeight,
                        buttonPadding: buttonPadding,
                        backgroundColor: backgroundColor,
                        child: Text(
                          e.desc,
                          style: TextStyle(color: iconColor),
                        ),
                        onTap: () {
                          videoEventVN.value = e;
                          stackController.onToggle();
                        },
                      ),
                    );
                  },
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
      cupertinoControlsController: cupertinoControlsController,
    );
    if (_fullScreenListenerAttached) {
      _chewieController?.removeListener(_onChewieFullScreenChanged);
    }
    _chewieController?.addListener(_onChewieFullScreenChanged);
    _fullScreenListenerAttached = true;
  }

  bool _fullScreenListenerAttached = false;
  bool _wasFullScreen = false;

  /// 全屏状态变化时，若从全屏退出则关闭全屏抽屉，避免残留打开状态导致
  /// 后续点击剧集作用到已销毁的全屏 controller。
  void _onChewieFullScreenChanged() {
    final bool isFull = _chewieController?.isFullScreen ?? false;
    if (_wasFullScreen && !isFull) {
      if (fullScreenSlideStackController.isVisible) {
        fullScreenSlideStackController.onToggle();
      }
      _wasFullScreen = false;
    } else if (isFull) {
      _wasFullScreen = true;
    }
  }

  Future<void> toggleVideo() async {
    final int nextIndex = (currPlayIndex + 1) % srcs.length;
    final bool switched = await switchToVideo(nextIndex);
    debugPrint('toggleVideo index=$nextIndex switched=$switched');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            onPressed: () async {
              await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
              await initializePlayer();
              setState(() {});
            },
            icon: Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            child: Container(
              color: Colors.black,
              child: Center(
                child: _isSwitching || !_isVideoReady()
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
                          childBuilder: (onToggle) => Chewie(
                            key: _chewieKey,
                            controller: _chewieController!,
                          ),
                        ),
                      ),
              ),
            ),
          ),
          buildBottom(),
          // Spacer(),
        ],
      ),
    );
  }

  Widget buildChewie({
    required NSlideStackController controller,
    required Widget Function(VoidCallback onToggle) childBuilder,
  }) {
    return NSlideStack(
      controller: controller,
      drawerWidth: MediaQuery.of(context).orientation == Orientation.portrait ? 150 : 200,
      drawerBuilder: (VoidCallback onToggle) => TapRegion(
        onTapOutside: (PointerDownEvent e) {
          if (controller.isVisible) {
            controller.onToggle();
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.6),
          ),
          child: MediaQuery.removePadding(
            context: context,
            removeTop: true,
            removeBottom: true,
            removeLeft: true,
            removeRight: true,
            child: ValueListenableBuilder<VideoButtonEvent>(
              valueListenable: videoEventVN,
              builder: (context, value, child) {
                if (value == VideoButtonEvent.series) {
                  return buildListView(onToggle: onToggle);
                }
                return buildSpeedView(onToggle: onToggle);
              },
            ),
          ),
        ),
      ),
      childBuilder: childBuilder,
    );
  }

  /// 视频列表
  Widget buildListView({
    VoidCallback? onTap,
    VoidCallback? onToggle,
    Divider? divider,
  }) {
    return ValueListenableBuilder<int>(
      valueListenable: currPlayIndexVN,
      builder: (BuildContext context, int selectedIndex, Widget? child) {
        final dividerColor = Colors.white.withValues(alpha: 0.1);
        return Scrollbar(
          child: ListView.separated(
            itemBuilder: (context, int i) {
              final String title = '视频 ${i + 1}';
              final bool isSelected = i == selectedIndex;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  if (i == currPlayIndex) {
                    onToggle?.call();
                    return;
                  }
                  final bool switched = await switchToVideo(i);
                  if (switched) {
                    onToggle?.call();
                  }
                  onTap?.call();
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
                          title,
                          style: TextStyle(
                            color: isSelected ? Colors.amber : Colors.white,
                          ),
                        ),
                      ),
                      if (isSelected) const Icon(Icons.play_arrow, color: Colors.amber),
                    ],
                  ),
                ),
              );
            },
            separatorBuilder: (context, i) {
              return divider ?? Divider(color: dividerColor, height: 1);
            },
            itemCount: srcs.length,
          ),
        );
      },
    );
  }

  /// 倍数
  Widget buildSpeedView({
    VoidCallback? onTap,
    VoidCallback? onToggle,
    Divider? divider,
  }) {
    final items = _chewieController!.playbackSpeeds;
    return Container(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          ...items.map((e) {
            return Expanded(
              child: GestureDetector(
                onTap: () async {
                  debugPrint("$e");
                  if (onTap != null) {
                    onTap();
                  } else {
                    await _chewieController!.videoPlayerController.setPlaybackSpeed(e);
                  }
                  onToggle?.call();
                },
                child: Container(
                  alignment: Alignment.center,
                  child: Text(
                    "${e}x",
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            );
          })
        ],
      ),
    );
  }

  Widget buildBottom() {
    return Column(
      children: [
        Row(
          children: <Widget>[
            Expanded(
              child: TextButton(
                onPressed: () {
                  _videoPlayerController1.pause();
                  _videoPlayerController1.seekTo(Duration.zero);
                  _chewieController?.dispose();
                  _cupertinoControlsController = null;
                  _createChewieController();
                  setState(() {});
                },
                child: Text("Landscape Video"),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: () async {
                  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
                },
                child: Text("Portrait Video"),
              ),
            )
          ],
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: TextButton(
                onPressed: () {
                  _platform = TargetPlatform.android;
                  setState(() {});
                },
                child: Text("Android controls"),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: () {
                  _platform = TargetPlatform.iOS;
                  setState(() {});
                },
                child: Text("iOS controls"),
              ),
            )
          ],
        ),
        // Row(
        //   children: <Widget>[
        //     Expanded(
        //       child: TextButton(
        //         onPressed: () {
        //           setState(() {
        //             _platform = TargetPlatform.windows;
        //           });
        //         },
        //         child: Text("Desktop controls"),
        //       ),
        //     ),
        //   ],
        // ),
        // if (Platform.isAndroid)
        //   ListTile(
        //     title: const Text("Delay"),
        //     subtitle: DelaySlider(
        //       delay: _chewieController?.progressIndicatorDelay?.inMilliseconds,
        //       onSave: (delay) async {
        //         if (delay != null) {
        //           bufferDelay = delay == 0 ? null : delay;
        //           await initializePlayer();
        //         }
        //       },
        //     ),
        //   )
      ],
    );
  }

  Widget buildButton({
    required PlayerNotifier notifier,
    required Color backgroundColor,
    double? width,
    double? barHeight,
    EdgeInsets? buttonPadding,
    required Widget child,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: notifier.hideStuff ? 0.0 : 1.0,
        duration: const Duration(milliseconds: 300),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10.0),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 10.0),
            child: Container(
              width: width,
              height: barHeight,
              padding: buttonPadding,
              color: backgroundColor,
              child: Center(
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DelaySlider extends StatefulWidget {
  const DelaySlider({super.key, required this.delay, required this.onSave});

  final int? delay;
  final void Function(int?) onSave;
  @override
  State<DelaySlider> createState() => _DelaySliderState();
}

class _DelaySliderState extends State<DelaySlider> {
  int? delay;
  bool saved = false;

  @override
  void initState() {
    super.initState();
    delay = widget.delay;
  }

  @override
  Widget build(BuildContext context) {
    const int max = 1000;
    return ListTile(
      title: Text(
        "Progress indicator delay ${delay != null ? "${delay.toString()} MS" : ""}",
      ),
      subtitle: Slider(
        value: delay != null ? (delay! / max) : 0,
        onChanged: (value) async {
          delay = (value * max).toInt();
          saved = false;
          setState(() {});
        },
      ),
      trailing: IconButton(
        icon: const Icon(Icons.save),
        onPressed: saved
            ? null
            : () {
                widget.onSave(delay);
                saved = true;
                setState(() {});
              },
      ),
    );
  }
}
