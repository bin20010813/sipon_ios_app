import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sipon/features/drinks/records/data/sticker_cutout_service.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('sipon/sticker_cutout');
  late Directory directory;
  late File source;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('sticker_cutout_test_');
    source = File('${directory.path}/photo.jpg')..writeAsBytesSync([1]);
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    directory.deleteSync(recursive: true);
  });

  test(
    'passes the source path and returns the native transparent sticker',
    () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        expect(call.method, 'generateSticker');
        expect(call.arguments, {'sourcePath': source.path});
        return {
          'photoPath': '${directory.path}/saved.jpg',
          'stickerPath': '${directory.path}/sticker.png',
          'status': 'processed',
        };
      });
      final result = await StickerCutoutService.instance.generate(source.path);
      expect(result.hasCutout, isTrue);
      expect(result.status, 'processed');
      expect(result.photoPath, '${directory.path}/saved.jpg');
      expect(result.stickerPath, '${directory.path}/sticker.png');
    },
  );

  for (final status in ['no_subject', 'processing_failed', 'unsupported']) {
    test('$status preserves the saved original without a sticker', () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        _,
      ) async {
        return {
          'photoPath': '${directory.path}/saved.jpg',
          'stickerPath': null,
          'status': status,
        };
      });
      final result = await StickerCutoutService.instance.generate(source.path);
      expect(result.status, status);
      expect(result.photoPath, '${directory.path}/saved.jpg');
      expect(result.stickerPath, isNull);
      expect(result.hasCutout, isFalse);
    });
  }

  test('missing source is rejected before invoking native code', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async {
      fail('Missing source must not reach the native channel');
    });
    await expectLater(
      StickerCutoutService.instance.generate('${directory.path}/missing.jpg'),
      throwsA(
        isA<StickerCutoutException>().having(
          (error) => error.code,
          'code',
          'source_missing',
        ),
      ),
    );
  });

  test('native errors retain their error code', () async {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'storage_failed', message: 'Disk full');
    });
    await expectLater(
      StickerCutoutService.instance.generate(source.path),
      throwsA(
        isA<StickerCutoutException>().having(
          (error) => error.code,
          'code',
          'storage_failed',
        ),
      ),
    );
  });
}
