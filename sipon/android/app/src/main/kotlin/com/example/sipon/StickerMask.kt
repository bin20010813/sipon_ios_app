package com.example.sipon

import kotlin.math.floor
import kotlin.math.roundToInt

/** Pure numerical operations, kept independent of Android and ONNX for regression tests. */
internal object StickerMask {
    const val INPUT_SIZE = 320
    const val ALPHA_THRESHOLD = 8
    private val mean = floatArrayOf(0.485f, 0.456f, 0.406f)
    private val std = floatArrayOf(0.229f, 0.224f, 0.225f)

    fun preprocess(pixels: IntArray): FloatArray {
        require(pixels.isNotEmpty())
        var maximum = 0
        for (pixel in pixels) {
            maximum = maxOf(maximum, (pixel ushr 16) and 255, (pixel ushr 8) and 255, pixel and 255)
        }
        val divisor = maximum.coerceAtLeast(1).toFloat()
        return FloatArray(pixels.size * 3) { index ->
            val channel = index / pixels.size
            val value = (pixels[index % pixels.size] ushr (16 - channel * 8)) and 255
            (value / divisor - mean[channel]) / std[channel]
        }
    }

    fun normalize(values: FloatArray): FloatArray {
        require(values.isNotEmpty())
        require(values.all { it.isFinite() }) { "Non-finite saliency output." }
        val minimum = values.minOrNull()!!.toDouble()
        val range = values.maxOrNull()!!.toDouble() - minimum
        // Constant predictions carry no usable foreground/background distinction.
        if (range <= 1e-6) return FloatArray(values.size)
        return FloatArray(values.size) { ((values[it] - minimum) / range).toFloat().coerceIn(0f, 1f) }
    }

    fun sample(mask: FloatArray, size: Int, x: Int, y: Int, width: Int, height: Int): Float {
        val sx = ((x + 0.5f) * size / width - 0.5f).coerceIn(0f, (size - 1).toFloat())
        val sy = ((y + 0.5f) * size / height - 0.5f).coerceIn(0f, (size - 1).toFloat())
        val x0 = floor(sx).toInt()
        val y0 = floor(sy).toInt()
        val x1 = minOf(x0 + 1, size - 1)
        val y1 = minOf(y0 + 1, size - 1)
        val dx = sx - x0
        val dy = sy - y0
        val top = mask[y0 * size + x0] * (1 - dx) + mask[y0 * size + x1] * dx
        val bottom = mask[y1 * size + x0] * (1 - dx) + mask[y1 * size + x1] * dx
        return top * (1 - dy) + bottom * dy
    }

    fun applyAlpha(pixel: Int, confidence: Float): Int {
        val alpha = ((pixel ushr 24) * confidence.coerceIn(0f, 1f)).roundToInt()
        return if (alpha <= ALPHA_THRESHOLD) 0 else (pixel and 0x00ffffff) or (alpha shl 24)
    }

    data class Bounds(val left: Int, val top: Int, val width: Int, val height: Int)

    fun bounds(pixels: IntArray, width: Int, height: Int): Bounds? {
        require(width > 0 && height > 0 && pixels.size == width * height)
        var left = width
        var top = height
        var right = -1
        var bottom = -1
        pixels.forEachIndexed { index, pixel ->
            if ((pixel ushr 24) > ALPHA_THRESHOLD) {
                val x = index % width
                val y = index / width
                left = minOf(left, x)
                right = maxOf(right, x)
                top = minOf(top, y)
                bottom = maxOf(bottom, y)
            }
        }
        return if (right < left) null else Bounds(left, top, right - left + 1, bottom - top + 1)
    }
}
