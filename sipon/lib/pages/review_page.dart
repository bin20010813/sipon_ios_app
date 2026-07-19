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
  final List<String> _feedbackItems = <String>[];
  int _rating = 0;

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
      _feedbackItems.insert(0, feedback);
      _feedbackController.clear();
    });
    FocusScope.of(context).unfocus();
    _showMessage(text.feedbackSent);
  }

  void _submitRating(SiponAppText text) {
    if (_rating == 0) {
      _showMessage(text.ratingRequired);
      return;
    }

    _showMessage(text.ratingSent);
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
                        _ReviewTopBar(title: text.reviewTitle, back: text.back),
                        const SizedBox(height: 20),
                        _RatingSection(
                          text: text,
                          rating: _rating,
                          onRatingChanged: (rating) {
                            setState(() => _rating = rating);
                          },
                          onSubmit: () => _submitRating(text),
                        ),
                        const SizedBox(height: 16),
                        _FeedbackSection(
                          text: text,
                          controller: _feedbackController,
                          feedbackItems: _feedbackItems,
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

class _RatingSection extends StatelessWidget {
  const _RatingSection({
    required this.text,
    required this.rating,
    required this.onRatingChanged,
    required this.onSubmit,
  });

  final SiponAppText text;
  final int rating;
  final ValueChanged<int> onRatingChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.star_rate_rounded,
            title: text.rateTitle,
            trailing: Text(
              text.ratingValue(rating),
              style: const TextStyle(
                color: _ReviewPageState._brand,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            text.ratingPrompt,
            style: const TextStyle(
              color: _ReviewPageState._muted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var value = 1; value <= 5; value++)
                _StarButton(
                  value: value,
                  selected: value <= rating,
                  onPressed: () => onRatingChanged(value),
                ),
            ],
          ),
          const SizedBox(height: 14),
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
              icon: const Icon(Icons.send_rounded, size: 18),
              label: Text(
                text.submitRating,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StarButton extends StatelessWidget {
  const _StarButton({
    required this.value,
    required this.selected,
    required this.onPressed,
  });

  final int value;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: IconButton(
        onPressed: onPressed,
        style: IconButton.styleFrom(
          fixedSize: const Size.fromHeight(44),
          padding: EdgeInsets.zero,
          foregroundColor: selected
              ? const Color(0xFFFFB340)
              : const Color(0xFFD9D3D8),
        ),
        icon: Icon(
          selected ? Icons.star_rounded : Icons.star_border_rounded,
          size: 34,
        ),
      ),
    );
  }
}

class _FeedbackSection extends StatelessWidget {
  const _FeedbackSection({
    required this.text,
    required this.controller,
    required this.feedbackItems,
    required this.onSubmit,
  });

  final SiponAppText text;
  final TextEditingController controller;
  final List<String> feedbackItems;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return _SettingsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.forum_rounded,
            title: text.feedbackBoardTitle,
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
                    body: feedbackItems[index],
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
  const _FeedbackItem({required this.title, required this.body});

  final String title;
  final String body;

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
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;

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
        ?trailing,
      ],
    );
  }
}
