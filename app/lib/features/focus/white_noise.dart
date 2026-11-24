import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/log/app_log.dart';
import '../../core/i18n/i18n.dart';

/// 白噪音场景。
///
/// 素材不随包分发，而是运行时算出来：一段 6 秒的 PCM 只有 264KB，
/// 但换来「零素材、零版权、包体不涨」——这是本地优先应用该有的取舍。
enum NoiseScene {
  white('白噪音', '均匀，盖住环境杂音', Icons.blur_on),
  pink('粉噪音', '更柔和，适合阅读', Icons.waves),
  brown('棕噪音', '低沉，像远处瀑布', Icons.landscape_outlined),
  rain('雨声', '棕噪音加雨滴', Icons.water_drop_outlined);

  const NoiseScene(this._label, this._hint, this.icon);
  final String _label;
  final String _hint;
  final IconData icon;

  String get label => tr(_label);
  String get hint => tr(_hint);
}

class NoiseState {
  NoiseState({this.scene, this.volume = 0.45, this.paused = false});
  final NoiseScene? scene;
  final double volume;
  final bool paused;

  bool get playing => scene != null && !paused;
  bool get active => scene != null;

  NoiseState copyWith({
    NoiseScene? scene,
    double? volume,
    bool? paused,
    bool clear = false,
  }) => NoiseState(
    scene: clear ? null : (scene ?? this.scene),
    volume: volume ?? this.volume,
    paused: clear ? false : (paused ?? this.paused),
  );
}

class WhiteNoiseController extends Notifier<NoiseState> {
  AudioPlayer? _player;
  static final Map<NoiseScene, Uint8List> _cache = {};

  @override
  NoiseState build() {
    ref.onDispose(() {
      _player?.dispose();
      _player = null;
    });
    return NoiseState();
  }

  AudioPlayer get _ensurePlayer {
    final existing = _player;
    if (existing != null) return existing;
    final player = AudioPlayer()..setReleaseMode(ReleaseMode.loop);
    _player = player;
    return player;
  }

  Future<void> play(NoiseScene scene) async {
    try {
      final player = _ensurePlayer;
      final bytes = _cache.putIfAbsent(scene, () => _render(scene));
      await player.setVolume(state.volume);
      await player.setSource(BytesSource(bytes, mimeType: 'audio/wav'));
      await player.resume();
      state = state.copyWith(scene: scene, paused: false);
      AppLog.i(trf('白噪音开始：{}', [scene.label]));
    } catch (e) {
      AppLog.w(trf('白噪音播放失败：{}', [e]));
      state = state.copyWith(clear: true);
    }
  }

  Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (_) {
      // 停止失败不影响状态复位
    }
    state = state.copyWith(clear: true);
  }

  /// 暂停而不销毁：恢复时接着播，不重新解码。
  Future<void> pause() async {
    if (state.scene == null) return;
    try {
      await _player?.pause();
    } catch (_) {
      // 忽略：暂停失败不该打断专注
    }
    state = state.copyWith(paused: true);
  }

  Future<void> resume() async {
    if (state.scene == null) return;
    try {
      await _player?.resume();
    } catch (_) {
      // 忽略
    }
    state = state.copyWith(paused: false);
  }

  Future<void> togglePlay() async {
    if (state.scene == null) return;
    if (state.paused) {
      await resume();
    } else {
      await pause();
    }
  }

  Future<void> toggle(NoiseScene scene) async {
    if (state.scene == scene) {
      await stop();
    } else {
      await play(scene);
    }
  }

  Future<void> setVolume(double value) async {
    final v = value.clamp(0.0, 1.0);
    state = state.copyWith(volume: v);
    try {
      await _player?.setVolume(v);
    } catch (_) {
      // 忽略：音量失败不该打断专注
    }
  }
}

final whiteNoiseProvider = NotifierProvider<WhiteNoiseController, NoiseState>(
  WhiteNoiseController.new,
);

// ------------------------------------------------------------------ 音频生成

const int _rate = 22050;
const int _seconds = 6;

