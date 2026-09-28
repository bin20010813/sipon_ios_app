import 'dart:async';

import 'package:flutter/material.dart';

import '../pages/language_transform.dart';
import '../pages/public_profile_page.dart';
import '../pages/review_detail_page.dart';
import '../pages/sms_login_page.dart';
import '../services/home_moments_repository.dart';
import '../services/sipon_api_client.dart';
import '../services/sipon_api_config.dart';
import '../services/sipon_api_service.dart';
import '../services/sipon_auth_service.dart';
import 'map/venue_detail_page.dart';
import 'sipon_network_image.dart';
import 'check_in_comments_sheet.dart';

/// The home page's public check-in feed. Filtering and sorting are performed
/// by /api/feed/check-ins before pagination, rather than over loaded cards.
class HomeMomentsSection extends StatefulWidget {
  const HomeMomentsSection({
    super.key,
    required this.city,
    this.onCheckInPressed,
    this.repository,
    this.apiService,
  });

  final String city;
  final Future<void> Function()? onCheckInPressed;
  final HomeMomentsRepository? repository;
  final SiponApiService? apiService;

  @override
  State<HomeMomentsSection> createState() => HomeMomentsSectionState();
}

class HomeMomentsSectionState extends State<HomeMomentsSection> {
  static const _brand = Color(0xFF9A3D78);
  static const _ink = Color(0xFF252229);
  static const _muted = Color(0xFF9B939B);
  static const _pageSize = 20;

  late final HomeMomentsRepository _repository =
      widget.repository ?? HomeMomentsRepository();
  late final SiponApiService _api = widget.apiService ?? SiponApiService();
  final _searchController = TextEditingController();
  final List<HomeMoment> _moments = [];
  final Set<int> _reacting = {};
  final Set<int> _following = {};
  int? _viewerId;
  Timer? _searchDebounce;
  List<BarSubtypeOption> _subtypes = const [];
  String? _subtype;
  String _scope = 'all';
  String _sort = 'latest';
  bool _allCities = false;
  int _nextOffset = 0;
  int _generation = 0;
  bool _loading = false;
  bool _hasMore = true;
  bool _failedReplace = false;
  Object? _error;

