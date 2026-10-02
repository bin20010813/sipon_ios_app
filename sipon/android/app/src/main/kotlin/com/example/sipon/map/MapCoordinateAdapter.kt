package com.example.sipon.map

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import kotlin.math.sqrt

/** Trial assumption: Flutter/API business coordinates are GCJ-02. */
internal data class Gcj02Point(val lng: Double, val lat: Double)
internal data class Cgcs2000Point(val lng: Double, val lat: Double)

internal object MapCoordinateAdapter {
    const val strategy = "gcj02-to-cgcs2000-v1"

    private const val semiMajorAxis = 6378245.0
    private const val eccentricitySquared = 0.006693421622965943
    private const val inverseIterations = 4

    /**
     * Tianditu's `_w` tiles use an unencrypted geographic datum with Web
     * Mercator tiling. CGCS2000 and WGS-84 are close enough for this map
     * display, so the material correction here is removal of the GCJ-02
     * offset. Iteration avoids the larger error of a one-step subtraction.
     */
    fun toDisplay(point: Gcj02Point): Cgcs2000Point {
        if (outsideChina(point.lng, point.lat)) return Cgcs2000Point(point.lng, point.lat)
        var lng = point.lng
        var lat = point.lat
        repeat(inverseIterations) {
            val projected = fromUnshifted(lng, lat)
            lng -= projected.lng - point.lng
            lat -= projected.lat - point.lat
        }
        return Cgcs2000Point(lng, lat)
    }

    fun toBusiness(point: Cgcs2000Point): Gcj02Point =
        if (outsideChina(point.lng, point.lat)) Gcj02Point(point.lng, point.lat)
        else fromUnshifted(point.lng, point.lat)

    fun valid(lng: Double, lat: Double) =
        lng.isFinite() && lat.isFinite() && lng in -180.0..180.0 && lat in -85.0..85.0

    private fun outsideChina(lng: Double, lat: Double) =
        lng !in 72.004..137.8347 || lat !in 0.8293..55.8271

    private fun fromUnshifted(lng: Double, lat: Double): Gcj02Point {
        var dLat = transformLat(lng - 105.0, lat - 35.0)
        var dLng = transformLng(lng - 105.0, lat - 35.0)
        val radLat = lat / 180.0 * PI
        val sinLat = sin(radLat)
        val magic = 1 - eccentricitySquared * sinLat * sinLat
        val sqrtMagic = sqrt(magic)
        dLat = dLat * 180.0 /
            ((semiMajorAxis * (1 - eccentricitySquared) / (magic * sqrtMagic)) * PI)
        dLng = dLng * 180.0 /
            ((semiMajorAxis / sqrtMagic * kotlin.math.cos(radLat)) * PI)
        return Gcj02Point(lng + dLng, lat + dLat)
    }

    private fun transformLat(x: Double, y: Double): Double {
        var result = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y +
            0.1 * x * y + 0.2 * sqrt(abs(x))
        result += (20.0 * sin(6.0 * x * PI) + 20.0 * sin(2.0 * x * PI)) * 2.0 / 3.0
        result += (20.0 * sin(y * PI) + 40.0 * sin(y / 3.0 * PI)) * 2.0 / 3.0
        result += (160.0 * sin(y / 12.0 * PI) + 320 * sin(y * PI / 30.0)) * 2.0 / 3.0
        return result
    }

    private fun transformLng(x: Double, y: Double): Double {
        var result = 300.0 + x + 2.0 * y + 0.1 * x * x +
            0.1 * x * y + 0.1 * sqrt(abs(x))
        result += (20.0 * sin(6.0 * x * PI) + 20.0 * sin(2.0 * x * PI)) * 2.0 / 3.0
        result += (20.0 * sin(x * PI) + 40.0 * sin(x / 3.0 * PI)) * 2.0 / 3.0
        result += (150.0 * sin(x / 12.0 * PI) + 300.0 * sin(x / 30.0 * PI)) * 2.0 / 3.0
        return result
    }
}
