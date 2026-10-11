import { subjectSegmentation } from '@kit.CoreVisionKit';
import { image } from '@kit.ImageKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

export interface StickerOutput {
  photoPath: string;
  stickerPath: string;
  status: string;
}

// Release failures must not replace a completed sticker or prevent other cleanup.
async function cleanup(action: () => Promise<void>): Promise<void> {
  try { await action(); } catch (_) { /* Best effort resource cleanup. */ }
}

export async function orientPhoto(pixelMap: image.PixelMap, orientation: string): Promise<void> {
  switch (orientation.toLowerCase()) {
    case '2': case 'top-right': await pixelMap.flip(true, false); break;
    case '3': case 'bottom-right': await pixelMap.rotate(180); break;
    case '4': case 'bottom-left': await pixelMap.flip(false, true); break;
    case '5': case 'left-top': await pixelMap.flip(true, false); await pixelMap.rotate(270); break;
    case '6': case 'right-top': await pixelMap.rotate(90); break;
    case '7': case 'right-bottom': await pixelMap.flip(true, false); await pixelMap.rotate(90); break;
    case '8': case 'left-bottom': await pixelMap.rotate(270); break;
  }
}

export class StickerProcessor {
  private queue: Promise<void> = Promise.resolve();
  private filesDir: string;

  constructor(filesDir: string) { this.filesDir = filesDir; }

  // The system segmentation service is shared. Do not release it during another request.
  generate(sourcePath: string): Promise<StickerOutput> {
    const job = this.queue.then(() => this.process(sourcePath));
    this.queue = job.then(() => {}, () => {});
    return job;
  }

  private async process(sourcePath: string): Promise<StickerOutput> {
    const directory = `${this.filesDir}/drink_stickers`;
    if (!await fileIo.access(directory)) await fileIo.mkdir(directory);
    const identifier = util.generateRandomUUID(true);
    const extensionMatch = sourcePath.match(/\.([a-zA-Z0-9]{1,8})$/);
    const extension = extensionMatch === null ? 'jpg' : extensionMatch[1].toLowerCase();
    const photoPath = `${directory}/${identifier}_original.${extension}`;
    // Copy before processing so a failed/no-subject result still persists after cache eviction.
    await fileIo.copyFile(sourcePath, photoPath);
    const output: StickerOutput = { photoPath, stickerPath: '', status: 'processing_failed' };
    if (!canIUse('SystemCapability.AI.Vision.SubjectSegmentation')) {
      output.status = 'unsupported';
      return output;
    }

    let sourceFile: fileIo.File | undefined;
    let outputFile: fileIo.File | undefined;
    let imageSource: image.ImageSource | undefined;
    let input: image.PixelMap | undefined;
    let foreground: image.PixelMap | undefined;
    let packer: image.ImagePacker | undefined;
    let attemptedInit = false;
    const stickerPath = `${directory}/${identifier}_sticker.png`;
    try {
      attemptedInit = true;
      if (!await subjectSegmentation.init()) return output;
      sourceFile = await fileIo.open(photoPath, fileIo.OpenMode.READ_ONLY);
      imageSource = image.createImageSource(sourceFile.fd);
      const info = await imageSource.getImageInfo();
      const scale = Math.min(1, 1600 / Math.max(info.size.width, info.size.height));
      input = await imageSource.createPixelMap({
        editable: true,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        desiredSize: { width: Math.max(1, Math.round(info.size.width * scale)),
          height: Math.max(1, Math.round(info.size.height * scale)) }
      });
      let orientation = 'Top-left';
      try { orientation = await imageSource.getImageProperty(image.PropertyKey.ORIENTATION); }
      catch (_) { /* PNG and some gallery images have no EXIF orientation. */ }
      await orientPhoto(input, orientation);
      const segmentation = await subjectSegmentation.doSegmentation({ pixelMap: input }, {
        enableSubjectDetails: false, enableSubjectForegroundImage: true
      });
      foreground = segmentation.fullSubject?.foregroundImage;
      if (segmentation.subjectCount <= 0 || foreground === undefined) {
        output.status = 'no_subject';
        return output;
      }
      // Some devices return a full-size foreground; others return the subject extent already.
      const bounds = segmentation.fullSubject.subjectRectangle;
      const foregroundInfo = await foreground.getImageInfo();
      const inputInfo = await input.getImageInfo();
      const left = Math.max(0, Math.floor(bounds.left));
      const top = Math.max(0, Math.floor(bounds.top));
      const width = Math.min(foregroundInfo.size.width - left, Math.ceil(bounds.left + bounds.width) - left);
      const height = Math.min(foregroundInfo.size.height - top, Math.ceil(bounds.top + bounds.height) - top);
      if (foreground.isEditable && foregroundInfo.size.width === inputInfo.size.width &&
        foregroundInfo.size.height === inputInfo.size.height && width > 0 && height > 0) {
        await foreground.crop({ x: left, y: top, size: { width, height } });
      }
      packer = image.createImagePacker();
      outputFile = await fileIo.open(stickerPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
      // PNG preserves the segmentation alpha channel. JPEG would create a black background.
      await packer.packToFile(foreground, outputFile.fd, { format: 'image/png', quality: 100 });
      output.stickerPath = stickerPath;
      output.status = 'processed';
    } catch (error) {
      const failure = error as BusinessError;
      hilog.warn(0x0000, 'SiponSticker', 'Native cutout failed: %{public}d %{public}s',
        failure.code ?? 0, failure.message);
    } finally {
      const savedOutputFile = outputFile;
      const savedSourceFile = sourceFile;
      const savedPacker = packer;
      const savedForeground = foreground;
      const savedInput = input;
      const savedImageSource = imageSource;
      if (savedOutputFile !== undefined) await cleanup(() => fileIo.close(savedOutputFile));
      if (savedPacker !== undefined) await cleanup(() => savedPacker.release());
      if (savedForeground !== undefined && savedForeground !== savedInput) await cleanup(() => savedForeground.release());
      if (savedInput !== undefined) await cleanup(() => savedInput.release());
      if (savedImageSource !== undefined) await cleanup(() => savedImageSource.release());
      if (savedSourceFile !== undefined) await cleanup(() => fileIo.close(savedSourceFile));
      if (attemptedInit) await cleanup(() => subjectSegmentation.release());
      if (output.stickerPath.length === 0) await cleanup(async () => {
        if (await fileIo.access(stickerPath)) await fileIo.unlink(stickerPath);
      });
    }
    return output;
  }
}
