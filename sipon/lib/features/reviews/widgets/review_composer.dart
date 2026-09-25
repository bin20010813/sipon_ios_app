import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/theme/sipon_theme_colors.dart';

class ReviewDraft {
  const ReviewDraft({
    required this.rating,
    required this.content,
    required this.images,
  });

  final int rating;
  final String content;
  final List<XFile> images;
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
  bool _submitting = false;

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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight - 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.venueName,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              widget.venueAddress,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 28),
            const Text('本次体验', style: TextStyle(fontWeight: FontWeight.w700)),
            Row(
              children: [
                for (var index = 1; index <= 5; index++)
                  IconButton(
                    onPressed: () => setState(() => _rating = index),
                    icon: Icon(
                      index <= _rating
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      // 评分星标使用评分语义色，浅深色下都保持可辨识。
                      color: context.siponColors.starRating,
                      size: 30,
                    ),
                    tooltip: '$index 星',
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              minLines: 5,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: '写下这次的酒、音乐或遇见的人...',
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(8)),
                  borderSide: BorderSide(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
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
                          color: Theme.of(context).colorScheme.surface,
                          border: Border.all(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.add_photo_alternate_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submitting ? null : _submit,
                icon: _submitting
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(_submitting ? '提交中...' : widget.submitLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
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
                      // 图片解码中的占位，复用骨架色。
                      color: context.siponColors.skeleton,
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
              color: Theme.of(context).colorScheme.primary,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 24, height: 24),
            ),
          ),
        ],
      ),
    );
  }
}
