package com.example.sipon.map

import org.json.JSONObject

/** Parses road geometry only; encoded overview polylines are not coordinate arrays. */
internal object PetalRouteParser {
    fun parse(body: String): List<List<Double>> {
        val response = JSONObject(body)
        val code = response.optString("returnCode")
        if (code != "0") error("Petal driving error $code")
        val routes = response.getJSONArray("routes")
        require(routes.length() > 0) { "No driving route" }
        val paths = routes.getJSONObject(0).getJSONArray("paths")
        val leg = mutableListOf<List<Double>>()
        for (pathIndex in 0 until paths.length()) {
            val steps = paths.getJSONObject(pathIndex).getJSONArray("steps")
            for (stepIndex in 0 until steps.length()) {
                val polyline = steps.getJSONObject(stepIndex).getJSONArray("polyline")
                for (pointIndex in 0 until polyline.length()) {
                    val point = polyline.getJSONObject(pointIndex)
                    val lng = point.getDouble("lng")
                    val lat = point.getDouble("lat")
                    require(MapCoordinateAdapter.valid(lng, lat)) { "Invalid driving coordinate" }
                    val next = listOf(lng, lat)
                    if (leg.lastOrNull() != next) leg.add(next)
                }
            }
        }
        require(leg.size >= 2) { "Invalid driving geometry" }
        return leg
    }
}
