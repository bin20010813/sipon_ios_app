package com.example.sipon.map

import org.json.JSONObject

/** Mainland Navi Kit accepts the same GCJ-02 points used by our map markers. */
internal object PetalRouteRequest {
    fun build(origin: Gcj02Point, destination: Gcj02Point): JSONObject {
        fun location(point: Gcj02Point): JSONObject {
            require(MapCoordinateAdapter.valid(point.lng, point.lat)) { "Invalid route stop" }
            return JSONObject().put("lng", point.lng).put("lat", point.lat)
        }
        return JSONObject()
            .put("origin", location(origin))
            .put("destination", location(destination))
    }
}
