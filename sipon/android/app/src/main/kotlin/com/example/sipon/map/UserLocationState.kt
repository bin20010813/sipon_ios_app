package com.example.sipon.map

/** Device fixes only, already normalized to GCJ-02. Never populated by camera moves. */
internal class UserLocationState {
    private var point: Gcj02Point? = null
    private var timestampNanos = Long.MIN_VALUE

    fun update(value: Gcj02Point, fixNanos: Long, nowNanos: Long) {
        if (!MapCoordinateAdapter.valid(value.lng, value.lat) ||
            fixNanos > nowNanos || nowNanos - fixNanos > maxAgeNanos ||
            fixNanos < timestampNanos) return
        point = value
        timestampNanos = fixNanos
    }

    fun current(nowNanos: Long): Gcj02Point? {
        val value = point ?: return null
        return value.takeIf { nowNanos >= timestampNanos && nowNanos - timestampNanos <= maxAgeNanos }
    }

    fun clear() { point = null; timestampNanos = Long.MIN_VALUE }

    private companion object { const val maxAgeNanos = 120_000_000_000L }
}
