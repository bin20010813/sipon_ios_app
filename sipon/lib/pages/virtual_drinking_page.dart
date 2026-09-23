import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/sipon_api_service.dart';
import '../services/sipon_auth_service.dart';
import '../services/virtual_drinking_audio.dart';
import '../services/virtual_drinking_local_store.dart';
import '../services/virtual_drinking_models.dart';
import '../widgets/virtual_drinking_canvas.dart';
import 'language_transform.dart';

/// 虚拟饮品体验。杯量与互动次数仅存在本机，不写入真实饮酒记录。
class VirtualDrinkingPage extends StatefulWidget {
  const VirtualDrinkingPage({
    super.key,
    this.initialDrinkCode,
    this.initialSceneCode,
    this.apiService,
    this.localStore,
    this.audio,
  });

  final String? initialDrinkCode;
  final String? initialSceneCode;
  final SiponApiService? apiService;
  final VirtualDrinkingLocalStore? localStore;
  final VirtualDrinkingAudio? audio;

  @override
  State<VirtualDrinkingPage> createState() => _VirtualDrinkingPageState();
}

class _VirtualDrinkingPageState extends State<VirtualDrinkingPage>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late final SiponApiService _api;
  late final VirtualDrinkingLocalStore _local;
  late final VirtualDrinkingAudio _audio;
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  )..repeat();
  late final AnimationController _fill = AnimationController(
    vsync: this,
    value: 1,
  );

  VirtualDrinkingCatalog? _catalog;
  VirtualDrinkingPreference? _preference;
  VirtualDrink? _drink;
  VirtualDrink? _detail;
  bool _loading = true;
  String? _error;
  bool _detailLoading = false;
  bool _tilting = false;
  bool _pageVisible = true;
  double _remainingTarget = 1;
  int _sipCount = 0;
  int _todayCount = 0;
  int _detailRequest = 0;
  Timer? _holdTimer;
  Timer? _tiltTimer;
  Timer? _saveTimer;
  VirtualDrinkingPreference? _pendingPreference;
  bool _savingPreference = false;

  @override
  void initState() {
    super.initState();
    _api = widget.apiService ?? SiponApiService();
    _local = widget.localStore ?? VirtualDrinkingLocalStore();
    _audio = widget.audio ?? VirtualDrinkingAudio();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _pageVisible = state == AppLifecycleState.resumed;
    if (!_pageVisible) _stopHolding();
    _syncAudio();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopHolding();
    _tiltTimer?.cancel();
    _saveTimer?.cancel();
    unawaited(_flushPreference());
    unawaited(_audio.dispose());
    _motion.dispose();
    _fill.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = VirtualDrinkingCatalog.fromJson(
        await _api.getVirtualDrinkingBootstrap(),
      );
      if (catalog.drinks.isEmpty ||
          catalog.glasses.isEmpty ||
          catalog.scenes.isEmpty) {
        throw StateError('虚拟饮品目录暂时为空');
      }
      final localPreference = await _local.loadPreference();
      var preference = localPreference ?? catalog.defaults;
      if (SiponAuthService.instance.session != null) {
        try {
          preference = VirtualDrinkingPreference.fromJson(
            await _api.getVirtualDrinkingPreferences(),
          );
        } on Exception {
          // 网络不可用时仍可按本机上次选择进入体验。
        }
      }
      final chosenDrink =
          catalog.drink(widget.initialDrinkCode ?? preference.drinkCode) ??
          catalog.drink(preference.drinkCode) ??
          catalog.drinks.first;
      final chosenScene =
          catalog.scene(widget.initialSceneCode ?? preference.sceneCode) ??
          catalog.scenes.first;
      if (widget.initialDrinkCode != null &&
          chosenDrink.code != preference.drinkCode) {
        preference = preference.copyWith(
          drinkCode: chosenDrink.code,
          glassCode: chosenDrink.defaultGlassCode,
          iceCode: chosenDrink.defaultIceCode,
        );
      }
      preference = _validPreference(
        catalog,
        chosenDrink,
        chosenScene,
        preference,
      );
      final todayCount = await _local.loadTodayCount(DateTime.now());
      if (!mounted) return;
      _lastSipDate = DateTime.now();
      setState(() {
        _catalog = catalog;
        _preference = preference;
        _drink = chosenDrink;
        _detail = null;
        _todayCount = todayCount;
        _loading = false;
      });
      unawaited(_local.savePreference(preference));
      if (widget.initialDrinkCode != null || widget.initialSceneCode != null) {
        _queuePreference(preference);
      }
      _syncAudio();
      unawaited(_loadDetail(chosenDrink.code));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error is StateError ? error.message : '加载虚拟饮品失败，请检查网络后重试';
      });
    }
  }

  VirtualDrinkingPreference _validPreference(
    VirtualDrinkingCatalog catalog,
    VirtualDrink drink,
    VirtualScene scene,
    VirtualDrinkingPreference preference,
  ) {
    final glass =
        catalog.glass(preference.glassCode) ??
        catalog.glass(drink.defaultGlassCode) ??
        catalog.glasses.first;
    final ice = drink.allowedIceCodes.contains(preference.iceCode)
        ? preference.iceCode
        : drink.defaultIceCode;
    return preference.copyWith(
      drinkCode: drink.code,
      glassCode: glass.code,
      sceneCode: scene.code,
      iceCode: ice,
    );
  }

  Future<void> _loadDetail(String code) async {
    final request = ++_detailRequest;
    setState(() => _detailLoading = true);
    try {
      final detail = VirtualDrink.fromJson(await _api.getVirtualDrink(code));
      if (!mounted || request != _detailRequest || _drink?.code != code) return;
      setState(() => _detail = detail);
    } on Exception {
      // 摘要仍能驱动画面；知识卡保留摘要内容。
    } finally {
      if (mounted && request == _detailRequest) {
        setState(() => _detailLoading = false);
      }
    }
  }

  void _changeDrink(VirtualDrink drink) {
    final catalog = _catalog!;
    final preference = _preference!;
    final glass =
        catalog.glass(drink.defaultGlassCode) ?? catalog.glasses.first;
    final ice = drink.allowedIceCodes.contains(drink.defaultIceCode)
        ? drink.defaultIceCode
        : (drink.allowedIceCodes.isEmpty
              ? 'none'
              : drink.allowedIceCodes.first);
    final next = preference.copyWith(
      drinkCode: drink.code,
      glassCode: glass.code,
      iceCode: ice,
    );
    _stopHolding();
    _remainingTarget = 1;
    _fill.value = 1;
    setState(() {
      _drink = drink;
      _detail = null;
      _sipCount = 0;
      _preference = next;
    });
    _queuePreference(next);
    unawaited(_loadDetail(drink.code));
  }

  void _changePreference(VirtualDrinkingPreference next) {
    setState(() => _preference = next);
    _queuePreference(next);
    _syncAudio();
  }

  void _queuePreference(VirtualDrinkingPreference value) {
    unawaited(_local.savePreference(value));
    if (SiponAuthService.instance.session == null) return;
    _pendingPreference = value;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 550), () {
      unawaited(_flushPreference());
    });
  }

  Future<void> _flushPreference() async {
    if (_savingPreference || SiponAuthService.instance.session == null) return;
    _savingPreference = true;
    try {
      while (_pendingPreference != null) {
        final value = _pendingPreference!;
        _pendingPreference = null;
        try {
          await _api.updateVirtualDrinkingPreferences(value.toJson());
        } on Exception {
          // 本机偏好已保存；下一次修改时再尝试远端同步。
        }
      }
    } finally {
      _savingPreference = false;
    }
  }

  void _syncAudio() {
    final catalog = _catalog;
    final preference = _preference;
    if (catalog == null || preference == null) return;
    final scene = catalog.scene(preference.sceneCode);
    if (scene == null) return;
    unawaited(
      _audio
          .update(
            scene: scene,
            catalog: catalog,
            preference: preference,
            pageVisible: _pageVisible,
          )
          .catchError((Object _) {}),
    );
  }

  void _sip() {
    final drink = _drink;
    if (drink == null || _remainingTarget <= 0.005) return;
    final sipSound = drink.interactionPreset['sipSound'];
    if (sipSound is String) {
      unawaited(_audio.playEffect(sipSound).catchError((Object _) {}));
    }
    final now = DateTime.now();
    final end = (_remainingTarget - drink.sipAmount).clamp(0.0, 1.0);
    _remainingTarget = end;
    unawaited(
      _fill.animateTo(
        end,
        duration: const Duration(milliseconds: 330),
        curve: Curves.easeOutCubic,
      ),
    );
    final previousDay = _lastSipDate;
    setState(() {
      if (previousDay == null || !_sameDay(previousDay, now)) _todayCount = 0;
      _lastSipDate = now;
      _sipCount++;
      _todayCount++;
      _tilting = true;
    });
    unawaited(_local.saveTodayCount(now, _todayCount));
    _tiltTimer?.cancel();
    _tiltTimer = Timer(const Duration(milliseconds: 270), () {
      if (mounted) setState(() => _tilting = false);
    });
  }

  DateTime? _lastSipDate;
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _startHolding() {
    _sip();
    _holdTimer?.cancel();
    _holdTimer = Timer.periodic(
      Duration(milliseconds: _drink?.holdRepeatMs ?? 650),
      (_) {
        if (_remainingTarget <= 0.005) {
          _stopHolding();
        } else {
          _sip();
        }
      },
    );
  }

  void _stopHolding() {
    _holdTimer?.cancel();
    _holdTimer = null;
  }

  void _refill() {
    _remainingTarget = 1;
    _fill.animateTo(
      1,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
    );
    setState(() => _sipCount = 0);
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    if (_loading || _error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFF1B2430),
        body: SafeArea(
          child: Center(
            child: _loading
                ? const CircularProgressIndicator(color: Color(0xFFE6D2A2))
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.cloud_off_rounded,
                        color: Colors.white70,
                        size: 42,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.white70),
                      ),
                      const SizedBox(height: 14),
                      FilledButton(onPressed: _load, child: Text(text.t('重试'))),
                      TextButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: Text(text.t('返回首页')),
                      ),
                    ],
                  ),
          ),
        ),
      );
    }

    final catalog = _catalog!;
    final preference = _preference!;
    final drink = _drink!;
    final scene = catalog.scene(preference.sceneCode) ?? catalog.scenes.first;
    final glass = catalog.glass(preference.glassCode) ?? catalog.glasses.first;
    final soundAvailable = catalog.soundPresets.any(
      (preset) =>
          preset.code == scene.ambientSoundCode && _audio.supports(preset),
    );

    return Scaffold(
      backgroundColor: scene.backgroundColors.first,
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _motion,
              builder: (_, _) =>
                  VirtualSceneCanvas(scene: scene, progress: _motion.value),
            ),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x66000000),
                    Colors.transparent,
                    Color(0xAA090B11),
                  ],
                  stops: [0, 0.5, 1],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                _topBar(text),
                Expanded(
                  child: _stage(
                    catalog,
                    drink,
                    glass,
                    scene,
                    soundAvailable,
                    text,
                  ),
                ),
                AnimatedBuilder(
                  animation: _fill,
                  builder: (_, _) => _bottomInfo(drink, scene, text),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(SiponAppText text) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 18, 0),
    child: Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Colors.white,
          ),
          tooltip: text.t('返回'),
        ),
        const Spacer(),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              text.t('虚拟小酌'),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                letterSpacing: 2,
              ),
            ),
            Text(
              text.isZh
                  ? '今日虚拟喝了 $_todayCount 口'
                  : '$_todayCount virtual sips today',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _stage(
    VirtualDrinkingCatalog catalog,
    VirtualDrink drink,
    VirtualGlass glass,
    VirtualScene scene,
    bool soundAvailable,
    SiponAppText text,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final height = constraints.maxHeight;
      final glassWidth = math.min(width * 0.58, 250.0);
      final glassHeight = glassWidth * 1.24;
      final anchor = scene.glassAnchor;
      final left = (width * anchor.dx - glassWidth / 2 - 16)
          .clamp(6.0, math.max(6.0, width - glassWidth - 52))
          .toDouble();
      final top = (height * anchor.dy - glassHeight / 2)
          .clamp(0.0, math.max(0.0, height - glassHeight))
          .toDouble();
      return Stack(
        children: [
          Positioned(
            left: left,
            top: top,
            width: glassWidth,
            height: glassHeight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (_remainingTarget <= 0.005) {
                  _refill();
                } else {
                  _sip();
                }
              },
              onLongPressStart: (_) => _startHolding(),
              onLongPressEnd: (_) => _stopHolding(),
              onLongPressCancel: _stopHolding,
              child: Semantics(
                button: true,
                label: text.t('点杯子喝一口，长按连喝'),
                child: AnimatedRotation(
                  turns: _tilting ? -0.025 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_fill, _motion]),
                    builder: (_, _) => VirtualGlassCanvas(
                      drink: drink,
                      glass: glass,
                      iceCode: _preference!.iceCode,
                      remaining: _fill.value,
                      progress: _motion.value,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: 8,
            top: 10,
            bottom: 10,
            width: 67,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _rail(Icons.local_bar_outlined, text.t('换饮品'), _showDrinks),
                  _rail(Icons.wine_bar_outlined, text.t('换杯'), _showGlasses),
                  _rail(Icons.landscape_outlined, text.t('换场景'), _showScenes),
                  _rail(Icons.ac_unit_rounded, text.t('加冰'), _showIce),
                  _rail(
                    Icons.water_drop_outlined,
                    text.t('喝水'),
                    _switchToWater,
                  ),
                  if (soundAvailable)
                    _rail(
                      _preference!.ambientSoundEnabled
                          ? Icons.volume_up_outlined
                          : Icons.volume_off_outlined,
                      text.t('环境声'),
                      _showSound,
                    ),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 10,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _fill,
              builder: (_, _) => _remainingTarget > 0.005
                  ? const SizedBox.shrink()
                  : Center(
                      child: FilledButton.tonal(
                        onPressed: _refill,
                        child: Text(text.t('再来一杯')),
                      ),
                    ),
            ),
          ),
        ],
      );
    },
  );

  Widget _rail(IconData icon, String label, VoidCallback onPressed) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Icon(icon, color: Colors.white.withValues(alpha: 0.92), size: 26),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _bottomInfo(
    VirtualDrink drink,
    VirtualScene scene,
    SiponAppText text,
  ) => Container(
    width: double.infinity,
    padding: const EdgeInsets.fromLTRB(24, 19, 24, 20),
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xBA1A1719), Color(0xF0121014)],
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                drink.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            IconButton.filledTonal(
              onPressed: _showKnowledge,
              icon: const Icon(Icons.menu_book_outlined),
              tooltip: text.t('了解这杯'),
            ),
          ],
        ),
        Text(
          [
            drink.subtitle,
            scene.name,
          ].where((item) => item.isNotEmpty).join(' · '),
          style: const TextStyle(color: Color(0xFFE3D5CB), fontSize: 13),
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _infoChip(text.isZh ? '本杯第 $_sipCount 口' : 'Sip $_sipCount'),
            if (drink.category == 'non_alcoholic') _infoChip(text.t('无酒精')),
            for (final tag in drink.flavorTags.take(2)) _infoChip(tag),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          _remainingTarget <= 0.005
              ? text.t('已喝完，点杯子或“再来一杯”续杯')
              : text.t('点杯子喝一口 · 长按连喝 · 点书本看配方'),
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 11,
            height: 1.4,
          ),
        ),
      ],
    ),
  );

  Widget _infoChip(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
    ),
    child: Text(
      label,
      style: const TextStyle(color: Colors.white, fontSize: 11),
    ),
  );

  void _showDrinks() {
    final text = SiponLanguageScope.textOf(context);
    var query = '';
    var category = '';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFFF8F5F2),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, update) {
          final drinks = _catalog!.drinks
              .where(
                (drink) =>
                    (category.isEmpty || drink.category == category) &&
                    (query.isEmpty ||
                        drink.name.contains(query) ||
                        drink.name.toLowerCase().contains(
                          query.toLowerCase(),
                        ) ||
                        drink.code.contains(query)),
              )
              .toList();
          return FractionallySizedBox(
            heightFactor: 0.76,
            child: Column(
              children: [
                _sheetTitle(text.t('换饮品')),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: TextField(
                    onChanged: (value) => update(() => query = value.trim()),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: text.t('搜索饮品'),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
                  child: Row(
                    children: [
                      for (final entry in [
                        ('', text.t('全部')),
                        ('cocktail', text.t('鸡尾酒')),
                        ('beer', text.t('啤酒')),
                        ('non_alcoholic', text.t('无酒精')),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(entry.$2),
                            selected: category == entry.$1,
                            onSelected: (_) =>
                                update(() => category = entry.$1),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: drinks.isEmpty
                      ? Center(child: Text(text.t('没有找到饮品')))
                      : ListView.builder(
                          itemCount: drinks.length,
                          itemBuilder: (context, index) {
                            final drink = drinks[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: drink.liquidColor.withValues(
                                  alpha: 0.35,
                                ),
                                child: Icon(
                                  Icons.local_bar_rounded,
                                  color: drink.liquidColor,
                                ),
                              ),
                              title: Text(drink.name),
                              subtitle: Text(drink.subtitle),
                              trailing: drink.code == _drink?.code
                                  ? const Icon(
                                      Icons.check_circle,
                                      color: Color(0xFF9A3D78),
                                    )
                                  : null,
                              onTap: () {
                                Navigator.of(sheetContext).pop();
                                _changeDrink(drink);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _sheetTitle(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
      ),
    ),
  );

  void _showGlasses() {
    final text = SiponLanguageScope.textOf(context);
    final drink = _drink!;
    final glasses = [..._catalog!.glasses]
      ..sort((a, b) {
        final ai = drink.recommendedGlassCodes.contains(a.code) ? 0 : 1;
        final bi = drink.recommendedGlassCodes.contains(b.code) ? 0 : 1;
        return ai.compareTo(bi);
      });
    _showOptions(
      title: text.t('换杯'),
      options: [
        for (final glass in glasses)
          _PickOption(
            code: glass.code,
            title: glass.name,
            subtitle: drink.recommendedGlassCodes.contains(glass.code)
                ? text.t('适合这杯饮品')
                : '',
            icon: Icons.wine_bar_outlined,
          ),
      ],
      selected: _preference!.glassCode,
      onPick: (code) =>
          _changePreference(_preference!.copyWith(glassCode: code)),
    );
  }

  void _showScenes() {
    final text = SiponLanguageScope.textOf(context);
    _showOptions(
      title: text.t('换场景'),
      options: [
        for (final scene in _catalog!.scenes)
          _PickOption(
            code: scene.code,
            title: scene.name,
            icon: Icons.landscape_outlined,
          ),
      ],
      selected: _preference!.sceneCode,
      onPick: (code) =>
          _changePreference(_preference!.copyWith(sceneCode: code)),
    );
  }

  void _showIce() {
    final text = SiponLanguageScope.textOf(context);
    final allowed = _drink!.allowedIceCodes;
    _showOptions(
      title: text.t('加冰'),
      options: [
        for (final item in _catalog!.iceOptions)
          if (allowed.contains(item.code))
            _PickOption(
              code: item.code,
              title: item.name,
              subtitle: item.description,
              icon: Icons.ac_unit_rounded,
            ),
      ],
      selected: _preference!.iceCode,
      onPick: (code) {
        _changePreference(_preference!.copyWith(iceCode: code));
        final sounds = _drink!.interactionPreset['iceSounds'];
        final sound = sounds is Map ? sounds[code] : null;
        if (sound is String) {
          unawaited(_audio.playEffect(sound).catchError((Object _) {}));
        }
      },
    );
  }

  void _switchToWater() {
    final water = _catalog!.drinks
        .where((drink) => drink.category == 'non_alcoholic')
        .firstOrNull;
    if (water == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('当前目录暂无无酒精饮品')));
      return;
    }
    _changeDrink(water);
  }

  Future<void> _showOptions({
    required String title,
    required List<_PickOption> options,
    required String selected,
    required ValueChanged<String> onPick,
  }) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    backgroundColor: const Color(0xFFF8F5F2),
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _sheetTitle(title),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, index) {
                final option = options[index];
                return ListTile(
                  leading: Icon(option.icon, color: const Color(0xFF8B627B)),
                  title: Text(option.title),
                  subtitle: option.subtitle.isEmpty
                      ? null
                      : Text(option.subtitle),
                  trailing: option.code == selected
                      ? const Icon(Icons.check_circle, color: Color(0xFF9A3D78))
                      : null,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    onPick(option.code);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 10),
        ],
      ),
    ),
  );

  void _showSound() {
    final text = SiponLanguageScope.textOf(context);
    var current = _preference!;
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      backgroundColor: const Color(0xFFF8F5F2),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, update) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sheetTitle(text.t('环境声')),
              SwitchListTile(
                title: Text(text.t('播放场景环境声')),
                value: current.ambientSoundEnabled,
                onChanged: (value) {
                  update(
                    () =>
                        current = current.copyWith(ambientSoundEnabled: value),
                  );
                  _changePreference(current);
                },
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 18),
                child: Row(
                  children: [
                    const Icon(Icons.volume_down_outlined),
                    Expanded(
                      child: Slider(
                        value: current.ambientSoundVolume.toDouble(),
                        max: 100,
                        divisions: 20,
                        label: '${current.ambientSoundVolume}%',
                        onChanged: current.ambientSoundEnabled
                            ? (value) {
                                update(
                                  () => current = current.copyWith(
                                    ambientSoundVolume: value.round(),
                                  ),
                                );
                                _changePreference(current);
                              }
                            : null,
                      ),
                    ),
                    const Icon(Icons.volume_up_outlined),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showKnowledge() async {
    final text = SiponLanguageScope.textOf(context);
    if (_detail == null && !_detailLoading) await _loadDetail(_drink!.code);
    if (!mounted) return;
    final drink = _detail ?? _drink!;
    final recipe = drink.recipe;
    final ingredients = recipe?['ingredients'] is List
        ? (recipe!['ingredients'] as List).whereType<Map>().toList()
        : const <Map>[];
    final story =
        (recipe?['backgroundStory'] as String?)?.trim().isNotEmpty == true
        ? recipe!['backgroundStory'] as String
        : drink.backgroundStory;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFFF8F5F2),
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.78,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
          children: [
            _sheetTitle(drink.name),
            if (drink.subtitle.isNotEmpty)
              Text(
                drink.subtitle,
                style: const TextStyle(color: Color(0xFF786C74)),
              ),
            _knowledgeBlock(text.t('简介'), drink.description),
            if (ingredients.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                text.t('配方用料'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              for (final ingredient in ingredients)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(ingredient['name']?.toString() ?? ''),
                  trailing: Text(ingredient['amountText']?.toString() ?? ''),
                ),
            ],
            _knowledgeBlock(
              text.t('风味与结构'),
              recipe?['attributeLogic']?.toString() ?? '',
            ),
            _knowledgeBlock(text.t('背景故事'), story),
            _knowledgeBlock(
              text.t('制作技法'),
              recipe?['technique']?.toString() ?? '',
            ),
            _knowledgeBlock(
              text.t('在家替代'),
              recipe?['homeSubstitution']?.toString() ?? '',
            ),
          ],
        ),
      ),
    );
  }

  Widget _knowledgeBlock(String title, String content) {
    if (content.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            content,
            style: const TextStyle(
              fontSize: 14,
              height: 1.55,
              color: Color(0xFF554C52),
            ),
          ),
        ],
      ),
    );
  }
}

class _PickOption {
  const _PickOption({
    required this.code,
    required this.title,
    required this.icon,
    this.subtitle = '',
  });

  final String code;
  final String title;
  final String subtitle;
  final IconData icon;
}