Uint8List _render(NoiseScene scene) {
  final total = _rate * _seconds;
  final data = Int16List(total);
  final rnd = Random(7 + scene.index * 31);

  double b0 = 0, b1 = 0, b2 = 0;
  double brown = 0;
  double dropEnv = 0;

  for (var i = 0; i < total; i++) {
    final w = rnd.nextDouble() * 2 - 1;
    double v;
    switch (scene) {
      case NoiseScene.white:
        v = w * 0.16;
      case NoiseScene.pink:
        // Paul Kellet 的粉噪声近似，系数固定，输出稳定不飘。
        b0 = 0.99765 * b0 + w * 0.0990460;
        b1 = 0.96300 * b1 + w * 0.2965164;
        b2 = 0.57000 * b2 + w * 1.0526913;
        v = (b0 + b1 + b2 + w * 0.1848) * 0.055;
      case NoiseScene.brown:
        brown = (brown + 0.02 * w) / 1.02;
        v = brown * 1.7;
      case NoiseScene.rain:
        brown = (brown + 0.02 * w) / 1.02;
        if (dropEnv <= 0.01 && rnd.nextDouble() < 0.0012) dropEnv = 1;
        final crackle = dropEnv > 0.01 ? w * dropEnv * 0.3 : 0.0;
        dropEnv *= 0.999;
        v = brown * 0.95 + w * 0.045 + crackle;
    }
    // 首尾 0.35 秒淡入淡出：循环点不爆音。
    final edge = min(i, total - 1 - i).toDouble();
    final fade = min(1.0, edge / (_rate * 0.35));
    v *= fade;
    data[i] = (v.clamp(-1.0, 1.0) * 32767 * 0.9).round();
  }
  return _wav(data);
}

Uint8List _wav(Int16List samples) {
  final dataLen = samples.length * 2;
  final out = Uint8List(44 + dataLen);
  final header = ByteData.view(out.buffer, 0, 44);
  void writeAscii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      out[offset + i] = s.codeUnitAt(i);
    }
  }

  writeAscii(0, 'RIFF');
  header.setUint32(4, 36 + dataLen, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little); // fmt chunk size
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, 1, Endian.little); // mono
  header.setUint32(24, _rate, Endian.little);
  header.setUint32(28, _rate * 2, Endian.little); // byte rate
  header.setUint16(32, 2, Endian.little); // block align
  header.setUint16(34, 16, Endian.little); // bits
  writeAscii(36, 'data');
  header.setUint32(40, dataLen, Endian.little);

  final body = ByteData.view(out.buffer, 44);
  for (var i = 0; i < samples.length; i++) {
    body.setInt16(i * 2, samples[i], Endian.little);
  }
  return out;
}

/// 专注页的白噪音面板：四个场景 + 音量，点已选中的再点一次即关闭。
Future<void> showNoiseSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return Consumer(
        builder: (ctx, ref, _) {
          final noise = ref.watch(whiteNoiseProvider);
          final controller = ref.read(whiteNoiseProvider.notifier);
          return SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        tr('白噪音'),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(width: 6),
                      Text(
                        tr('盖住环境音，不改变计时'),
                        style: TextStyle(fontSize: 10.5, color: scheme.outline),
                      ),
                      Spacer(),
                      if (noise.playing)
                        TextButton(
                          onPressed: controller.stop,
                          child: Text(
                            tr('关闭'),
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: 8),
                  Row(
                    children: [
                      for (final scene in NoiseScene.values) ...[
                        if (scene != NoiseScene.values.first)
                          SizedBox(width: 8),
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => controller.toggle(scene),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: noise.scene == scene
                                    ? scheme.primaryContainer.withValues(
                                        alpha: 0.7,
                                      )
                                    : scheme.surfaceContainerHighest.withValues(
                                        alpha: 0.5,
                                      ),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: noise.scene == scene
                                      ? scheme.primary.withValues(alpha: 0.5)
                                      : Colors.transparent,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    scene.icon,
                                    size: 18,
                                    color: noise.scene == scene
                                        ? scheme.primary
                                        : scheme.onSurfaceVariant,
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    scene.label,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: noise.scene == scene
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: noise.scene == scene
                                          ? scheme.primary
                                          : scheme.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.volume_down,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                      Expanded(
                        child: Slider(
                          value: noise.volume,
                          onChanged: controller.setVolume,
                        ),
                      ),
                      Icon(
                        Icons.volume_up,
                        size: 16,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}
