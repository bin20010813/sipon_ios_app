part of '../pages/profile_page.dart';

class _MembershipSheet extends StatefulWidget {
  const _MembershipSheet({this.userLevel});

  final int? userLevel;

  @override
  State<_MembershipSheet> createState() => _MembershipSheetState();
}

class _MembershipSheetState extends State<_MembershipSheet> {
  static const _keyLabels = {
    'status': '状态',
    'balance': '余额',
    'points': '积分',
    'integral': '积分',
    'growthValue': '成长值',
    'expireAt': '有效期至',
    'expiredAt': '有效期至',
    'validTo': '有效期至',
    'cardNo': '卡号',
  };

  final SiponApiService _api = SiponApiService();
  Map<String, dynamic>? _membership;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 拉取会员信息；错误统一展示异常文案。
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.getMembership();
      if (!mounted) return;
      setState(() {
        _membership = data is Map ? data.cast<String, dynamic>() : const {};
        _loading = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final themeColors = context.siponColors;
    // 固定弹窗高度：让加载/空态/数据态高度一致，避免接口返回时 bottom sheet
    // 因内容高度变化重新调整尺寸，弹出时出现“闪一下”。
    final sheetHeight = math.min(
      480.0,
      MediaQuery.of(context).size.height * 0.7,
    );
    return Container(
      height: sheetHeight,
      decoration: BoxDecoration(
        color: themeColors.elevatedSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            children: [
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          'Sipon 会员',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: themeColors.brandSurface,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '限时',
                            style: TextStyle(
                              color: scheme.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              _buildSummary(),
              Flexible(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final scheme = Theme.of(context).colorScheme;
    // 等级优先取用户资料；会员接口中的等级用于资料尚未加载时兜底。
    final membership = _membership ?? const <String, dynamic>{};
    final level =
        widget.userLevel ??
        int.tryParse(
          '${membership['level'] ?? membership['userLevel'] ?? membership['levelName'] ?? ''}',
        );
    const labels = ['用户等级', '喝酒路线规划', '鸡尾酒查看'];
    final values = [level == null ? '—' : _romanNumeral(level), '特权开放', '特权开放'];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < labels.length; index++) ...[
          if (index > 0) Divider(height: 1, color: scheme.outlineVariant),
          _membershipRow(labels[index], values[index]),
        ],
      ],
    );
  }

  Widget _membershipRow(String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: scheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final scheme = Theme.of(context).colorScheme;
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: scheme.primary,
          ),
        ),
      );
    }

    final error = _error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              error,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('重试'),
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.primary,
                side: BorderSide(color: scheme.primary),
              ),
            ),
          ],
        ),
      );
    }

    final membership = _membership ?? const <String, dynamic>{};
    // 其他基础类型字段继续展示，避免丢失余额、积分等会员信息。
    final entries = [
      for (final entry in membership.entries)
        if (entry.value != null &&
            entry.value is! Map &&
            entry.value is! List &&
            !{'level', 'userLevel', 'levelName'}.contains(entry.key))
          entry,
    ];
    if (entries.isEmpty) return const SizedBox.shrink();

    return ListView.separated(
      shrinkWrap: true,
      itemCount: entries.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: scheme.outlineVariant),
      itemBuilder: (_, index) {
        final entry = entries[index];
        return _membershipRow(
          _keyLabels[entry.key] ?? entry.key,
          '${entry.value}',
        );
      },
    );
  }
}

/// 个人中心列表的单页数据：条目 + 是否还有下一页。
