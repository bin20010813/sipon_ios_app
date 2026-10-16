package com.example.sipon.map

import org.junit.Assert.assertEquals
import org.junit.Test

class PetalRouteParserTest {
    private fun response(polyline: String) = """{"returnCode":"0","routes":[{"paths":[{"steps":[{"polyline":$polyline}]}]}]}"""

    @Test fun preservesLongitudeLatitudeAndRemovesDuplicateStepJoints() {
        val body = """{"returnCode":"0","routes":[{"paths":[{"steps":[
            {"polyline":[{"lng":116.397128,"lat":39.916527},{"lng":116.398,"lat":39.917}]},
            {"polyline":[{"lng":116.398,"lat":39.917},{"lng":116.399,"lat":39.918}]}
        ]}]}]}"""
        assertEquals(listOf(listOf(116.397128, 39.916527), listOf(116.398, 39.917), listOf(116.399, 39.918)), PetalRouteParser.parse(body))
    }

    @Test(expected = IllegalStateException::class)
    fun rejectsProviderFailureEvenWhenGeometryExists() {
        PetalRouteParser.parse(response("[]").replace("\"0\"", "\"010001\""))
    }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsEmptyGeometryInsteadOfDrawingStraightLine() { PetalRouteParser.parse(response("[]")) }

    @Test(expected = IllegalArgumentException::class)
    fun rejectsOutOfRangeCoordinates() {
        PetalRouteParser.parse(response("""[{"lng":181,"lat":39},{"lng":116,"lat":39}]"""))
    }
}
