import 'package:flutter/material.dart';

import 'language_transform.dart';

class ReviewPage extends StatefulWidget {
  const ReviewPage({super.key});

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  static const Color _brand = Color(0xFF9A3D78);
  static const Color _ink = Color(0xFF292B32);
  static const Color _muted = Color(0xFF8E8790);
  static const Color _line = Color(0xFFF1EBEF);

  final TextEditingController _feedbackController = TextEditingController();
  final List<_FeedbackDraft> _feedbackItems = <_FeedbackDraft>[];
  int _screenshotCount = 0;

  @override
  void dispose() {
    _feedbackController.dispose();
    super.dispose();
  }

  void _submitFeedback(SiponAppText text) {
    final feedback = _feedbackController.text.trim();
    if (feedback.isEmpty) {
      _showMessage(text.feedbackRequired);
      return;
    }

    setState(() {
      _feedbackItems.insert(
        0,
        _FeedbackDraft(message: feedback, screenshotCount: _screenshotCount),
      );
      _feedbackController.clear();
      _screenshotCount = 0;
    });
    FocusScope.of(context).unfocus();
    _showMessage(text.feedbackSent);
  }

  void _addScreenshot(SiponAppText text) {
    if (_screenshotCount >= 3) {
      _showMessage(text.t('最多添加 3 张截图'));
      return;
    }

    setState(() => _screenshotCount += 1);
    _showMessage(text.t('已添加截图占位'));
  }

  void _removeScreenshot(int index) {
    setState(() => _screenshotCount -= 1);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final text = SiponLanguageScope.textOf(context);

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFFFFF2F3), Color(0xFFFFFCFC), Colors.white],
            stops: [0, 0.38, 1],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
                    sliver: SliverList.list(
                      children: [
                        _ReviewTopBar(
                          title: text.featureFeedback,
                          back: text.back,
                        ),
                        const SizedBox(height: 20),
                        _FeedbackSection(
                          text: text,
                          controller: _feedbackController,
                          feedbackItems: _feedbackItems,
                          screenshotCount: _screenshotCount,
                          onAddScreenshot: () => _addScreenshot(text),
                          onRemoveScreenshot: _removeScreenshot,
                          onSubmit: () => _submitFeedback(text),
                        ),
                      ],
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

class _FeedbackDraft {
  const _FeedbackDraft({required this.message, required this.screenshotCount});

  final String message;
  final int screenshotCount;
}

class _ReviewTopBar extends StatelessWidget {
  const _ReviewTopBar({required this.title, required this.back});

  final String title;
  final String back;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Tooltip(
            message: back,
            child: IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: IconButton.styleFrom(
                fixedSize: const Size(40, 40),
                backgroundColor: Colors.white.withValues(alpha: 0.78),
                foregroundColor: _ReviewPageState._ink,
                padding: EdgeInsets.zero,
                shape: const CircleBorder(),
              ),
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _ReviewPageState._ink,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackSection extends StatelessWidget {
  const _FeedbackSection({
    required this.text,
    required this.controller,
    required this.feedbackItems,
    required this.screenshotCount,
    required this.onAddScreenshot,
    required this.onRemoveScreenshot,
    required this.onSubmit,
  });

  final SiponAppText text;
  final TextEditingController controller;
  final List<_FeedbackDraft> feedbackItems;
  final int screenshotCount;
  final VoidCallback onAddScreenshot;
  final ValueChanged<int> onRemoveScreenshot;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.add_comment_outlined,
            title: text.t('留言反馈'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            minLines: 3,
            maxLines: 5,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: text.feedbackHint,
              filled: true,
              fillColor: const Color(0xFFFCF8FA),
              contentPadding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _ReviewPageState._line),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                  color: _ReviewPageState._brand,
                  width: 1.3,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _ScreenshotPicker(
            text: text,
            count: screenshotCount,
            onAdd: onAddScreenshot,
            onRemove: onRemoveScreenshot,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onSubmit,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                backgroundColor: _ReviewPageState._brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.post_add_rounded, size: 18),
              label: Text(
                text.submitFeedback,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (feedbackItems.isEmpty)
            _EmptyFeedback(text: text)
          else
            Column(
              children: [
                for (var index = 0; index < feedbackItems.length; index++) ...[
                  _FeedbackItem(
                    title: text.feedbackNumber(feedbackItems.length - index),
                    body: feedbackItems[index].message,
                    screenshotCount: feedbackItems[index].screenshotCount,
                  ),
                  if (index != feedbackItems.length - 1)
                    const SizedBox(height: 10),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _ScreenshotPicker extends StatelessWidget {
  const _ScreenshotPicker({
    required this.text,
    required this.count,
    required this.onAdd,
    required this.onRemove,
  });

  final SiponAppText text;
  final int count;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text.t('添加截图'),
          style: const TextStyle(
            color: _ReviewPageState._ink,
            fontSize: 14,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (var index = 0; index < count; index++)
              _ScreenshotTile(
                label: text.t('截图 ${index + 1}'),
                onRemove: () => onRemove(index),
              ),
            if (count < 3) _AddScreenshotTile(text: text, onTap: onAdd),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          text.t('最多上传 3 张问题截图，便于我们定位页面和异常。'),
          style: const TextStyle(
            color: _ReviewPageState._muted,
            fontSize: 12,
            height: 1.3,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _ScreenshotTile extends StatelessWidget {
  const _ScreenshotTile({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 88,
      height: 88,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFFFF6FB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _ReviewPageState._line),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.image_outlined,
                    color: _ReviewPageState._brand,
                    size: 24,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ReviewPageState._muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: -6,
            top: -6,
            child: IconButton.filled(
              onPressed: onRemove,
              style: IconButton.styleFrom(
                fixedSize: const Size(24, 24),
                padding: EdgeInsets.zero,
                backgroundColor: _ReviewPageState._ink,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.close_rounded, size: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddScreenshotTile extends StatelessWidget {
  const _AddScreenshotTile({required this.text, required this.onTap});

  final SiponAppText text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            color: const Color(0xFFFCF8FA),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _ReviewPageState._line),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.add_photo_alternate_outlined,
                color: _ReviewPageState._brand,
                size: 26,
              ),
              const SizedBox(height: 6),
              Text(
                text.t('添加'),
                style: const TextStyle(
                  color: _ReviewPageState._brand,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyFeedback extends StatelessWidget {
  const _EmptyFeedback({required this.text});

  final SiponAppText text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFFCF8FA),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _ReviewPageState._line),
      ),
      child: Text(
        text.feedbackEmpty,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: _ReviewPageState._muted,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _FeedbackItem extends StatelessWidget {
  const _FeedbackItem({
    required this.title,
    required this.body,
    required this.screenshotCount,
  });

  final String title;
  final String body;
  final int screenshotCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBFD),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _ReviewPageState._line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _ReviewPageState._brand,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              color: _ReviewPageState._ink,
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          if (screenshotCount > 0) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(
                  Icons.photo_library_outlined,
                  color: _ReviewPageState._brand,
                  size: 16,
                ),
                const SizedBox(width: 5),
                Text(
                  SiponLanguageScope.textOf(
                    context,
                  ).t('已附加 $screenshotCount 张截图'),
                  style: const TextStyle(
                    color: _ReviewPageState._brand,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F9A3D78),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 17),
        child: child,
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: const Color(0xFFFFEDF7),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: _ReviewPageState._brand, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _ReviewPageState._ink,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}