  bool get _signedIn =>
      SiponAuthService.instance.session != null ||
      SiponApiClient.imageRequestHeaders.isNotEmpty ||
      SiponApiConfig.instance.accessToken.isNotEmpty;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      _loadSubtypes();
      _loadViewerId();
      refresh(clear: true);
    });
  }

  Future<void> _loadViewerId() async {
    if (!_signedIn) return;
    final sessionId = SiponAuthService.instance.session?.user['id'];
    final parsed = sessionId is num
        ? sessionId.toInt()
        : int.tryParse('$sessionId');
    if (parsed != null) {
      if (mounted) setState(() => _viewerId = parsed);
      return;
    }
    try {
      final response = await _api.getMyProfile();
      if (response is Map && mounted) {
        final raw = response['id'] ?? response['userId'];
        setState(
          () => _viewerId = raw is num ? raw.toInt() : int.tryParse('$raw'),
        );
      }
    } on Exception {
      // The feed can still be read if the optional viewer lookup fails.
    }
  }

  @override
  void didUpdateWidget(covariant HomeMomentsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.city != widget.city) {
      _allCities = false;
      refresh(clear: true);
    }
  }

  @override
  void dispose() {
    _generation++;
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSubtypes() async {
    try {
      final result = await _repository.loadBarSubtypes();
      if (mounted) setState(() => _subtypes = result);
    } on Exception {
      // The feed remains available without the optional subtype filter.
    }
  }

  Future<void> refresh({bool clear = false}) async {
    final generation = ++_generation;
    if (!mounted) return;
    setState(() {
      if (clear) _moments.clear();
      _nextOffset = 0;
      _hasMore = true;
      _loading = false;
      _error = null;
      _failedReplace = false;
    });
    await _loadPage(generation: generation, replace: true);
  }

  Future<void> loadMore() async {
    if (!_hasMore || _loading || _moments.isEmpty || _error != null) return;
    await _loadPage(generation: _generation, replace: false);
  }

  Future<void> _loadPage({
    required int generation,
    required bool replace,
  }) async {
    if (!mounted || (_loading && !replace)) return;
    final offset = replace ? 0 : _nextOffset;
    final query = HomeFeedQuery(
      city: _allCities ? null : widget.city,
      keyword: _searchController.text.trim().isEmpty
          ? null
          : _searchController.text.trim(),
      barSubtype: _subtype,
      scope: _scope,
      sort: _sort,
      limit: _pageSize,
      offset: offset,
    );
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _repository.load(query);
      if (!mounted || generation != _generation) return;
      setState(() {
        if (replace) _moments.clear();
        final seen = _moments.map((moment) => moment.id).toSet();
        _moments.addAll(page.items.where((moment) => seen.add(moment.id)));
        _nextOffset = page.offset + page.limit;
        _hasMore = page.hasMore;
      });
    } on Exception catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _error = error;
          _failedReplace = replace;
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  void _onKeywordChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) refresh(clear: true);
    });
  }

  Future<bool> _ensureLogin({bool force = false}) async {
    if (!force && _signedIn) return true;
    final loggedIn = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (pageContext) => SmsLoginPage(
          onLoginSucceeded: () => Navigator.of(pageContext).pop(true),
        ),
      ),
    );
    if (loggedIn == true && mounted) {
      await _loadViewerId();
      await refresh(clear: true);
    }
    return loggedIn == true;
  }

  Future<void> _changeScope(String scope) async {
    if (scope == _scope) return;
    if (scope == 'following' && !await _ensureLogin()) return;
    if (!mounted) return;
    setState(() => _scope = scope);
    await refresh(clear: true);
  }

  Future<void> _toggleLike(HomeMoment moment) async {
    if (_reacting.contains(moment.id)) return;
    if (!await _ensureLogin() || !mounted) return;
    final index = _moments.indexWhere((item) => item.id == moment.id);
    if (index < 0) return;
    final original = _moments[index];
    final next = original.myReaction == 'like' ? null : 'like';
    setState(() {
      _reacting.add(moment.id);
      _moments[index] = original.withReaction(next);
    });
    try {
      await _api.setCheckInReaction(moment.id, next);
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          final current = _moments.indexWhere((item) => item.id == moment.id);
          if (current >= 0) _moments[current] = original;
        });
        _showError(error);
        if (error is SiponApiException && error.statusCode == 401) {
          await _ensureLogin(force: true);
        }
      }
    } finally {
      if (mounted) setState(() => _reacting.remove(moment.id));
    }
  }

  Future<void> _toggleFollow(HomeMoment moment) async {
    final authorId = moment.author.id;
    if (authorId == null ||
        authorId == _viewerId ||
        _following.contains(authorId)) {
      return;
    }
    if (!await _ensureLogin() || !mounted) return;
    final next = moment.author.isFollowing != true;
    setState(() {
      _following.add(authorId);
      for (var i = 0; i < _moments.length; i++) {
        if (_moments[i].author.id == authorId) {
          _moments[i] = _moments[i].withFollowing(next);
        }
      }
    });
    try {
      if (next) {
        await _api.followUser(authorId);
      } else {
        await _api.unfollowUser(authorId);
      }
      if (mounted && _scope == 'following') await refresh();
    } on Exception catch (error) {
      if (mounted) {
        setState(() {
          for (var i = 0; i < _moments.length; i++) {
            if (_moments[i].author.id == authorId) {
              _moments[i] = _moments[i].withFollowing(!next);
            }
          }
        });
        _showError(error);
      }
    } finally {
      if (mounted) setState(() => _following.remove(authorId));
    }
  }

  Future<void> _openComments(HomeMoment moment) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => CheckInCommentsSheet(
        checkInId: moment.id,
        api: _api,
        viewerId: _viewerId,
        ensureLogin: _ensureLogin,
      ),
    );
    if (mounted) await refresh();
  }

  void _showError(Object error) {
    final message = error is SiponApiException
        ? (error.message ?? '操作失败，请重试')
        : '操作失败，请重试';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(SiponLanguageScope.textOf(context).t(message))),
    );
  }

  void _openMoment(HomeMoment moment) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ActivityCheckInDetailPage(moment: moment, api: _api),
      ),
    );
  }

  void _openVenue(HomeMoment moment) {
    if (moment.venue.id.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VenueDetailPage(venue: moment.venue),
      ),
    );
  }

  Future<void> _openAuthor(HomeMoment moment) async {
    final userId = moment.author.id;
    if (userId == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PublicProfilePage(userId: userId),
      ),
    );
    if (mounted && _scope == 'following') await refresh();
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final subtypeName = {
      for (final subtype in _subtypes) subtype.code: subtype.name,
    };
    final error = _error;
    return Padding(
      padding: const EdgeInsets.only(right: 23, top: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  text.t('酒友动态'),
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                tooltip: text.t('刷新动态'),
                onPressed: () => refresh(),
                icon: const Icon(Icons.refresh_rounded, color: _brand),
              ),
              if (widget.onCheckInPressed != null)
                TextButton.icon(
                  onPressed: () async {
                    if (!await _ensureLogin()) return;
                    await widget.onCheckInPressed?.call();
                    if (mounted) await refresh();
                  },
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(text.t('发布打卡')),
                ),
            ],
          ),
          Text(
            text.t(_allCities ? '全部城市的公开打卡' : '当前城市的公开打卡'),
            style: const TextStyle(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: _onKeywordChanged,
            maxLength: 100,
            decoration: InputDecoration(
              hintText: text.t('搜索酒吧或动态内容'),
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: text.t('清除搜索'),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _searchDebounce?.cancel();
                        _searchController.clear();
                        refresh(clear: true);
                      },
                    ),
              counterText: '',
              isDense: true,
              filled: true,
              fillColor: const Color(0xFFF8F5F7),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _filterChip(
                text.t('全部动态'),
                _scope == 'all',
                () => _changeScope('all'),
              ),
              _filterChip(
                text.t('关注'),
                _scope == 'following',
                () => _changeScope('following'),
              ),
              PopupMenuButton<String?>(
                tooltip: text.t('品类'),
                onSelected: (value) {
                  if (_subtype == value) return;
                  setState(() => _subtype = value);
                  refresh(clear: true);
                },
                itemBuilder: (_) => [
                  PopupMenuItem<String?>(
                    value: null,
                    child: Text(text.t('全部品类')),
                  ),
                  for (final option in _subtypes)
                    PopupMenuItem<String?>(
                      value: option.code,
                      child: Text(text.t(option.name)),
                    ),
                ],
                child: _filterLabel(text.t(subtypeName[_subtype] ?? '全部品类')),
              ),
              PopupMenuButton<String>(
                tooltip: text.t('排序'),
                onSelected: (value) {
                  if (_sort == value) return;
                  setState(() => _sort = value);
                  refresh(clear: true);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(value: 'latest', child: Text(text.t('最新优先'))),
                  PopupMenuItem(value: 'popular', child: Text(text.t('热门优先'))),
                ],
                child: _filterLabel(
                  text.t(_sort == 'popular' ? '热门优先' : '最新优先'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    error is SiponApiException && error.statusCode == 401
                        ? text.t(
                            _scope == 'following' ? '请登录后查看关注动态' : '请登录后重试动态',
                          )
                        : error is SiponApiException &&
                              error.message?.trim().isNotEmpty == true
                        ? error.message!
                        : text.t('动态加载失败，请重试'),
                    style: const TextStyle(color: _muted, fontSize: 13),
                  ),
                  TextButton(
                    onPressed: () async {
                      if (error is SiponApiException &&
                          error.statusCode == 401) {
                        await _ensureLogin(force: true);
                        return;
                      }
                      if (_failedReplace) {
                        await refresh(clear: _moments.isEmpty);
                      } else {
                        await _loadPage(
                          generation: _generation,
                          replace: false,
                        );
                      }
                    },
                    child: Text(text.t('重试')),
                  ),
                ],
              ),
            ),
          if (_moments.isEmpty && !_loading && error == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text.t(
                      _scope == 'following' ? '还没有关注用户的公开动态' : '这里还没有打卡动态',
                    ),
                    style: const TextStyle(color: _muted, fontSize: 13),
                  ),
                  if (_scope == 'all')
                    TextButton(
                      onPressed: () {
                        setState(() => _allCities = !_allCities);
                        refresh(clear: true);
                      },
                      child: Text(text.t(_allCities ? '返回当前城市' : '查看全部城市')),
                    ),
                ],
              ),
            ),
          for (final moment in _moments) ...[
            _MomentCard(
              key: ValueKey(moment.id),
              moment: moment,
              subtypeName: subtypeName[moment.barSubtype],
              onOpen: () => _openMoment(moment),
              onOpenVenue: () => _openVenue(moment),
              onOpenAuthor: moment.author.id == null
                  ? null
                  : () => _openAuthor(moment),
              onLike: () => _toggleLike(moment),
              onFollow:
                  moment.author.id == null || moment.author.id == _viewerId
                  ? null
                  : () => _toggleFollow(moment),
              followingBusy: _following.contains(moment.author.id),
              onComments: () => _openComments(moment),
            ),
            const SizedBox(height: 12),
          ],
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: CircularProgressIndicator(),
              ),
            ),
          if (_hasMore && !_loading && _moments.isNotEmpty && error == null)
            Center(
              child: TextButton(
                onPressed: loadMore,
                child: Text(text.t('查看更多动态')),
              ),
            ),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) =>
      ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: const Color(0xFFF8E7F7),
        labelStyle: TextStyle(color: selected ? _brand : _muted, fontSize: 12),
        side: const BorderSide(color: Color(0xFFF2EDF1)),
        showCheckmark: false,
      );

  Widget _filterLabel(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFFF2EDF1)),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
        const Icon(Icons.keyboard_arrow_down_rounded, size: 17, color: _muted),
      ],
    ),
  );
}

