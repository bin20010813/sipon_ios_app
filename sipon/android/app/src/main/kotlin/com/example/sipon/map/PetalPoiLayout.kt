package com.example.sipon.map

import kotlin.math.floor
import kotlin.math.min

/** Layout in logical pixels. Reduce candidates before calling the SDK projection. */
internal object PetalPoiLayout {
    data class GeoPoint(
        val id: String,
        val longitude: Double,
        val latitude: Double,
        val hasLabel: Boolean,
        val selected: Boolean = false,
        val routeStop: Boolean = false,
    )

    data class Candidate(
        val id: String,
        val x: Double,
        val y: Double,
        val hasLabel: Boolean,
        val selected: Boolean = false,
        val routeStop: Boolean = false,
        val labelWidth: Double = 132.0,
        val labelHeight: Double = 80.0,
    )

    data class Placement(val id: String, val label: Boolean)

    private data class Bounds(val left: Double, val top: Double, val right: Double, val bottom: Double) {
        fun intersects(other: Bounds) = left < other.right && right > other.left &&
            top < other.bottom && bottom > other.top
    }

    fun shortlist(
        points: List<GeoPoint>, west: Double, south: Double, east: Double, north: Double,
        width: Double, height: Double,
    ): List<GeoPoint> {
        val longitudeSpan = (east - west).let { if (it < 0) it + 360 else it }
        val latitudeSpan = north - south
        if (width <= 0 || height <= 0 || longitudeSpan <= 0 || latitudeSpan <= 0) return emptyList()
        val columns = floor(width / 44).toInt().coerceIn(1, 8)
        val rows = floor(height / 44).toInt().coerceIn(1, 12)
        val cells = linkedMapOf<Int, GeoPoint>()
        val priority = mutableListOf<GeoPoint>()
        for (point in points) {
            if (!point.longitude.isFinite() || !point.latitude.isFinite()) continue
            val x = ((point.longitude - west + 360) % 360) / longitudeSpan
            val y = (point.latitude - south) / latitudeSpan
            if (x !in 0.0..1.0 || y !in 0.0..1.0) continue
            if (point.selected || point.routeStop) { priority.add(point); continue }
            val cell = (y * rows).toInt().coerceAtMost(rows - 1) * columns +
                (x * columns).toInt().coerceAtMost(columns - 1)
            val existing = cells[cell]
            // A label-capable venue represents its cell; ID breaks ties consistently
            // across API response ordering changes. There are no count markers.
            if (existing == null || (point.hasLabel && !existing.hasLabel) ||
                (point.hasLabel == existing.hasLabel && point.id < existing.id)) cells[cell] = point
        }
        return priority + cells.values
    }

    fun select(
        candidates: List<Candidate>, width: Double, height: Double, zoom: Double,
        topInset: Double = 0.0, bottomInset: Double = 0.0,
    ): List<Placement> {
        if (width <= 0 || height <= 0) return emptyList()
        val top = topInset.coerceIn(0.0, height)
        val bottom = (height - bottomInset).coerceIn(top, height)
        val availableArea = width * (bottom - top)
        val labelBudget = min(
            when { zoom < 12 -> 6; zoom < 14 -> 8; zoom < 16 -> 9; else -> 10 },
            floor(availableArea / (140 * 90)).toInt().coerceAtLeast(1),
        )
        val dotBudget = min(
            when { zoom < 12 -> 24; zoom < 14 -> 36; zoom < 16 -> 48; else -> 64 },
            floor(availableArea / (36 * 36)).toInt(),
        )
        val centerX = width / 2
        val centerY = (top + bottom) / 2
        fun distance(point: Candidate) = (point.x - centerX) * (point.x - centerX) +
            (point.y - centerY) * (point.y - centerY)
        val ordered = candidates.filter {
            it.x.isFinite() && it.y.isFinite() && it.x in 0.0..width && it.y in 0.0..height
        }.sortedWith(compareByDescending<Candidate> { it.selected }
            .thenByDescending { it.routeStop }.thenBy { distance(it) }.thenBy { it.id })
        val result = linkedMapOf<String, Placement>()
        val occupied = mutableListOf<Bounds>()
        var labels = 0
        for (point in ordered) {
            val priority = point.selected || point.routeStop
            if (!point.hasLabel && !priority) continue
            if (!priority && (labels >= labelBudget || point.y < top || point.y > bottom)) continue
            val bounds = Bounds(point.x - point.labelWidth / 2 - 6, point.y - 18,
                point.x + point.labelWidth / 2 + 6, point.y - 14 + point.labelHeight + 4)
            if (!priority && (bounds.left < 4 || bounds.right > width - 4 ||
                    bounds.top < top || bounds.bottom > bottom || occupied.any { it.intersects(bounds) })) continue
            result[point.id] = Placement(point.id, true)
            occupied.add(bounds)
            // Selection uses one of the visible label slots; route stops remain
            // exempt so a planned route never loses its numbered stops.
            if (!point.routeStop) labels++
        }
        var dots = 0
        for (point in ordered) {
            if (dots >= dotBudget) break
            if (result.containsKey(point.id) || point.y < top + 8 || point.y > bottom - 8 ||
                point.x < 8 || point.x > width - 8) continue
            val bounds = Bounds(point.x - 18, point.y - 18, point.x + 18, point.y + 18)
            if (occupied.any { it.intersects(bounds) }) continue
            result[point.id] = Placement(point.id, false)
            occupied.add(bounds)
            dots++
        }
        return result.values.toList()
    }
}
