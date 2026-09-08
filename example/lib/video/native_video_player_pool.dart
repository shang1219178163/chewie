import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// 单槽原生播放器池：切源时先释放旧实例，再创建新实例（dispose-first）。
class NativeVideoPlayerPool {
  NativeVideoPlayerPool({
    this.initializeTimeout = const Duration(seconds: 20),
    this.maxRetryCount = 2,
  });

  final Duration initializeTimeout;
  final int maxRetryCount;
  VideoPlayerController? _current;

  int get activeCount => _current == null ? 0 : 1;

  /// 释放旧播放器后创建并 initialize 新播放器。
  Future<VideoPlayerController> acquireForSwitch(Uri uri) async {
    await releaseAll();
    Object? lastError;
    for (int attempt = 0; attempt <= maxRetryCount; attempt++) {
      if (attempt > 0) {
        debugPrint('NativeVideoPlayerPool retry #$attempt uri=$uri');
        await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
      }
      try {
        final VideoPlayerController player = await _createAndInitialize(uri);
        _current = player;
        debugPrint('NativeVideoPlayerPool acquire uri=$uri');
        return player;
      } on Object catch (error) {
        lastError = error;
        debugPrint('NativeVideoPlayerPool acquire failed: $error');
        if (!_isRetryable(error) || attempt >= maxRetryCount) {
          rethrow;
        }
      }
    }
    throw lastError ?? StateError('视频初始化失败');
  }

  Future<VideoPlayerController> _createAndInitialize(Uri uri) async {
    final VideoPlayerController player = VideoPlayerController.networkUrl(uri);
    try {
      await player.initialize().timeout(initializeTimeout);
      if (player.value.hasError) {
        throw StateError(player.value.errorDescription ?? '视频初始化失败');
      }
      return player;
    } on Object catch (_) {
      try {
        await player.dispose();
      } catch (_) {}
      rethrow;
    }
  }

  bool _isRetryable(Object error) {
    final String message =
        error is PlatformException ? '${error.message} ${error.details}' : '$error';
    return message.contains('502') ||
        message.contains('503') ||
        message.contains('504') ||
        message.contains('Bad Gateway') ||
        message.contains('timed out') ||
        message.contains('TimeoutException') ||
        message.contains('resource unavailable');
  }

  Future<void> releaseAll() async {
    final VideoPlayerController? player = _current;
    _current = null;
    if (player == null) {
      return;
    }
    try {
      await player.pause();
    } catch (_) {}
    try {
      await player.dispose().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }
}