class _ActivityCheckInDetailPage extends StatefulWidget {
  const _ActivityCheckInDetailPage({required this.moment, required this.api});
  final HomeMoment moment;
  final SiponApiService api;

  @override
  State<_ActivityCheckInDetailPage> createState() =>
      _ActivityCheckInDetailPageState();
}

class _ActivityCheckInDetailPageState
    extends State<_ActivityCheckInDetailPage> {
  late Future<dynamic> _detail = widget.api.getCheckIn(widget.moment.id);

  @override
  Widget build(BuildContext context) => FutureBuilder<dynamic>(
    future: _detail,
    builder: (context, snapshot) {
      if (snapshot.hasData && snapshot.data is Map) {
        return ReviewDetailPage(
          entry: (snapshot.data as Map).cast<String, dynamic>(),
          venue: widget.moment.venue,
          author: widget.moment.author,
          apiService: widget.api,
        );
      }
      return Scaffold(
        appBar: AppBar(
          title: Text(SiponLanguageScope.textOf(context).t('动态详情')),
        ),
        body: Center(
          child: snapshot.hasError
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(SiponLanguageScope.textOf(context).t('动态不可用或已删除')),
                    TextButton(
                      onPressed: () => setState(() {
                        _detail = widget.api.getCheckIn(widget.moment.id);
                      }),
                      child: Text(SiponLanguageScope.textOf(context).t('重试')),
                    ),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      );
    },
  );
}

class _MomentCard extends StatelessWidget {
  const _MomentCard({
    super.key,
    required this.moment,
    required this.subtypeName,
    required this.onOpen,
    required this.onOpenVenue,
    required this.onOpenAuthor,
    required this.onLike,
    required this.onFollow,
    required this.followingBusy,
    required this.onComments,
  });

  final HomeMoment moment;
  final String? subtypeName;
  final VoidCallback onOpen;
  final VoidCallback onOpenVenue;
  final VoidCallback? onOpenAuthor;
  final VoidCallback onLike;
  final VoidCallback? onFollow;
  final bool followingBusy;
  final VoidCallback onComments;

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    final date = moment.createdAt;
    final dateLabel = date == null
        ? ''
        : '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
    final location = [
      moment.city,
      moment.address,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    final category = subtypeName ?? moment.barCategory ?? moment.barSubtype;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFF2EDF1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InkWell(
                    onTap: onOpenAuthor,
                    customBorder: const CircleBorder(),
                    child: ClipOval(
                      child: SizedBox(
                        width: 30,
                        height: 30,
                        child: moment.author.avatarUrl == null
                            ? const ColoredBox(
                                color: Color(0xFFF8E7F7),
                                child: Icon(Icons.person_rounded, size: 18),
                              )
                            : SiponNetworkImage(
                                url: moment.author.avatarUrl!,
                                auth: true,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      onTap: onOpenAuthor,
                      child: Text(
                        moment.author.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    dateLabel,
                    style: const TextStyle(
                      color: Color(0xFF9B939B),
                      fontSize: 11,
                    ),
                  ),
                  if (onFollow != null) ...[
                    const SizedBox(width: 5),
                    TextButton(
                      onPressed: followingBusy ? null : onFollow,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 30),
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                      ),
                      child: Text(
                        text.t(
                          moment.author.isFollowing == true ? '已关注' : '关注',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (moment.author.checkInCount != null) ...[
                const SizedBox(height: 3),
                Text(
                  '${moment.author.checkInCount} ${text.t('条公开评价')}',
                  style: const TextStyle(
                    color: Color(0xFF9B939B),
                    fontSize: 11,
                  ),
                ),
              ],
              if (moment.content.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  moment.content,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF514A52),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
              ],
              const SizedBox(height: 11),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 104,
                      height: 104,
                      child: moment.photos.isEmpty
                          ? const ColoredBox(
                              color: Color(0xFFF3EEF1),
                              child: Icon(
                                Icons.local_bar_outlined,
                                color: Color(0xFFB6ABB2),
                                size: 32,
                              ),
                            )
                          : PageView.builder(
                              key: ValueKey('moment-photos-${moment.id}'),
                              itemCount: moment.photos.length,
                              itemBuilder: (_, index) => SiponNetworkImage(
                                url: moment.photos[index],
                                fallbackWidget: const ColoredBox(
                                  color: Color(0xFFF3EEF1),
                                  child: Icon(Icons.image_outlined),
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: onOpenVenue,
                          child: Text(
                            moment.venue.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF252229),
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (location.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            location,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF9B939B),
                              fontSize: 11,
                            ),
                          ),
                        ],
                        if (category != null || moment.priceRange != null) ...[
                          const SizedBox(height: 5),
                          Text(
                            [
                              if (category != null) text.t(category),
                              if (moment.priceRange != null) moment.priceRange!,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF9A3D78),
                              fontSize: 11,
                            ),
                          ),
                        ],
                        if (moment.rating != null) ...[
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              const Icon(
                                Icons.star_rounded,
                                color: Color(0xFFFFAC46),
                                size: 15,
                              ),
                              Text(
                                '${moment.rating}/5',
                                style: const TextStyle(
                                  color: Color(0xFF9A3D78),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: onLike,
                    icon: Icon(
                      moment.myReaction == 'like'
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 18,
                    ),
                    label: Text('${moment.likeCount}'),
                  ),
                  TextButton.icon(
                    onPressed: onComments,
                    icon: const Icon(Icons.mode_comment_outlined, size: 18),
                    label: Text('${moment.commentCount}'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
