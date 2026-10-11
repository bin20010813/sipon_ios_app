package com.example.sipon.map

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class MapCoordinateAdapterTest {
    @Test fun devicePointMatchesSharedBeijingReference() {
        val business = MapCoordinateAdapter.toBusiness(Cgcs2000Point(116.397128, 39.916527))
        assertEquals(116.403372494, business.lng, 1e-8)
        assertEquals(39.917930749, business.lat, 1e-8)
    }

    @Test fun providerRouteReturnsToItsOriginalDisplayPosition() {
        val providerPoints = listOf(
            Cgcs2000Point(116.397128, 39.916527),
            Cgcs2000Point(121.4737, 31.2304),
            Cgcs2000Point(114.0579, 22.5431),
        )
        providerPoints.forEach { provider ->
            val business = MapCoordinateAdapter.toBusiness(provider)
            val display = MapCoordinateAdapter.toDisplay(business)
            assertEquals(provider.lng, display.lng, 1e-7)
            assertEquals(provider.lat, display.lat, 1e-7)
        }
    }

    @Test fun outsideRegionIsUnchangedAndInvalidCoordinatesAreRejected() {
        val point = MapCoordinateAdapter.toDisplay(Gcj02Point(-0.1276, 51.5072))
        assertEquals(-0.1276, point.lng, 0.0)
        assertEquals(51.5072, point.lat, 0.0)
        assertFalse(MapCoordinateAdapter.valid(Double.NaN, 31.0))
        assertFalse(MapCoordinateAdapter.valid(181.0, 31.0))
    }
}
