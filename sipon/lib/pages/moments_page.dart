import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/mock_home_moments_repository.dart';
import '../widgets/home_moments_section.dart';
import '../widgets/sipon_city_picker.dart';

class MomentsPage extends StatefulWidget {
  const MomentsPage({
    super.key,
    this.bottomOverlayInset = 0,
    this.onCheckInPressed,
  });

  final double bottomOverlayInset;
  final Future<void> Function()? onCheckInPressed;

  @override
  State<MomentsPage> createState() => MomentsPageState();
}

class MomentsPageState extends State<MomentsPage> {
  final _feedKey = GlobalKey<HomeMomentsSectionState>();
  final _scrollController = ScrollController();
  final _repository = kDebugMode ? MockHomeMomentsRepository() : null;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMore);
  }

  void _loadMore() {
    if (_scrollController.position.extentAfter < 500) {
      _feedKey.currentState?.loadMore();
    }
  }

  Future<void> refresh() async => _feedKey.currentState?.refresh();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cityController = SiponCityScope.controllerOf(context);
    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: refresh,
          child: ListenableBuilder(
            listenable: cityController,
            builder: (context, _) => SingleChildScrollView(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                0,
                24 + widget.bottomOverlayInset,
              ),
              child: HomeMomentsSection(
                key: _feedKey,
                city: cityController.city,
                repository: _repository,
                onCheckInPressed: widget.onCheckInPressed,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
