import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/theme/sipon_theme_colors.dart';

import '../../shared/localization/language_transform.dart';
import '../../features/profile/pages/public_profile_page.dart';
import '../../features/reviews/pages/review_detail_page.dart';
import '../../features/auth/pages/sms_login_page.dart';
import '../services/home_moments_repository.dart';
import '../services/sipon_api_client.dart';
import '../services/sipon_api_config.dart';
import '../services/sipon_api_service.dart';
import '../services/sipon_auth_service.dart';
import '../../features/map/pages/venue_detail_page.dart';
import 'sipon_network_image.dart';
import 'sipon_message.dart';
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
    this.asSliver = false,
  });

  final String city;
  final Future<void> Function()? onCheckInPressed;
  final HomeMomentsRepository? repository;
  final SiponApiService? apiService;
  final bool asSliver;

  @override
  State<HomeMomentsSection> createState() => HomeMomentsSectionState();
}

class HomeMomentsSectionState extends State<HomeMomentsSection> {
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
    showSiponMessage(
      context,
      SiponLanguageScope.textOf(context).t(message),
      type: SiponMessageType.error,
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
    final colors = Theme.of(context).colorScheme;
    final subtypeName = {
      for (final subtype in _subtypes) subtype.code: subtype.name,
    };
    final error = _error;
    final isEmpty = _moments.isEmpty && !_loading && error == null;
    final emptyState = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text.t(_scope == 'following' ? '还没有关注用户的公开动态' : '这里暂时没有内容'),
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
        ),
        if (_scope == 'all') ...[
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              setState(() => _allCities = !_allCities);
              refresh(clear: true);
            },
            child: Text(text.t(_allCities ? '返回当前城市' : '查看全部城市')),
          ),
        ],
      ],
    );
    final header = Padding(
      padding: const EdgeInsets.only(right: 16, top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  text.t('酒友动态'),
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.8,
                  ),
                ),
              ),
              IconButton(
                tooltip: text.t('刷新动态'),
                onPressed: () => refresh(),
                icon: Icon(Icons.refresh_rounded, color: colors.primary),
              ),
              if (widget.onCheckInPressed != null)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _searchController,
            onChanged: _onKeywordChanged,
            maxLength: 100,
            style: TextStyle(fontSize: 14, color: colors.onSurface),
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
              fillColor: colors.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 15),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: colors.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _filterChip(
                text.t('全部动态'),
                _scope == 'all',
                () => _changeScope('all'),
              ),
              const SizedBox(width: 16),
              _filterChip(
                text.t('关注'),
                _scope == 'following',
                () => _changeScope('following'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
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
                          child: _filterLabel(
                            text.t(subtypeName[_subtype] ?? '全部品类'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        PopupMenuButton<String>(
                          tooltip: text.t('排序'),
                          onSelected: (value) {
                            if (_sort == value) return;
                            setState(() => _sort = value);
                            refresh(clear: true);
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(
                              value: 'latest',
                              child: Text(text.t('最新优先')),
                            ),
                            PopupMenuItem(
                              value: 'popular',
                              child: Text(text.t('热门优先')),
                            ),
                          ],
                          child: _filterLabel(
                            text.t(_sort == 'popular' ? '热门优先' : '最新优先'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    if (error is SiponApiException && error.statusCode == 401) {
                      await _ensureLogin(force: true);
                      return;
                    }
                    if (_failedReplace) {
                      await refresh(clear: _moments.isEmpty);
                    } else {
                      await _loadPage(generation: _generation, replace: false);
                    }
                  },
                  child: Text(text.t('重试')),
                ),
              ],
            ),
          ),
        if (isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 25),
            child: Center(child: emptyState),
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
            onFollow: moment.author.id == null || moment.author.id == _viewerId
                ? null
                : () => _toggleFollow(moment),
            followingBusy: _following.contains(moment.author.id),
            onComments: () => _openComments(moment),
          ),
          const SizedBox(height: 14),
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
    );
    if (widget.asSliver) {
      return SliverMainAxisGroup(
        slivers: [
          SliverToBoxAdapter(child: header),
          if (isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Center(child: emptyState),
              ),
            )
          else
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: content,
              ),
            ),
        ],
      );
    }
    return Column(
      children: [
        header,
        Padding(padding: const EdgeInsets.only(right: 16), child: content),
      ],
    );
  }

  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: selected ? colors.onSurface : colors.onSurfaceVariant,
                  fontSize: 16,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 9),
              Container(
                width: 22,
                height: 3,
                decoration: BoxDecoration(
                  color: selected ? colors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterLabel(String label) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 17,
            color: colors.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
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
    final colors = Theme.of(context).colorScheme;
    final date = moment.createdAt;
    final dateLabel = date == null
        ? ''
        : '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
    final location = [
      moment.city,
      moment.address,
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
    final category = subtypeName ?? moment.barCategory ?? moment.barSubtype;
    final metadata = [
      if (dateLabel.isNotEmpty) dateLabel,
      if (moment.author.checkInCount != null)
        '${moment.author.checkInCount} ${text.t('条公开评价')}',
    ].join(' · ');
    final liked = moment.myReaction == 'like';
    return Material(
      color: context.siponColors.elevatedSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.45)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  InkWell(
                    onTap: onOpenAuthor,
                    customBorder: const CircleBorder(),
                    child: CircleAvatar(
                      radius: 20,
                      backgroundColor: context.siponColors.brandSurface,
                      child: ClipOval(
                        child: SizedBox(
                          width: 40,
                          height: 40,
                          child: moment.author.avatarUrl == null
                              ? Icon(
                                  Icons.person_rounded,
                                  color: colors.primary,
                                  size: 23,
                                )
                              : SiponNetworkImage(
                                  url: moment.author.avatarUrl!,
                                  auth: true,
                                  fallbackWidget: Icon(
                                    Icons.person_rounded,
                                    color: colors.primary,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: onOpenAuthor,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            moment.author.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (metadata.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              metadata,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (onFollow != null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: followingBusy ? null : onFollow,
                      style: TextButton.styleFrom(
                        foregroundColor: moment.author.isFollowing == true
                            ? colors.onSurfaceVariant
                            : colors.primary,
                        backgroundColor: moment.author.isFollowing == true
                            ? context.siponColors.subtleSurface
                            : context.siponColors.brandSurface,
                        minimumSize: const Size(60, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: Text(
                        text.t(
                          moment.author.isFollowing == true ? '已关注' : '+ 关注',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (moment.rating != null) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    for (var i = 0; i < moment.rating!.clamp(0, 5); i++)
                      Icon(
                        Icons.star_rounded,
                        color: context.siponColors.starRating,
                        size: 18,
                      ),
                  ],
                ),
              ],
              if (moment.content.isNotEmpty) ...[
                SizedBox(height: moment.rating != null ? 6 : 16),
                Text(
                  moment.content,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),
              ],
              if (moment.photos.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 172,
                  child: ListView.separated(
                    key: ValueKey('moment-photos-${moment.id}'),
                    scrollDirection: Axis.horizontal,
                    itemCount: moment.photos.length,
                    separatorBuilder: (_, index) => const SizedBox(width: 8),
                    itemBuilder: (_, index) => ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SiponNetworkImage(
                        url: moment.photos[index],
                        width: 172,
                        height: 172,
                        fallbackWidget: ColoredBox(
                          color: context.siponColors.subtleSurface,
                          child: Icon(
                            Icons.image_outlined,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Material(
                color: context.siponColors.subtleSurface,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onOpenVenue,
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 56,
                            height: 56,
                            child: moment.venue.imageUrl == null
                                ? Image.asset(
                                    moment.venue.imageAsset,
                                    fit: BoxFit.cover,
                                  )
                                : SiponNetworkImage(
                                    url: moment.venue.imageUrl!,
                                    fallbackAsset: moment.venue.imageAsset,
                                  ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                moment.venue.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.onSurface,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  height: 1.4,
                                ),
                              ),
                              if (category != null ||
                                  moment.priceRange != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  [
                                    if (category != null) text.t(category),
                                    if (moment.priceRange != null)
                                      moment.priceRange!,
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                              if (location.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  location,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: colors.onSurfaceVariant,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Spacer(),
                  TextButton.icon(
                    onPressed: onLike,
                    style: TextButton.styleFrom(
                      foregroundColor: liked
                          ? colors.primary
                          : colors.onSurfaceVariant,
                      minimumSize: const Size(48, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    icon: Icon(
                      liked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 19,
                    ),
                    label: Text(
                      moment.likeCount == 0
                          ? text.t('赞')
                          : '${moment.likeCount}',
                    ),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: onComments,
                    style: TextButton.styleFrom(
                      foregroundColor: colors.onSurfaceVariant,
                      minimumSize: const Size(48, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                    icon: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 18,
                    ),
                    label: Text(
                      moment.commentCount == 0
                          ? text.t('评论')
                          : '${moment.commentCount}',
                    ),
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
