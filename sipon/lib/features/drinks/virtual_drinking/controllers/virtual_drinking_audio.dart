import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import '../models/virtual_drinking_models.dart';

class VirtualDrinkingAudio {
  final AudioPlayer _ambient = AudioPlayer();
  final AudioPlayer _effect = AudioPlayer();
  Future<void> _pending = Future<void>.value();
  bool _disposed = false;
  String? _playingPath;

  static const _bundled = {
    'virtual_drinking/audio/rain_window':
        'virtual_drinking/audio/rain_window.wav',
    'virtual_drinking/audio/ocean_waves':
        'virtual_drinking/audio/ocean_waves.wav',
  };

  static const _effects = {
    'sip_soft': 'virtual_drinking/audio/sip_soft.wav',
    'sip_water': 'virtual_drinking/audio/sip_water.wav',
    'ice_drop': 'virtual_drinking/audio/ice_drop.wav',
    'ice_crush': 'virtual_drinking/audio/ice_crush.wav',
  };

  bool supports(VirtualSoundPreset preset) =>
      _bundled.containsKey(preset.assetKey);

  Future<void> playEffect(String key) async {
    final path = _effects[key];
    if (_disposed || path == null) return;
    await _effect.stop();
    await _effect.setVolume(0.52);
    await _effect.play(AssetSource(path));
  }

  Future<void> update({
    required VirtualScene scene,
    required VirtualDrinkingCatalog catalog,
    required VirtualDrinkingPreference preference,
    required bool pageVisible,
  }) {
    if (_disposed) return Future<void>.value();
    final preset = catalog.soundPresets
        .where((item) => item.code == scene.ambientSoundCode && supports(item))
        .firstOrNull;
    final path = preset == null ? null : _bundled[preset.assetKey];
    _pending = _pending.catchError((Object _) {}).then((_) async {
      if (_disposed) return;
      if (!pageVisible || !preference.ambientSoundEnabled || path == null) {
        if (_playingPath != null) await _ambient.stop();
        _playingPath = null;
        return;
      }
      if (_playingPath == path) {
        await _ambient.setVolume(preference.ambientSoundVolume / 100);
        return;
      }
      if (_playingPath != null) await _ambient.stop();
      _playingPath = null;
      await _ambient.setReleaseMode(
        preset!.loop ? ReleaseMode.loop : ReleaseMode.stop,
      );
      await _ambient.setVolume(preference.ambientSoundVolume / 100);
      await _ambient.play(AssetSource(path));
      _playingPath = path;
    });
    return _pending;
  }

  Future<void> dispose() async {
    _disposed = true;
    await _pending.catchError((Object _) {});
    await _ambient.dispose();
    await _effect.dispose();
  }
}
