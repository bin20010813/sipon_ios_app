import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:sipon/shared/services/sipon_city_controller.dart';
import 'package:sipon/shared/services/home_moments_repository.dart';
import 'package:sipon/shared/services/mock_home_moments_repository.dart';
import 'package:sipon/shared/widgets/bottom_clamping_bouncing_scroll_physics.dart';
import 'package:sipon/shared/widgets/home_moments_section.dart';
import 'package:sipon/shared/widgets/sipon_city_picker.dart';

/// 底栏「酒友动态」tab：公开打卡信息流（筛选、点赞、评论都在 section 内）。
class MomentsPage extends StatefulWidget {
  const MomentsPage({
    super.key,
    this.bottomOverlayInset = 0,
    this.onCheckInPressed,
    this.repository,
  });

  final double bottomOverlayInset;
  final HomeMomentsRepository? repository;
  final Future<void> Function()? onCheckInPressed;

  @override
  State<MomentsPage> createState() => MomentsPageState();
}

class MomentsPageState extends State<MomentsPage> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey<HomeMomentsSectionState> _momentsKey =
      GlobalKey<HomeMomentsSectionState>();
  late final HomeMomentsRepository? _repository =
      widget.repository ??
      (kDebugMode && const bool.fromEnvironment('SIPON_MOCK_MOMENTS')
          ? MockHomeMomentsRepository()
          : null);
  SiponCityController? _cityController;
  String _city = SiponCityController.defaultCity;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScrolled);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cityController = SiponCityScope.controllerOf(context);
    if (_cityController != cityController) {
      _cityController?.removeListener(_onCityChanged);
      _cityController = cityController..addListener(_onCityChanged);
    }
    _onCityChanged();
  }

  @override
  void dispose() {
    _cityController?.removeListener(_onCityChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onCityChanged() {
    final city = _cityController?.city;
    if (city == null || city == _city) return;
    setState(() => _city = city);
  }

  void _onScrolled() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 500) {
      _momentsKey.currentState?.loadMore();
    }
  }

  Future<void> refresh() async {
    await _momentsKey.currentState?.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        // 底部不进安全区，底部留白由 bottomOverlayInset 预留（与首页一致）。
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: RefreshIndicator(
              onRefresh: refresh,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const BottomClampingBouncingScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      16,
                      8,
                      0,
                      24 + widget.bottomOverlayInset,
                    ),
                    sliver: HomeMomentsSection(
                      key: _momentsKey,
                      city: _city,
                      repository: _repository,
                      asSliver: true,
                      onCheckInPressed: widget.onCheckInPressed,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
