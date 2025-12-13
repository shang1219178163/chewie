import 'dart:io';
import 'dart:ui' as ui;
import 'package:chewie/chewie.dart';
import 'package:chewie_example/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../widget/NSlidePopupRoute.dart';

class ChewieDemo extends StatefulWidget {
  const ChewieDemo({
    super.key,
    this.title = 'Chewie Demo',
  });

  final String title;

  @override
  State<StatefulWidget> createState() {
    return _ChewieDemoState();
  }
}

class _ChewieDemoState extends State<ChewieDemo> {
  TargetPlatform? _platform;
  late VideoPlayerController _videoPlayerController1;
  late VideoPlayerController _videoPlayerController2;
  ChewieController? _chewieController;
  int? bufferDelay;

  @override
  void initState() {
    super.initState();
    initializePlayer();
  }

  @override
  void dispose() {
    _videoPlayerController1.dispose();
    _videoPlayerController2.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  List<String> srcs = [
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4",
    "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
  ];

  Future<void> initializePlayer() async {
    _videoPlayerController1 = VideoPlayerController.networkUrl(Uri.parse(srcs[currPlayIndex]));
    _videoPlayerController2 = VideoPlayerController.networkUrl(Uri.parse(srcs[currPlayIndex]));
    await Future.wait([_videoPlayerController1.initialize(), _videoPlayerController2.initialize()]);
    _createChewieController();
    setState(() {});
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

      hideControlsTimer: const Duration(seconds: 10),

      // Try playing around with some of these other options:
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
      // overlay: Positioned(
      //   right: 8,
      //   top: 8,
      //   child: Container(
      //     decoration: BoxDecoration(
      //       color: Colors.transparent,
      //       border: Border.all(color: Colors.blue),
      //     ),
      //     child: GestureDetector(
      //       onTap: () {
      //         debugPrint("${DateTime.now()} $runtimeType close");
      //       },
      //       child: Padding(
      //         padding: const EdgeInsets.all(8.0),
      //         child: Icon(Icons.close, color: Colors.white),
      //       ),
      //     ),
      //   ),
      // ),
      allowFullScreen: true,
      deviceOrientationsOnEnterFullScreen: [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ],
      deviceOrientationsAfterFullScreen: [
        DeviceOrientation.portraitUp,
      ],
    );
  }

  int currPlayIndex = 0;

  Future<void> toggleVideo() async {
    await _videoPlayerController1.pause();
    currPlayIndex += 1;
    if (currPlayIndex >= srcs.length) {
      currPlayIndex = 0;
    }
    await initializePlayer();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: widget.title,
      theme: AppTheme.light.copyWith(
        platform: _platform ?? Theme.of(context).platform,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            IconButton(
              onPressed: () async {
                await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
                _chewieController = _chewieController?.copyWith(
                  onClose: () {
                    print("onClose");
                  },
                  spacerBuilder: (notifier, barHeight, buttonPadding, backgroundColor, iconColor) {
                    final items = List.generate(3, (i) => "选项$i");

                    const constraints = BoxConstraints(
                      maxWidth: 100,
                      // maxHeight: 200.0,
                    );

                    return Align(
                      alignment: Alignment.bottomRight,
                      child: Container(
                        constraints: constraints,
                        clipBehavior: Clip.hardEdge,
                        decoration: BoxDecoration(
                          // color: Colors.green,
                          border: Border.all(color: Colors.blue),
                          // borderRadius: BorderRadius.all(Radius.circular(0)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.end,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              decoration: const BoxDecoration(
                                color: Colors.green,
                              ),
                              child: Text("${constraints.maxWidth},${constraints.maxHeight},"),
                            ),
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
                                      e,
                                      style: TextStyle(color: iconColor),
                                    ),
                                    onTap: () {
                                      print(e);
                                      Navigator.of(context).push(buildPopupRoute(from: Alignment.centerRight));
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
                );
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
                  child: _chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
                      ? Chewie(
                          controller: _chewieController!,
                        )
                      : const Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 20),
                            Text('Loading'),
                          ],
                        ),
                ),
              ),
            ),
            buildBottom(),
            buildPopup(),
            Spacer(),
          ],
        ),
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
                  setState(() {
                    _videoPlayerController1.pause();
                    _videoPlayerController1.seekTo(Duration.zero);
                    _createChewieController();
                  });
                },
                child: Text("Landscape Video"),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: () async {
                  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
                  setState(() {
                    // _videoPlayerController2.pause();
                    // _videoPlayerController2.seekTo(Duration.zero);
                    // _chewieController = _chewieController!.copyWith(
                    //   videoPlayerController: _videoPlayerController2,
                    //   autoPlay: true,
                    //   looping: true,
                    //   /* subtitle: Subtitles([
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
                    //   ]),
                    //   subtitleBuilder: (context, subtitle) => Container(
                    //     padding: const EdgeInsets.all(10.0),
                    //     child: Text(
                    //       subtitle,
                    //       style: const TextStyle(color: Colors.white),
                    //     ),
                    //   ), */
                    // );
                  });
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
                  setState(() {
                    _platform = TargetPlatform.android;
                  });
                },
                child: Text("Android controls"),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: () {
                  setState(() {
                    _platform = TargetPlatform.iOS;
                  });
                },
                child: Text("iOS controls"),
              ),
            )
          ],
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: TextButton(
                onPressed: () {
                  setState(() {
                    _platform = TargetPlatform.windows;
                  });
                },
                child: Text("Desktop controls"),
              ),
            ),
          ],
        ),
        if (Platform.isAndroid)
          ListTile(
            title: const Text("Delay"),
            subtitle: DelaySlider(
              delay: _chewieController?.progressIndicatorDelay?.inMilliseconds,
              onSave: (delay) async {
                if (delay != null) {
                  bufferDelay = delay == 0 ? null : delay;
                  await initializePlayer();
                }
              },
            ),
          )
      ],
    );
  }

  Widget buildPopup() {
    final items = [
      Alignment.center,
      Alignment.centerLeft,
      Alignment.centerRight,
      Alignment.topCenter,
      Alignment.bottomCenter,
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items.map((e) {
        return MaterialButton(
          onPressed: () {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              Navigator.of(context).push(buildPopupRoute(alignment: e, from: e));
            });
          },
          child: Text(e.toString().split(".").last),
        );
      }).toList(),
    );
  }

  buildPopupRoute({required Alignment from, Alignment alignment = Alignment.centerRight}) {
    return NSlidePopupRoute(
      // barrierColor: Colors.red.withOpacity(0.3),
      barrierColor: Colors.black.withOpacity(0.0),
      from: from,
      builder: (_) {
        return Align(
          alignment: alignment,
          child: Container(
            width: 200,
            height: 400,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.green,
              border: Border.all(color: Colors.blue),
              borderRadius: BorderRadius.all(Radius.circular(0)),
            ),
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text("dismiss"),
            ),
          ),
        );
      },
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
          setState(() {
            saved = false;
          });
        },
      ),
      trailing: IconButton(
        icon: const Icon(Icons.save),
        onPressed: saved
            ? null
            : () {
                widget.onSave(delay);
                setState(() {
                  saved = true;
                });
              },
      ),
    );
  }
}
