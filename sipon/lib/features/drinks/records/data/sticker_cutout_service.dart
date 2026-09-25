import 'dart:io';

import 'package:flutter/services.dart';

class StickerCutoutResult {
  const StickerCutoutResult({
    required this.photoPath,
    required this.stickerPath,
    required this.status,
  });

  final String photoPath;
  final String? stickerPath;
  final String status;

  bool get hasCutout => stickerPath != null && stickerPath!.isNotEmpty;
}

class StickerCutoutService {
  StickerCutoutService._();

  static final StickerCutoutService instance = StickerCutoutService._();
  static const MethodChannel _channel = MethodChannel('sipon/sticker_cutout');

  Future<StickerCutoutResult> generate(String sourcePath) async {
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw const StickerCutoutException(
        code: 'source_missing',
        message: 'Selected photo no longer exists.',
      );
    }

    try {
      final response = await _channel.invokeMapMethod<String, dynamic>(
        'generateSticker',
        {'sourcePath': sourcePath},
      );
      final photoPath = response?['photoPath']?.toString();
      final stickerPath = response?['stickerPath']?.toString();
      if (photoPath == null || photoPath.isEmpty) {
        throw const StickerCutoutException(
          code: 'invalid_result',
          message: 'Sticker processor returned no saved photo.',
        );
      }
      return StickerCutoutResult(
        photoPath: photoPath,
        stickerPath: stickerPath == null || stickerPath.isEmpty
            ? null
            : stickerPath,
        status: response?['status']?.toString() ?? 'processed',
      );
    } on PlatformException catch (error) {
      throw StickerCutoutException(
        code: error.code,
        message: error.message ?? 'Unable to generate sticker.',
      );
    } on MissingPluginException {
      throw const StickerCutoutException(
        code: 'unsupported',
        message: 'Sticker generation is unavailable on this platform.',
      );
    }
  }
}

class StickerCutoutException implements Exception {
  const StickerCutoutException({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => 'StickerCutoutException($code): $message';
}
