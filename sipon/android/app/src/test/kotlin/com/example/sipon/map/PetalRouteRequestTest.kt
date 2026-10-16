package com.example.sipon.map

import org.junit.Assert.assertEquals
import org.junit.Test

class PetalRouteRequestTest {
    @Test fun guangzhouStopsAndRoadGeometryKeepTheMarkerCoordinateSystem() {
        // Synthetic Guangzhou GCJ-02 fixture: neither boundary may apply a GPS shift.
        val origin = Gcj02Point(113.282, 23.125)
        val destination = Gcj02Point(113.275, 23.12)
        val request = PetalRouteRequest.build(origin, destination)
        assertEquals(origin.lng, request.getJSONObject("origin").getDouble("lng"), 0.0)
        assertEquals(origin.lat, request.getJSONObject("origin").getDouble("lat"), 0.0)
        assertEquals(destination.lng, request.getJSONObject("destination").getDouble("lng"), 0.0)
        assertEquals(destination.lat, request.getJSONObject("destination").getDouble("lat"), 0.0)

        val response = """{"returnCode":"0","routes":[{"paths":[{"steps":[
            {"polyline":[{"lng":113.282,"lat":23.125},{"lng":113.278,"lat":23.123},{"lng":113.275,"lat":23.12}]}
        ]}]}]}"""
        assertEquals(listOf(
            listOf(origin.lng, origin.lat), listOf(113.278, 23.123),
            listOf(destination.lng, destination.lat),
        ), PetalRouteParser.parse(response))
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsInvalidStopBeforeMakingARequest() {
        PetalRouteRequest.build(Gcj02Point(Double.NaN, 23.125), Gcj02Point(113.275, 23.12))
    }
}
