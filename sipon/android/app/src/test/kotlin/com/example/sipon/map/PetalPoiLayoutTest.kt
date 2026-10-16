package com.example.sipon.map

import org.junit.Assert.*
import org.junit.Test

class PetalPoiLayoutTest {
    @Test fun limitsProjectionWorkBeforeCreatingSdkMarkers() {
        val points = (0 until 20_000).map {
            PetalPoiLayout.GeoPoint("venue-$it", 116.0 + (it % 200) / 200.0,
                39.0 + (it / 200) / 100.0, it % 5 == 0)
        } + PetalPoiLayout.GeoPoint("selected", 116.5, 39.5, true, selected = true)
        val shortlisted = PetalPoiLayout.shortlist(points, 116.0, 39.0, 117.0, 40.0, 400.0, 900.0)
        assertTrue(shortlisted.size <= 97)
        assertTrue(shortlisted.any { it.id == "selected" })
    }

    @Test fun coarseSamplingIsStableAcrossResponseOrdering() {
        val points = listOf(
            PetalPoiLayout.GeoPoint("b", 116.51, 39.51, true),
            PetalPoiLayout.GeoPoint("a", 116.51, 39.51, true),
            PetalPoiLayout.GeoPoint("dot", 116.51, 39.51, false),
        )
        fun shortlist(input: List<PetalPoiLayout.GeoPoint>) = PetalPoiLayout.shortlist(
            input, 116.0, 39.0, 117.0, 40.0, 400.0, 900.0).map { it.id }
        assertEquals(listOf("a"), shortlist(points))
        assertEquals(shortlist(points), shortlist(points.reversed()))
    }

    @Test fun excludesOffscreenAndNonFiniteGeographicPointsIncludingAntimeridian() {
        val points = listOf(
            PetalPoiLayout.GeoPoint("inside", -175.0, 20.0, true),
            PetalPoiLayout.GeoPoint("outside", 0.0, 20.0, true),
            PetalPoiLayout.GeoPoint("invalid", Double.NaN, 20.0, true),
        )
        assertEquals(listOf("inside"), PetalPoiLayout.shortlist(points,
            170.0, 10.0, -170.0, 30.0, 400.0, 900.0).map { it.id })
    }

    @Test fun denseCityViewShowsSixLabelsAndAtMost24Dots() {
        val candidates = (0 until 1200).map {
            PetalPoiLayout.Candidate("$it", 10.0 + (it % 20) * 20.0,
                10.0 + (it / 20) * 15.0, true)
        }
        val selected = PetalPoiLayout.select(candidates, 420.0, 950.0, 11.8, 140.0, 220.0)
        assertEquals(6, selected.count { it.label })
        assertTrue(selected.count { !it.label } <= 24)
        assertTrue(selected.any { !it.label })
        assertEquals(selected.size, selected.map { it.id }.distinct().size)
        val byId = candidates.associateBy { it.id }
        assertTrue(selected.all { byId.getValue(it.id).y in 140.0..730.0 })
    }

    @Test fun preservesSelectionAndAllNumberedRouteStopsEvenWhenTheyOverlap() {
        val candidates = (0 until 12).map {
            PetalPoiLayout.Candidate("route-$it", 150.0, 150.0, true, routeStop = true)
        } + PetalPoiLayout.Candidate("selection", 150.0, 150.0, false, selected = true)
        val selected = PetalPoiLayout.select(candidates, 400.0, 700.0, 11.8)
        assertEquals(13, selected.size)
        assertTrue(selected.all { it.label })
        assertEquals("selection", selected.first().id)
    }

    @Test fun dotSpacingAndLabelCollisionAvoidStacking() {
        val candidates = listOf(
            PetalPoiLayout.Candidate("label", 200.0, 200.0, true, selected = true),
            PetalPoiLayout.Candidate("overlap", 201.0, 201.0, true),
            PetalPoiLayout.Candidate("near-dot", 210.0, 210.0, false),
            PetalPoiLayout.Candidate("far-dot", 350.0, 350.0, false),
        )
        val selected = PetalPoiLayout.select(candidates, 450.0, 800.0, 15.0)
        assertEquals(listOf("label", "far-dot"), selected.map { it.id })
    }

    @Test fun highZoomCapsLabelsAtTenIncludingSelection() {
        val candidates = (0 until 49).map {
            PetalPoiLayout.Candidate("$it", 100.0 + (it % 7) * 160.0,
                100.0 + (it / 7) * 130.0, true)
        }
        val selected = PetalPoiLayout.select(candidates + PetalPoiLayout.Candidate(
            "selection", 80.0, 80.0, true, selected = true), 1200.0, 1200.0, 18.0)
        assertEquals(10, selected.count { it.label })
        assertTrue(selected.any { it.id == "selection" })
        assertTrue(PetalPoiLayout.select(candidates, 0.0, 0.0, 18.0).isEmpty())
    }

    @Test fun usesActualLabelDimensionsToFitRatingsOnPhoneScreen() {
        val candidates = (0 until 12).map {
            PetalPoiLayout.Candidate("$it", 65.0 + (it % 3) * 140.0,
                220.0 + (it / 3) * 120.0, true, labelWidth = 88.0, labelHeight = 76.0)
        }
        val selected = PetalPoiLayout.select(candidates, 420.0, 950.0, 14.5, 140.0, 220.0)
        assertEquals(9, selected.count { it.label })
        val positions = candidates.associateBy { it.id }
        val labels = selected.filter { it.label }.map { positions.getValue(it.id) }
        for ((index, a) in labels.withIndex()) for (b in labels.drop(index + 1)) {
            assertTrue(kotlin.math.abs(a.x - b.x) >= (a.labelWidth + b.labelWidth) / 2 + 12 ||
                kotlin.math.abs(a.y - b.y) >= (a.labelHeight + b.labelHeight) / 2 + 8)
        }
    }
}
