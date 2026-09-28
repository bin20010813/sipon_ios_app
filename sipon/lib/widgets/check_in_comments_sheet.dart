import 'package:flutter/material.dart';

import '../pages/language_transform.dart';
import '../services/sipon_api_client.dart';
import '../services/sipon_api_service.dart';
import 'sipon_network_image.dart';

/// Public, approved comments for a check-in. Newly submitted comments stay in
/// moderation and are deliberately not inserted into this list.
class CheckInCommentsSheet extends StatefulWidget {
  const CheckInCommentsSheet({
    super.key,
    required this.checkInId,
    required this.api,
    required this.viewerId,
    required this.ensureLogin,
  });

  final int checkInId;
  final SiponApiService api;
  final int? viewerId;
  final Future<bool> Function({bool force}) ensureLogin;

  @override
  State<CheckInCommentsSheet> createState() => _CheckInCommentsSheetState();
}

class _CheckInCommentsSheetState extends State<CheckInCommentsSheet> {
  static const _pageSize = 20;
  final _controller = TextEditingController();
  final List<_Comment> _comments = [];
  bool _loading = false;
  bool _sending = false;
  bool _hasMore = true;
  int _offset = 0;
  Object? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadMore);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await widget.api.getCheckInComments(
        widget.checkInId,
        page: SiponPage(limit: _pageSize, offset: _offset),
      );
      if (!mounted) return;
      if (raw is! Map || raw['items'] is! List) {
        throw const FormatException('Invalid comments response');
      }
      final page = (raw['items'] as List)
          .whereType<Map>()
          .map(_Comment.fromJson)
          .toList();
      setState(() {
        final seen = _comments.map((item) => item.id).toSet();
        _comments.addAll(page.where((item) => seen.add(item.id)));
        _offset = (raw['offset'] as num?)?.toInt() ?? _offset;
        _offset += (raw['limit'] as num?)?.toInt() ?? _pageSize;
        _hasMore = raw['hasMore'] == true;
      });
    } on Exception catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    final content = _controller.text.trim();
    if (content.isEmpty || content.length > 1000 || _sending) return;
    if (!await widget.ensureLogin() || !mounted) return;
    setState(() => _sending = true);
    try {
      await widget.api.createCheckInComment(widget.checkInId, content);
      if (!mounted) return;
      _controller.clear();
      FocusScope.of(context).unfocus();
      _notice('评论已提交，审核通过后展示');
    } on Exception catch (error) {
      if (!mounted) return;
      _notice(_errorMessage(error));
      if (error is SiponApiException && error.statusCode == 401) {
        await widget.ensureLogin(force: true);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(_Comment comment) async {
    try {
      await widget.api.deleteCheckInComment(widget.checkInId, comment.id);
      if (!mounted) return;
      setState(() => _comments.removeWhere((item) => item.id == comment.id));
      _notice('评论已删除');
    } on Exception catch (error) {
      if (mounted) _notice(_errorMessage(error));
    }
  }

  Future<void> _report(_Comment comment) async {
    if (!await widget.ensureLogin() || !mounted) return;
    final reason = await showModalBottomSheet<(String, String)>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in const [
              ('spam', '垃圾广告'),
              ('abuse', '辱骂攻击'),
              ('false_info', '虚假信息'),
              ('porn', '色情低俗'),
              ('other', '其他'),
            ])
              ListTile(
                title: Text(SiponLanguageScope.textOf(context).t(item.$2)),
                onTap: () => Navigator.of(context).pop(item),
              ),
          ],
        ),
      ),
    );
    if (reason == null || !mounted) return;
    try {
      await widget.api.createReport({
        'contentType': 'check_in_comment',
        'contentId': comment.id,
        'reason': reason.$1,
        'details': reason.$2,
      });
      if (mounted) _notice('举报已提交，感谢反馈');
    } on Exception catch (error) {
      if (mounted) _notice(_errorMessage(error));
    }
  }

  String _errorMessage(Object error) =>
      error is SiponApiException && error.message?.trim().isNotEmpty == true
      ? error.message!
      : '操作失败，请重试';

  void _notice(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(SiponLanguageScope.textOf(context).t(message))),
  );

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: FractionallySizedBox(
        heightFactor: 0.78,
        child: Column(
          children: [
            Text(text.t('评论'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Expanded(
              child: _comments.isEmpty && _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      children: [
                        if (_comments.isEmpty && _error == null)
                          Padding(
                            padding: const EdgeInsets.all(28),
                            child: Center(child: Text(text.t('暂无评论'))),
                          ),
                        for (final comment in _comments)
                          ListTile(
                            leading: CircleAvatar(
                              child: comment.avatarUrl == null
                                  ? const Icon(Icons.person_outline_rounded)
                                  : ClipOval(
                                      child: SiponNetworkImage(
                                        url: comment.avatarUrl!,
                                        auth: true,
                                        width: 40,
                                        height: 40,
                                      ),
                                    ),
                            ),
                            title: Text(comment.authorName),
                            subtitle: Text(comment.content),
                            trailing: PopupMenuButton<String>(
                              tooltip: text.t('评论操作'),
                              onSelected: (action) => action == 'delete'
                                  ? _delete(comment)
                                  : _report(comment),
                              itemBuilder: (_) => [
                                if (comment.authorId == widget.viewerId)
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text(text.t('删除')),
                                  )
                                else
                                  PopupMenuItem(
                                    value: 'report',
                                    child: Text(text.t('举报')),
                                  ),
                              ],
                            ),
                          ),
                        if (_error != null)
                          Center(
                            child: TextButton(
                              onPressed: _loadMore,
                              child: Text(text.t('加载失败，点击重试')),
                            ),
                          ),
                        if (_hasMore && !_loading && _error == null)
                          Center(
                            child: TextButton(
                              onPressed: _loadMore,
                              child: Text(text.t('查看更多评论')),
                            ),
                          ),
                        if (_loading && _comments.isNotEmpty)
                          const Center(child: CircularProgressIndicator()),
                      ],
                    ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        maxLength: 1000,
                        maxLines: 2,
                        minLines: 1,
                        decoration: InputDecoration(
                          hintText: text.t('写下评论'),
                          counterText: '',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: text.t('发送评论'),
                      onPressed: _sending ? null : _submit,
                      icon: const Icon(Icons.send_rounded),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Comment {
  const _Comment({
    required this.id,
    required this.content,
    required this.authorId,
    required this.authorName,
    required this.avatarUrl,
  });

  final int id;
  final String content;
  final int? authorId;
  final String authorName;
  final String? avatarUrl;

  factory _Comment.fromJson(Map raw) {
    final author = raw['author'] is Map ? raw['author'] as Map : const {};
    final id = raw['id'];
    final userId = author['userId'];
    return _Comment(
      id: id is num ? id.toInt() : int.tryParse('$id') ?? 0,
      content: raw['content']?.toString() ?? '',
      authorId: userId is num ? userId.toInt() : int.tryParse('$userId'),
      authorName: author['displayName']?.toString() ?? 'Sipon 用户',
      avatarUrl: author['avatarUrl']?.toString(),
    );
  }
}
