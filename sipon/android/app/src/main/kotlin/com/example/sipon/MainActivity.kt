package com.example.sipon

import android.graphics.Bitmap
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.segmentation.subject.SubjectSegmentation
import com.google.mlkit.vision.segmentation.subject.SubjectSegmenterOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.UUID

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "sipon/sticker_cutout"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != "generateSticker") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val sourcePath = call.argument<String>("sourcePath")
            if (sourcePath.isNullOrBlank()) {
                result.error("invalid_arguments", "sourcePath is required.", null)
                return@setMethodCallHandler
            }
            generateSticker(sourcePath, result)
        }
    }

    private fun generateSticker(sourcePath: String, channelResult: MethodChannel.Result) {
        val source = File(sourcePath)
        if (!source.exists()) {
            channelResult.error(
                "source_missing",
                "Selected photo no longer exists.",
                null,
            )
            return
        }

        val outputDirectory = File(filesDir, "drink_stickers")
        if (!outputDirectory.exists() && !outputDirectory.mkdirs()) {
            channelResult.error(
                "storage_failed",
                "Unable to create sticker directory.",
                null,
            )
            return
        }

        val identifier = UUID.randomUUID().toString().lowercase()
        val extension = source.extension.ifBlank { "jpg" }
        val savedPhoto = File(outputDirectory, "${identifier}_original.${extension}")
        try {
            source.copyTo(savedPhoto, overwrite = false)
        } catch (error: Exception) {
            channelResult.error("storage_failed", error.localizedMessage, null)
            return
        }

        val options = SubjectSegmenterOptions.Builder()
            .enableForegroundBitmap()
            .build()
        val segmenter = SubjectSegmentation.getClient(options)
        val inputImage = try {
            InputImage.fromFilePath(this, Uri.fromFile(savedPhoto))
        } catch (error: Exception) {
            segmenter.close()
            channelResult.success(
                mapOf(
                    "photoPath" to savedPhoto.absolutePath,
                    "stickerPath" to null,
                    "status" to "processing_failed",
                ),
            )
            return
        }

        segmenter.process(inputImage)
            .addOnSuccessListener { segmentation ->
                val foreground = segmentation.foregroundBitmap
                if (foreground == null) {
                    channelResult.success(
                        mapOf(
                            "photoPath" to savedPhoto.absolutePath,
                            "stickerPath" to null,
                            "status" to "no_subject",
                        ),
                    )
                    segmenter.close()
                    return@addOnSuccessListener
                }

                val stickerFile = File(outputDirectory, "${identifier}_sticker.png")
                try {
                    FileOutputStream(stickerFile).use { stream ->
                        if (!foreground.compress(Bitmap.CompressFormat.PNG, 100, stream)) {
                            throw IllegalStateException("Unable to encode sticker PNG.")
                        }
                    }
                    channelResult.success(
                        mapOf(
                            "photoPath" to savedPhoto.absolutePath,
                            "stickerPath" to stickerFile.absolutePath,
                            "status" to "processed",
                        ),
                    )
                } catch (error: Exception) {
                    channelResult.success(
                        mapOf(
                            "photoPath" to savedPhoto.absolutePath,
                            "stickerPath" to null,
                            "status" to "processing_failed",
                        ),
                    )
                } finally {
                    segmenter.close()
                }
            }
            .addOnFailureListener {
                segmenter.close()
                channelResult.success(
                    mapOf(
                        "photoPath" to savedPhoto.absolutePath,
                        "stickerPath" to null,
                        "status" to "processing_failed",
                    ),
                )
            }
    }
}
