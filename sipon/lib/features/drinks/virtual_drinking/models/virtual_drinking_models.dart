import 'package:flutter/material.dart';

Map<String, dynamic> _map(dynamic value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : const {};

String _string(dynamic value, [String fallback = '']) =>
    value is String ? value : fallback;

double _number(dynamic value, double fallback) =>
    value is num ? value.toDouble() : fallback;

List<String> _strings(dynamic value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const [];

List<T> _items<T>(dynamic value, T Function(dynamic) parse) => value is List
    ? value.whereType<Map>().map(parse).toList(growable: false)
    : const [];

Color virtualColor(dynamic value, Color fallback) {
  final source = _string(value);
  final hex = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(source)?.group(1);
  return hex == null ? fallback : Color(int.parse('FF$hex', radix: 16));
}

class VirtualDrinkingCatalog {
  const VirtualDrinkingCatalog({
    required this.drinks,
    required this.glasses,
    required this.scenes,
    required this.iceOptions,
    required this.soundPresets,
    required this.defaults,
    required this.contentVersion,
    required this.rendererVersion,
    this.modelRendererVersion = '',
    this.assets = const [],
  });

  factory VirtualDrinkingCatalog.fromJson(dynamic value) {
    final data = _map(value);
    return VirtualDrinkingCatalog(
      drinks: _items(data['drinks'], VirtualDrink.fromJson),
      glasses: _items(data['glasses'], VirtualGlass.fromJson),
      scenes: _items(data['scenes'], VirtualScene.fromJson),
      iceOptions: _items(data['iceOptions'], VirtualIceOption.fromJson),
      soundPresets: _items(data['soundPresets'], VirtualSoundPreset.fromJson),
      defaults: VirtualDrinkingPreference.fromJson(data['preferenceDefaults']),
      contentVersion: _string(data['contentVersion']),
      rendererVersion: _string(data['rendererVersion']),
      modelRendererVersion: _string(data['modelRendererVersion']),
      assets: _items(data['assets'], VirtualModelAsset.fromJson),
    );
  }

  final List<VirtualDrink> drinks;
  final List<VirtualGlass> glasses;
  final List<VirtualScene> scenes;
  final List<VirtualIceOption> iceOptions;
  final List<VirtualSoundPreset> soundPresets;
  final VirtualDrinkingPreference defaults;
  final String contentVersion;
  final String rendererVersion;
  final String modelRendererVersion;
  final List<VirtualModelAsset> assets;

  VirtualModelAsset? asset(String code) {
    for (final item in assets) {
      if (item.code == code) return item;
    }
    return null;
  }

  VirtualDrink? drink(String code) {
    for (final item in drinks) {
      if (item.code == code) return item;
    }
    return null;
  }

  VirtualGlass? glass(String code) {
    for (final item in glasses) {
      if (item.code == code) return item;
    }
    return null;
  }

  VirtualScene? scene(String code) {
    for (final item in scenes) {
      if (item.code == code) return item;
    }
    return null;
  }
}

class VirtualDrink {
  const VirtualDrink({
    required this.code,
    required this.name,
    required this.category,
    required this.subtitle,
    required this.description,
    required this.backgroundStory,
    required this.flavorTags,
    required this.defaultGlassCode,
    required this.recommendedGlassCodes,
    required this.defaultIceCode,
    required this.allowedIceCodes,
    required this.renderConfig,
    required this.interactionPreset,
    required this.recipe,
    required this.cocktailId,
  });

  factory VirtualDrink.fromJson(dynamic value) {
    final data = _map(value);
    return VirtualDrink(
      code: _string(data['code']),
      name: _string(data['name']),
      category: _string(data['category']),
      subtitle: _string(data['subtitle']),
      description: _string(data['description']),
      backgroundStory: _string(data['backgroundStory']),
      flavorTags: _strings(data['flavorTags']),
      defaultGlassCode: _string(data['defaultGlassCode']),
      recommendedGlassCodes: _strings(data['recommendedGlassCodes']),
      defaultIceCode: _string(data['defaultIceCode']),
      allowedIceCodes: _strings(data['allowedIceCodes']),
      renderConfig: _map(data['renderConfig']),
      interactionPreset: _map(data['interactionPreset']),
      recipe: data['recipe'] is Map ? _map(data['recipe']) : null,
      cocktailId: data['cocktailId'] is num
          ? (data['cocktailId'] as num).toInt()
          : null,
    );
  }

  final String code;
  final String name;
  final String category;
  final String subtitle;
  final String description;
  final String backgroundStory;
  final List<String> flavorTags;
  final String defaultGlassCode;
  final List<String> recommendedGlassCodes;
  final String defaultIceCode;
  final List<String> allowedIceCodes;
  final Map<String, dynamic> renderConfig;
  final Map<String, dynamic> interactionPreset;
  final Map<String, dynamic>? recipe;
  final int? cocktailId;

  Color get liquidColor =>
      virtualColor(renderConfig['color'], const Color(0xFFB8D4C4));
  Color get foamColor =>
      virtualColor(renderConfig['foamColor'], const Color(0xFFF4E6C7));
  double get opacity => _number(renderConfig['opacity'], 0.8).clamp(0.1, 1);
  bool get bubbles => renderConfig['bubbles'] == true;
  bool get foam => renderConfig['foam'] == true;
  List<String> get garnish => _strings(renderConfig['garnish']);
  double get sipAmount =>
      _number(interactionPreset['sipAmount'], 0.08).clamp(0.01, 0.5);
  int get holdRepeatMs =>
      _number(interactionPreset['holdRepeatMs'], 650).round().clamp(250, 3000);
}

class VirtualGlass {
  const VirtualGlass({
    required this.code,
    required this.name,
    required this.renderConfig,
  });

  factory VirtualGlass.fromJson(dynamic value) {
    final data = _map(value);
    return VirtualGlass(
      code: _string(data['code']),
      name: _string(data['name']),
      renderConfig: _map(data['renderConfig']),
    );
  }

  final String code;
  final String name;
  final Map<String, dynamic> renderConfig;

  String get shape => _string(renderConfig['shape'], 'highball');
  double get maxFill => _number(renderConfig['maxFill'], 0.76).clamp(0.25, 0.9);
  double get liquidInset =>
      _number(renderConfig['liquidInset'], 0.09).clamp(0.02, 0.25);
  Map<String, dynamic> get model3d => _map(renderConfig['model3d']);
  String get modelAssetCode => _string(model3d['assetCode']);
  List<Map<String, double>> get liquidProfile {
    final profile = _map(model3d['liquidProfile']);
    final points = profile['points'];
    if (points is! List) return const [];
    return points
        .whereType<Map>()
        .map((point) {
          final value = _map(point);
          return {
            'y': _number(value['y'], 0),
            'radius': _number(value['radius'], 0),
          };
        })
        .where((point) => point['radius']! > 0)
        .toList(growable: false);
  }
}

class VirtualModelAsset {
  const VirtualModelAsset({
    required this.code,
    required this.url,
    required this.kind,
    this.title = '',
    this.author = '',
    this.sourceUrl = '',
    this.license = '',
    this.modificationNote = '',
  });

  factory VirtualModelAsset.fromJson(dynamic value) {
    final data = _map(value);
    return VirtualModelAsset(
      code: _string(data['code']),
      url: _string(data['url']),
      kind: _string(data['kind']),
      title: _string(data['title']),
      author: _string(data['author']),
      sourceUrl: _string(data['sourceUrl']),
      license: _string(data['license']),
      modificationNote: _string(data['modificationNote']),
    );
  }

  final String code;
  final String url;
  final String kind;
  final String title;
  final String author;
  final String sourceUrl;
  final String license;
  final String modificationNote;
}

class VirtualScene {
  const VirtualScene({
    required this.code,
    required this.name,
    required this.renderConfig,
    required this.ambientSoundCode,
  });

  factory VirtualScene.fromJson(dynamic value) {
    final data = _map(value);
    return VirtualScene(
      code: _string(data['code']),
      name: _string(data['name']),
      renderConfig: _map(data['renderConfig']),
      ambientSoundCode: _string(data['ambientSoundCode']),
    );
  }

  final String code;
  final String name;
  final Map<String, dynamic> renderConfig;
  final String ambientSoundCode;

  List<Color> get backgroundColors {
    final matches = RegExp(r'#[0-9a-fA-F]{6}')
        .allMatches(_string(renderConfig['background']))
        .take(3)
        .map((match) => virtualColor(match.group(0), Colors.black))
        .toList();
    return matches.length >= 2
        ? matches
        : const [Color(0xFF222D3B), Color(0xFF121C29), Color(0xFF2B2529)];
  }

  Color get accent =>
      virtualColor(renderConfig['accent'], const Color(0xFFB9C5D0));
  Offset get glassAnchor {
    final value = _map(renderConfig['glassAnchor']);
    return Offset(
      _number(value['x'], 0.5).clamp(0.2, 0.8),
      _number(value['y'], 0.53).clamp(0.25, 0.75),
    );
  }
}

class VirtualIceOption {
  const VirtualIceOption({
    required this.code,
    required this.name,
    required this.description,
    this.model3d = const {},
  });

  factory VirtualIceOption.fromJson(dynamic value) {
    final data = _map(value);
    return VirtualIceOption(
      code: _string(data['code']),
      name: _string(data['name']),
      description: _string(data['description']),
      model3d: _map(data['model3d']),
    );
  }

  final String code;
  final String name;
  final String description;
  final Map<String, dynamic> model3d;
  String get renderer => _string(model3d['renderer']);
  String get modelAssetCode => _string(model3d['assetCode']);
}

class VirtualSoundPreset {
  const VirtualSoundPreset({
    required this.code,
    required this.assetKey,
    required this.loop,
  });

  factory VirtualSoundPreset.fromJson(dynamic value) {
    final data = _map(value);
    return VirtualSoundPreset(
      code: _string(data['code']),
      assetKey: _string(data['assetKey']),
      loop: data['loop'] == true,
    );
  }

  final String code;
  final String assetKey;
  final bool loop;
}

class VirtualDrinkingPreference {
  const VirtualDrinkingPreference({
    required this.drinkCode,
    required this.glassCode,
    required this.sceneCode,
    required this.iceCode,
    required this.ambientSoundEnabled,
    required this.ambientSoundVolume,
  });

  factory VirtualDrinkingPreference.fromJson(dynamic value) {
    final data = _map(value);
    return VirtualDrinkingPreference(
      drinkCode: _string(data['drinkCode']),
      glassCode: _string(data['glassCode']),
      sceneCode: _string(data['sceneCode']),
      iceCode: _string(data['iceCode']),
      ambientSoundEnabled: data['ambientSoundEnabled'] != false,
      ambientSoundVolume: _number(
        data['ambientSoundVolume'],
        45,
      ).round().clamp(0, 100),
    );
  }

  final String drinkCode;
  final String glassCode;
  final String sceneCode;
  final String iceCode;
  final bool ambientSoundEnabled;
  final int ambientSoundVolume;

  VirtualDrinkingPreference copyWith({
    String? drinkCode,
    String? glassCode,
    String? sceneCode,
    String? iceCode,
    bool? ambientSoundEnabled,
    int? ambientSoundVolume,
  }) => VirtualDrinkingPreference(
    drinkCode: drinkCode ?? this.drinkCode,
    glassCode: glassCode ?? this.glassCode,
    sceneCode: sceneCode ?? this.sceneCode,
    iceCode: iceCode ?? this.iceCode,
    ambientSoundEnabled: ambientSoundEnabled ?? this.ambientSoundEnabled,
    ambientSoundVolume: ambientSoundVolume ?? this.ambientSoundVolume,
  );

  Map<String, Object?> toJson() => {
    'drinkCode': drinkCode,
    'glassCode': glassCode,
    'sceneCode': sceneCode,
    'iceCode': iceCode,
    'ambientSoundEnabled': ambientSoundEnabled,
    'ambientSoundVolume': ambientSoundVolume,
  };
}
