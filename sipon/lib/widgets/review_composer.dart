import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ReviewDraft {
  const ReviewDraft({
    required this.rating,
    required this.aspectRatings,
    required this.content,
    required this.images,
  });

  final int rating;
  final ReviewAspectRatings aspectRatings;
  final String content;
  final List<XFile> images;
}

/// Zero means the visitor did not rate that part of the experience.
class ReviewAspectRatings {
  const ReviewAspectRatings({
    this.drinks = 0,
    this.food = 0,
    this.service = 0,
    this.atmosphere = 0,
  });

  final int drinks;
  final int food;
  final int service;
  final int atmosphere;

  Map<String, Object?> toPayload() => {
    if (drinks > 0) 'drinkRating': drinks,
    if (food > 0) 'foodRating': food,
    if (service > 0) 'serviceRating': service,
    if (atmosphere > 0) 'atmosphereRating': atmosphere,
  };

  String get summary {
    final parts = <String>[
      if (drinks > 0) '酒水 $drinks/5',
      if (food > 0) '食物 $food/5',
      if (service > 0) '服务 $service/5',
      if (atmosphere > 0) '氛围 $atmosphere/5',
    ];
    return parts.join(' · ');
  }

  String prependToContent(String content) {
    final trimmed = content.trim();
    if (summary.isEmpty) return trimmed;
    return trimmed.isEmpty ? summary : '$summary\n\n$trimmed';
  }
}

class ReviewComposer extends StatefulWidget {
  const ReviewComposer({
    super.key,
    required this.venueName,
    required this.venueAddress,
    required this.onSubmit,
    this.submitLabel = '完成评论',
  });

  final String venueName;
  final String venueAddress;
  final Future<void> Function(ReviewDraft draft) onSubmit;
  final String submitLabel;

  @override
  State<ReviewComposer> createState() => _ReviewComposerState();
}

class _ReviewComposerState extends State<ReviewComposer> {
  static const int _maxImages = 9;
  final _controller = TextEditingController();
  final _picker = ImagePicker();
  final _images = <XFile>[];
  int _rating = 0;
  int _drinksRating = 0;
  int _foodRating = 0;
  int _serviceRating = 0;
  int _atmosphereRating = 0;
  bool _submitting = false;

  ReviewAspectRatings get _aspectRatings => ReviewAspectRatings(
    drinks: _drinksRating,
    food: _foodRating,
    service: _serviceRating,
    atmosphere: _atmosphereRating,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickImage() async {
    if (_images.length >= _maxImages) {
      _showMessage('最多添加 $_maxImages 张图片');
      return;
    }
    try {
      final file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;
      setState(() => _images.add(file));
    } on Exception {
      if (mounted) _showMessage('图片选择失败，请重试');
    }
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      _showMessage('请先评分');
      return;
    }
    if (_submitting) return;
    setState(() => _submitting = true);
    FocusScope.of(context).unfocus();
    try {
      await widget.onSubmit(
        ReviewDraft(
          rating: _rating,
          aspectRatings: _aspectRatings,
          content: _controller.text.trim(),
          images: List.unmodifiable(_images),
        ),
      );
    } on Exception catch (error) {
      if (mounted) _showMessage('评论提交失败：$error');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.venueName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF252229),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.venueAddress,
                style: const TextStyle(color: Color(0xFF8F8790)),
              ),
              const SizedBox(height: 28),
              const Text(
                '总体评价',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              Row(
                children: [
                  for (var index = 1; index <= 5; index++)
                    IconButton(
                      onPressed: () => setState(() => _rating = index),
                      icon: Icon(
                        index <= _rating
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: const Color(0xFFE09A35),
                        size: 30,
                      ),
                      tooltip: '$index 星',
                    ),
                ],
              ),
              if (_rating > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 9),
                  child: Text(
                    '$_rating/5',
                    style: const TextStyle(
                      color: Color(0xFF9A3D78),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F3F6),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '细分体验（可选）',
                      style: TextStyle(
                        color: Color(0xFF252229),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _AspectRatingRow(
                      label: '酒水',
                      rating: _drinksRating,
                      onChanged: (value) =>
                          setState(() => _drinksRating = value),
                    ),
                    _AspectRatingRow(
                      label: '食物',
                      rating: _foodRating,
                      onChanged: (value) => setState(() => _foodRating = value),
                    ),
                    _AspectRatingRow(
                      label: '服务',
                      rating: _serviceRating,
                      onChanged: (value) =>
                          setState(() => _serviceRating = value),
                    ),
                    _AspectRatingRow(
                      label: '氛围',
                      rating: _atmosphereRating,
                      onChanged: (value) =>
                          setState(() => _atmosphereRating = value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                minLines: 4,
                maxLines: 7,
                decoration: const InputDecoration(
                  hintText: '分享酒水、食物、服务或氛围的体验…',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(8)),
                    borderSide: BorderSide(color: Color(0xFFF0E9ED)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '添加照片（${_images.length}/$_maxImages）',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 76,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (var index = 0; index < _images.length; index++)
                      _imageTile(index),
                    if (_images.length < _maxImages)
                      InkWell(
                        onTap: _pickImage,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: const Color(0xFFF0E9ED)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.add_photo_alternate_outlined,
                            color: Color(0xFF9A3D78),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFF0E9ED))),
          ),
          child: FilledButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_rounded),
            label: Text(_submitting ? '提交中...' : widget.submitLabel),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF9A3D78),
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _imageTile(int index) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: FutureBuilder<List<int>>(
              future: _images[index].readAsBytes(),
              builder: (context, snapshot) => snapshot.data == null
                  ? Container(
                      width: 76,
                      height: 76,
                      color: const Color(0xFFF0E9ED),
                    )
                  : Image.memory(
                      Uint8List.fromList(snapshot.data!),
                      width: 76,
                      height: 76,
                      fit: BoxFit.cover,
                    ),
            ),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: IconButton(
              onPressed: () => setState(() => _images.removeAt(index)),
              icon: const Icon(Icons.cancel_rounded, size: 20),
              color: const Color(0xFF9A3D78),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 24, height: 24),
            ),
          ),
        ],
      ),
    );
  }
}

class _AspectRatingRow extends StatelessWidget {
  const _AspectRatingRow({
    required this.label,
    required this.rating,
    required this.onChanged,
  });

  final String label;
  final int rating;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 43,
      child: Row(
        children: [
          SizedBox(
            width: 58,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF514A50),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (var index = 1; index <= 5; index++)
            IconButton(
              onPressed: () => onChanged(index == rating ? 0 : index),
              tooltip: '$label $index 星',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 43, height: 43),
              icon: Icon(
                index <= rating
                    ? Icons.star_rounded
                    : Icons.star_outline_rounded,
                color: const Color(0xFFEBA824),
                size: 27,
              ),
            ),
        ],
      ),
    );
  }
}
