package com.example.sipon

import android.graphics.Bitmap
import android.util.Log
import com.example.sipon.map.SiponPetalFactory
import com.example.sipon.map.SiponPetalView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val mapViews = mutableSetOf<SiponPetalView>()
    private val stickerExecutor = Executors.newSingleThreadExecutor()
    private var stickerChannel: MethodChannel? = null
    private val stickerSegmenter by lazy { U2NetStickerSegmenter(applicationContext.assets) }
    companion object {
        private const val CHANNEL = "sipon/sticker_cutout"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "sipon/petal",
            SiponPetalFactory(
                flutterEngine.dartExecutor.binaryMessenger,
                { mapViews.add(it) },
                { mapViews.remove(it) },
            ),
        )
        stickerChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).also { channel -> channel.setMethodCallHandler { call, result ->
            if (call.method != "generateSticker") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val sourcePath = call.argument<String>("sourcePath")
            if (sourcePath.isNullOrBlank()) {
                result.error("invalid_arguments", "sourcePath is required.", null)
                return@setMethodCallHandler
            }
            if (stickerExecutor.isShutdown) {
                result.error("activity_destroyed", "Sticker processing is no longer available.", null)
                return@setMethodCallHandler
            }
            stickerExecutor.execute { generateSticker(sourcePath, result) }
        } }
    }

    override fun onStart() {
        super.onStart()
        mapViews.toList().forEach { it.onActivityStart() }
    }

    override fun onResume() {
        super.onResume()
        mapViews.toList().forEach { it.onActivityResume() }
    }

    override fun onPause() {
        mapViews.toList().forEach { it.onActivityPause() }
        super.onPause()
    }

    override fun onStop() {
        mapViews.toList().forEach { it.onActivityStop() }
        super.onStop()
    }

    override fun onLowMemory() {
        mapViews.toList().forEach { it.onLowMemory() }
        super.onLowMemory()
    }

    override fun onDestroy() {
        mapViews.toList().forEach { it.dispose() }
        stickerChannel?.setMethodCallHandler(null)
        stickerChannel = null
        // Drain accepted work before closing the session; never close it concurrently with inference.
        stickerExecutor.execute {
            try {
                stickerSegmenter.close()
            } catch (error: Exception) {
                Log.w("StickerCutout", "Unable to close ONNX session", error)
            }
        }
        stickerExecutor.shutdown()
        super.onDestroy()
    }

    private fun generateSticker(sourcePath: String, channelResult: MethodChannel.Result) {
        val result = object : MethodChannel.Result {
            override fun success(value: Any?) = runOnUiThread { channelResult.success(value) }
            override fun error(code: String, message: String?, details: Any?) =
                runOnUiThread { channelResult.error(code, message, details) }
            override fun notImplemented() = runOnUiThread { channelResult.notImplemented() }
        }
        val source = File(sourcePath)
        if (!source.isFile) {
            result.error("source_missing", "Selected photo no longer exists.", null)
            return
        }
        val outputDirectory = File(filesDir, "drink_stickers")
        if (!outputDirectory.exists() && !outputDirectory.mkdirs()) {
            result.error("storage_failed", "Unable to create sticker directory.", null)
            return
        }
        val identifier = UUID.randomUUID().toString().lowercase()
        val extension = source.extension.ifBlank { "jpg" }
        val savedPhoto = File(outputDirectory, "${identifier}_original.${extension}")
        try {
            source.copyTo(savedPhoto, overwrite = false)
        } catch (error: Exception) {
            savedPhoto.delete()
            result.error("storage_failed", error.localizedMessage, null)
            return
        }
        fun complete(status: String, sticker: File? = null) {
            result.success(mapOf(
                "photoPath" to savedPhoto.absolutePath,
                "stickerPath" to sticker?.absolutePath,
                "status" to status,
            ))
        }
        var sticker: Bitmap? = null
        val stickerFile = File(outputDirectory, "${identifier}_sticker.png")
        try {
            val foreground = stickerSegmenter.cutout(savedPhoto)
            sticker = foreground
            if (foreground == null) {
                complete("no_subject")
                return
            }
            FileOutputStream(stickerFile).use { stream ->
                check(foreground.compress(Bitmap.CompressFormat.PNG, 100, stream)) {
                    "Unable to encode sticker PNG."
                }
            }
            complete("processed", stickerFile)
        } catch (error: Exception) {
            Log.w("StickerCutout", "Sticker generation failed", error)
            stickerFile.delete()
            complete("processing_failed")
        } finally {
            sticker?.recycle()
        }
    }
}
