import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

/// 原生播放器池：任意时刻最多保留 [maxPlayerCount] 个实例。
///
/// 切源策略为 dispose-first：先释放全部旧实例，再创建并 initialize 新实例，
/// 避免 iOS 上同时存在多个 AVPlayer 导致后续 initialize 静默失败。
class NativeVideoPlayerPool {
  NativeVideoPlayerPool({
    this.maxPlayerCount = 2,
    this.initializeTimeout = const Duration(seconds: 20),
    this.maxRetryCount = 2,
  });

  final int maxPlayerCount;
  final Duration initializeTimeout;
  final int maxRetryCount;
  final Set<VideoPlayerController> _tracked = <VideoPlayerController>{};

  int get activeCount => _tracked.length;

  /// 创建新播放器前先清空池内全部实例（含 current）。
  Future<VideoPlayerController> acquireForSwitch(Uri uri) async {
    await releaseAll();
    Object? lastError;
    for (int attempt = 0; attempt <= maxRetryCount; attempt++) {
      if (attempt > 0) {
        debugPrint('NativeVideoPlayerPool retry #$attempt, uri=$uri');
        await Future<void>.delayed(Duration(milliseconds: 300 * attempt));
      }
      try {
        return await _createAndInitialize(uri);
      } on Object catch (error) {
        lastError = error;
        debugPrint('NativeVideoPlayerPool acquire failed: $error');
        if (!_isRetryableError(error) || attempt >= maxRetryCount) {
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
        throw StateError(
          player.value.errorDescription ?? '视频初始化失败',
        );
      }
      _tracked.add(player);
      assert(activeCount <= maxPlayerCount);
      debugPrint(
        'NativeVideoPlayerPool acquire, activeCount=$activeCount, uri=$uri',
      );
      return player;
    } on Object catch (_) {
      try {
        await player.dispose();
      } catch (_) {}
      rethrow;
    }
  }

  bool _isRetryableError(Object error) {
    final String message = error is PlatformException
        ? '${error.message} ${error.details}'
        : error.toString();
    return message.contains('502') ||
        message.contains('503') ||
        message.contains('504') ||
        message.contains('Bad Gateway') ||
        message.contains('timed out') ||
        message.contains('TimeoutException') ||
        message.contains('resource unavailable');
  }

  Future<void> releaseAll() async {
    final List<VideoPlayerController> all = _tracked.toList(growable: false);
    _tracked.clear();
    for (final VideoPlayerController player in all) {
      await _disposePlayer(player);
    }
  }

  Future<void> _disposePlayer(VideoPlayerController player) async {
    try {
      await player.pause();
    } catch (_) {}
    try {
      await player.dispose().timeout(const Duration(seconds: 2));
    } catch (_) {}
    debugPrint('NativeVideoPlayerPool dispose, activeCount=$activeCount');
  }
}
