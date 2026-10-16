package com.example.sipon

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class StickerMaskTest {
    @Test
    fun preprocessingUsesGlobalRgbMaximumAndChannelFirstLayout() {
        val actual = StickerMask.preprocess(intArrayOf(0xff804020.toInt(), 0xff204080.toInt()))
        assertArrayEquals(floatArrayOf(
            (1f - 0.485f) / 0.229f, (0.25f - 0.485f) / 0.229f,
            (0.5f - 0.456f) / 0.224f, (0.5f - 0.456f) / 0.224f,
            (0.25f - 0.406f) / 0.225f, (1f - 0.406f) / 0.225f,
        ), actual, 1e-6f)
    }

    @Test
    fun blackInputIsFinite() {
        val actual = StickerMask.preprocess(intArrayOf(0xff000000.toInt(), 0))
        assertTrue(actual.all { it.isFinite() })
        assertEquals(-0.485f / 0.229f, actual[0], 1e-6f)
    }

    @Test
    fun inputHasExpectedNchwElementCount() {
        assertEquals(3 * 320 * 320, StickerMask.preprocess(IntArray(320 * 320)).size)
    }

    @Test
    fun normalizationUsesMinMax() {
        assertArrayEquals(floatArrayOf(0f, 0.5f, 1f), StickerMask.normalize(floatArrayOf(-2f, 0f, 2f)), 1e-6f)
    }

    @Test
    fun constantAndNearConstantMasksHaveNoSubject() {
        for (values in listOf(floatArrayOf(0f, 0f), floatArrayOf(1f, 1f), floatArrayOf(0f, 1e-8f))) {
            assertArrayEquals(floatArrayOf(0f, 0f), StickerMask.normalize(values), 0f)
        }
    }

    @Test(expected = IllegalArgumentException::class)
    fun nanOutputFailsInsteadOfGeneratingOpaqueSticker() {
        StickerMask.normalize(floatArrayOf(0f, Float.NaN, 1f))
    }

    @Test(expected = IllegalArgumentException::class)
    fun infiniteOutputFails() {
        StickerMask.normalize(floatArrayOf(0f, Float.POSITIVE_INFINITY))
    }

    @Test
    fun normalizationAvoidsFloatRangeOverflow() {
        assertArrayEquals(floatArrayOf(0f, 0.5f, 1f),
            StickerMask.normalize(floatArrayOf(-Float.MAX_VALUE, 0f, Float.MAX_VALUE)), 1e-6f)
    }

    @Test
    fun resizeUsesBilinearInterpolationAndClampsEdges() {
        val mask = floatArrayOf(0f, 1f, 1f, 0f)
        assertEquals(0.5f, StickerMask.sample(mask, 2, 1, 1, 3, 3), 1e-6f)
        assertEquals(0f, StickerMask.sample(mask, 2, 0, 0, 4, 4), 1e-6f)
        assertEquals(1f, StickerMask.sample(mask, 2, 3, 0, 4, 4), 1e-6f)
    }

    @Test
    fun alphaIsMultipliedRatherThanReplacedAndRgbIsPreserved() {
        val pixel = StickerMask.applyAlpha(0x80402010.toInt(), 0.5f)
        assertEquals(64, pixel ushr 24)
        assertEquals(0x402010, pixel and 0xffffff)
        assertEquals(0, StickerMask.applyAlpha(0x00402010, 1f))
    }

    @Test
    fun tinyBackgroundAlphaIsRemovedWithoutFlatteningSoftEdges() {
        assertEquals(0, StickerMask.applyAlpha(0xffffffff.toInt(), 0.03f))
        assertEquals(128, StickerMask.applyAlpha(0xffffffff.toInt(), 0.5f) ushr 24)
    }

    @Test
    fun boundsIgnoreNoiseAndIncludeLastRowAndColumn() {
        val pixels = IntArray(12) { 0x08000000 }
        pixels[6] = 0x40000000
        pixels[11] = 0xff000000.toInt()
        assertEquals(StickerMask.Bounds(2, 1, 2, 2), StickerMask.bounds(pixels, 4, 3))
    }

    @Test
    fun emptyForegroundReturnsNoBounds() {
        assertNull(StickerMask.bounds(IntArray(6), 2, 3))
        assertNull(StickerMask.bounds(IntArray(6) { 0x08000000 }, 2, 3))
    }
}
