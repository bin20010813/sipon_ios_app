package com.example.sipon

import android.content.res.AssetManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import java.io.Closeable
import java.io.File
import java.nio.FloatBuffer
import kotlin.math.roundToInt

/** Access and close only on the sticker executor: a session must never close during run(). */
internal class U2NetStickerSegmenter(private val assets: AssetManager) : Closeable {
    private var session: OrtSession? = null

    private fun session(): OrtSession {
        session?.let { return it }
        return OrtSession.SessionOptions().use { options ->
            options.setIntraOpNumThreads(minOf(2, Runtime.getRuntime().availableProcessors()))
            options.setInterOpNumThreads(1)
            options.setExecutionMode(OrtSession.SessionOptions.ExecutionMode.SEQUENTIAL)
            val model = assets.open("models/u2netp.onnx").use { it.readBytes() }
            OrtEnvironment.getEnvironment().createSession(model, options).also { session = it }
        }
    }

    fun cutout(source: File): Bitmap? {
        val image = decodeOriented(source)
        try {
            val resized = Bitmap.createScaledBitmap(image, StickerMask.INPUT_SIZE, StickerMask.INPUT_SIZE, true)
            val input = try {
                val pixels = IntArray(StickerMask.INPUT_SIZE * StickerMask.INPUT_SIZE)
                resized.getPixels(pixels, 0, resized.width, 0, 0, resized.width, resized.height)
                StickerMask.preprocess(pixels)
            } finally {
                if (resized !== image) resized.recycle()
            }
            val currentSession = session()
            val mask = OnnxTensor.createTensor(
                OrtEnvironment.getEnvironment(), FloatBuffer.wrap(input), longArrayOf(1, 3, 320, 320),
            ).use { tensor ->
                currentSession.run(mapOf(currentSession.inputNames.single() to tensor)).use { output ->
                    val prediction = output[0] as? OnnxTensor
                        ?: error("Expected tensor as first U2NETP output.")
                    check(prediction.info.shape.contentEquals(longArrayOf(1, 1, 320, 320))) {
                        "Unexpected U2NETP output shape."
                    }
                    val values = FloatArray(320 * 320)
                    prediction.floatBuffer.get(values)
                    StickerMask.normalize(values)
                }
            }
            val width = image.width
            val height = image.height
            val pixels = IntArray(width * height)
            image.getPixels(pixels, 0, width, 0, 0, width, height)
            for (y in 0 until height) {
                for (x in 0 until width) {
                    val index = y * width + x
                    pixels[index] = StickerMask.applyAlpha(
                        pixels[index], StickerMask.sample(mask, 320, x, y, width, height),
                    )
                }
            }
            val bounds = StickerMask.bounds(pixels, width, height) ?: return null
            return Bitmap.createBitmap(
                pixels, bounds.top * width + bounds.left, width,
                bounds.width, bounds.height, Bitmap.Config.ARGB_8888,
            )
        } finally {
            image.recycle()
        }
    }

    private fun decodeOriented(source: File): Bitmap {
        val orientation = ExifInterface(source).getAttributeInt(
            ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL,
        )
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(source.absolutePath, options)
        check(options.outWidth > 0 && options.outHeight > 0) { "Unable to decode photo dimensions." }
        var sample = 1
        while (maxOf(options.outWidth, options.outHeight) / sample > MAX_SIZE * 2) sample *= 2
        options.inJustDecodeBounds = false
        options.inSampleSize = sample
        options.inPreferredConfig = Bitmap.Config.ARGB_8888
        var bitmap = BitmapFactory.decodeFile(source.absolutePath, options)
            ?: error("Unable to decode photo.")
        try {
            val longest = maxOf(bitmap.width, bitmap.height)
            if (longest > MAX_SIZE) {
                val scale = MAX_SIZE.toFloat() / longest
                val scaled = Bitmap.createScaledBitmap(
                    bitmap, (bitmap.width * scale).roundToInt().coerceAtLeast(1),
                    (bitmap.height * scale).roundToInt().coerceAtLeast(1), true,
                )
                if (scaled !== bitmap) bitmap.recycle()
                bitmap = scaled
            }
            val matrix = Matrix().apply {
                when (orientation) {
                    ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> setScale(-1f, 1f)
                    ExifInterface.ORIENTATION_ROTATE_180 -> setRotate(180f)
                    ExifInterface.ORIENTATION_FLIP_VERTICAL -> setScale(1f, -1f)
                    ExifInterface.ORIENTATION_TRANSPOSE -> { setRotate(90f); postScale(-1f, 1f) }
                    ExifInterface.ORIENTATION_ROTATE_90 -> setRotate(90f)
                    ExifInterface.ORIENTATION_TRANSVERSE -> { setRotate(-90f); postScale(-1f, 1f) }
                    ExifInterface.ORIENTATION_ROTATE_270 -> setRotate(-90f)
                }
            }
            val oriented = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
            if (oriented !== bitmap) bitmap.recycle()
            return oriented
        } catch (error: Exception) {
            bitmap.recycle()
            throw error
        }
    }

    override fun close() {
        val current = session
        session = null
        current?.close()
        // OrtEnvironment is process-wide and may be shared by other native components.
    }

    private companion object {
        const val MAX_SIZE = 1600
    }
}
