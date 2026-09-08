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
    return Theme(
      data: Theme.of(context).copyWith(platform: _platform ?? Theme.of(context).platform),
      child: Scaffold(
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
            Container(
              height: 300,
              child: NChewieView<VideoModel>(
                controller: videoViewController,
                items: videos,
                urlOf: (item) => item.url,
                titleOf: (item, int index) => item.title,
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
          children: [
            Expanded(
              child: TextButton(
                onPressed: () {
                  final player = videoViewController.chewieController?.videoPlayerController;
                  player?.pause();
                  player?.seekTo(Duration.zero);
                },
                child: const Text('Pause & Seek 0'),
              ),
            ),
            Expanded(
              child: TextButton(
                onPressed: () => SystemChrome.setPreferredOrientations(
                  [DeviceOrientation.portraitUp],
                ),
                child: const Text('Portrait'),
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
