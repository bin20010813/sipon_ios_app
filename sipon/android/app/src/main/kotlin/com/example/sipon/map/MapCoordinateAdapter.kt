package com.example.sipon.map

/** All Flutter/API coordinates are WGS-84. MapLibre receives display coordinates here. */
internal data class Wgs84Point(val lng: Double, val lat: Double)
internal data class Cgcs2000Point(val lng: Double, val lat: Double)

internal object MapCoordinateAdapter {
    const val strategy = "approximate-identity-v1"

    // The approximation must be checked against surveyed points before precise picking ships.
    fun toDisplay(point: Wgs84Point) = Cgcs2000Point(point.lng, point.lat)
    fun toBusiness(point: Cgcs2000Point) = Wgs84Point(point.lng, point.lat)

    fun valid(lng: Double, lat: Double) =
        lng.isFinite() && lat.isFinite() && lng in -180.0..180.0 && lat in -85.0..85.0
}
