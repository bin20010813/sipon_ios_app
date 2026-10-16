package com.example.sipon.map

import android.os.Handler
import android.os.Looper
import com.example.sipon.BuildConfig
import okhttp3.Call
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.net.URLEncoder
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit

/** Requests a single driving route through all ordered stops. */
internal class PetalDrivingService {
    private val client = OkHttpClient.Builder()
        .connectTimeout(8, TimeUnit.SECONDS)
        .callTimeout(30, TimeUnit.SECONDS)
        .build()
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var currentCall: Call? = null
    private var task: Future<*>? = null
    private var generation = 0L
    private var pending: ((List<Map<String, Any>>?, String?) -> Unit)? = null

    fun plan(stops: List<Pair<Double, Double>>, onResult: (List<Map<String, Any>>?, String?) -> Unit) {
        cancel()
        val revision = generation
        if (BuildConfig.PETAL_ROUTE_KEY.isBlank()) {
            onResult(null, "PETAL_ROUTE_KEY is missing")
            return
        }
        pending = onResult
        task = worker.submit {
            try {
                // Directions API geometry is WGS-84; shared/Dart geometry is GCJ-02.
                val business = fetchRoute(stops).map { pair ->
                    MapCoordinateAdapter.toBusiness(Wgs84Point(pair[0], pair[1])).let {
                        listOf(it.lng, it.lat)
                    }
                }
                val legs = listOf(mapOf<String, Any>("coordinates" to business))
                main.post { if (revision == generation) finish(legs, null) }
            } catch (error: Exception) {
                main.post { if (revision == generation) finish(null, error.message ?: "Driving route failed") }
            }
        }
    }

    private fun finish(legs: List<Map<String, Any>>?, error: String?) {
        val callback = pending ?: return
        pending = null
        callback(legs, error)
    }

    fun cancel() {
        generation++
        finish(null, "Driving route cancelled")
        currentCall?.cancel()
        currentCall = null
        task?.cancel(true)
        task = null
    }

    fun dispose() {
        cancel()
        worker.shutdownNow()
    }

    private fun fetchRoute(stops: List<Pair<Double, Double>>): List<List<Double>> {
        val coordinates = mutableListOf<List<Double>>()
        // Plan consecutive legs so every ordered stop is visited.
        stops.zipWithNext().forEach { (origin, destination) ->
            if (Thread.currentThread().isInterrupted) error("Driving route cancelled")
            fun location(point: Pair<Double, Double>) = JSONObject().put("lng", point.first).put("lat", point.second)
            val payload = JSONObject().put("origin", location(origin)).put("destination", location(destination))
            val request = Request.Builder()
                .url("https://mapapi.cloud.huawei.com/mapApi/v1/routeService/driving?key=" + URLEncoder.encode(BuildConfig.PETAL_ROUTE_KEY, "UTF-8"))
                .post(payload.toString().toRequestBody("application/json; charset=utf-8".toMediaType()))
                .build()
            val call = client.newCall(request)
            currentCall = call
            val responseBody = call.execute().use { response ->
                if (!response.isSuccessful) error("Petal driving HTTP ${response.code}")
                val body = response.body ?: error("Empty driving response")
                val source = body.source()
                source.request(2_000_001)
                require(source.buffer.size <= 2_000_000) { "Driving response too large" }
                source.readUtf8()
            }
            currentCall = null
            val leg = PetalRouteParser.parse(responseBody)
            coordinates.addAll(if (coordinates.lastOrNull() == leg.first()) leg.drop(1) else leg)
        }
        return coordinates
    }
}
