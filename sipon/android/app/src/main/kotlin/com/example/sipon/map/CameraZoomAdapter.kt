package com.example.sipon.map

/** MapLibre's 512 px zoom baseline versus Sipon's existing 256 px business zoom. */
internal object CameraZoomAdapter {
    fun toNative(business: Double) = business - 1.0
    fun toBusiness(native: Double) = native + 1.0
}
