import 'dart:io';

import 'package:chewie_example/app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widget/n_chewie_view.dart';

class VideoModel {
  const VideoModel({
    required this.url,
    required this.title,
  });

  final String url;
  final String title;
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
  int? bufferDelay;
  final videoViewController = NChewieViewController();

  final List<VideoModel> videos = const [
    VideoModel(
      url: 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
      title: '视频 1',
    ),
    VideoModel(
      url: 'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
      title: '视频 2',
    ),
    VideoModel(
      url: 'https://media.w3.org/2010/05/sintel/trailer.mp4',
      title: '视频 3',
    ),
    VideoModel(
      url: 'https://test-streams.mux.dev/test_001/stream.m3u8',
      title: '视频 4',
    ),
    VideoModel(
      url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
      title: '视频 5',
    ),
  ];

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
                await videoViewController.switchVideo(
                  videoViewController.currentIndex,
                  recreateController: true,
                );
              },
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          children: <Widget>[
            Expanded(
              child: NChewieView<VideoModel>(
                controller: videoViewController,
                items: videos,
                urlOf: (item) => item.url,
                titleOf: (item, int index) => item.title,
                progressIndicatorDelay: bufferDelay != null ? Duration(milliseconds: bufferDelay!) : null,
              ),
            ),
            buildBottom(),
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
                  final player = videoViewController.chewieController?.videoPlayerController;
                  player?.pause();
                  player?.seekTo(Duration.zero);
                },
                child: const Text('Landscape Video'),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: () async {
                  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
                },
                child: const Text('Portrait Video'),
              ),
            ),
          ],
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: TextButton(
                onPressed: () => setState(() => _platform = TargetPlatform.android),
                child: const Text('Android controls'),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: () => setState(() => _platform = TargetPlatform.iOS),
                child: const Text('iOS controls'),
              ),
            ),
          ],
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: TextButton(
                onPressed: () => setState(() => _platform = TargetPlatform.windows),
                child: const Text('Desktop controls'),
              ),
            ),
          ],
        ),
        if (Platform.isAndroid)
          ListTile(
            title: const Text('Delay'),
            subtitle: DelaySlider(
              delay: videoViewController.chewieController?.progressIndicatorDelay?.inMilliseconds,
              onSave: (int? delay) async {
                if (delay == null) {
                  return;
                }
                setState(() {
                  bufferDelay = delay == 0 ? null : delay;
                });
                await videoViewController.switchVideo(
                  videoViewController.currentIndex,
                  recreateController: true,
                );
              },
            ),
          ),
      ],
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
        'Progress indicator delay ${delay != null ? "${delay.toString()} MS" : ""}',
      ),
      subtitle: Slider(
        value: delay != null ? (delay! / max) : 0,
        onChanged: (double value) {
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
