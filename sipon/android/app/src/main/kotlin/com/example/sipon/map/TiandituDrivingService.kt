package com.example.sipon.map

import android.os.Handler
import android.os.Looper
import android.util.Xml
import com.example.sipon.BuildConfig
import okhttp3.Call
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import org.xmlpull.v1.XmlPullParser
import java.io.StringReader
import java.net.URLEncoder
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit

/** Requests a single driving route through all ordered stops. */
internal class TiandituDrivingService {
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
        if (BuildConfig.TDT_ROUTE_KEY.isBlank()) {
            onResult(null, "TDT_ROUTE_KEY is missing")
            return
        }
        pending = onResult
        task = worker.submit {
            try {
                val legs = listOf(mapOf<String, Any>("coordinates" to fetchRoute(stops)))
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
        fun coordinate(point: Pair<Double, Double>) = "${point.first},${point.second}"
        val payload = JSONObject()
            .put("orig", coordinate(stops.first()))
            .put("dest", coordinate(stops.last()))
            .put("style", "0")
        if (stops.size > 2) {
            payload.put("mid", stops.subList(1, stops.lastIndex).joinToString(";") { coordinate(it) })
        }
        val query = "postStr=${encode(payload.toString())}&type=search&tk=${encode(BuildConfig.TDT_ROUTE_KEY)}" +
            if (BuildConfig.TDT_ROUTE_SK.isBlank()) "" else "&sk=${encode(BuildConfig.TDT_ROUTE_SK)}"
        val requestBuilder = Request.Builder().url("https://api.tianditu.gov.cn/drive?$query")
        if (BuildConfig.TDT_ROUTE_KEY == BuildConfig.TDT_KEY) {
            requestBuilder.header(
                "User-Agent",
                "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
            )
        }
        val request = requestBuilder.build()
        val call = client.newCall(request)
        currentCall = call
        val body = call.execute().use { response ->
            val content = response.body?.string() ?: ""
            if (content.length > 2_000_000) throw IllegalStateException("Driving response too large")
            if (!response.isSuccessful) {
                throw IllegalStateException("Tianditu driving HTTP ${response.code}: ${serviceError(content)}")
            }
            content
        }
        currentCall = null
        if (!body.trimStart().startsWith("<")) {
            throw IllegalStateException(serviceError(body))
        }
        return parseRoute(body)
    }

    private fun serviceError(body: String): String = try {
        val response = JSONObject(body)
        val code = response.optString("code")
        val message = response.optString("msg").ifBlank { response.optString("message") }
        listOf(code, message.take(100)).filter { it.isNotBlank() }.joinToString(": ")
            .ifBlank { "Tianditu driving returned an error" }
    } catch (_: Exception) {
        "Tianditu driving returned an error"
    }

    private fun parseRoute(xml: String): List<List<Double>> {
        val parser = Xml.newPullParser()
        parser.setInput(StringReader(xml))
        var routeText: String? = null
        var root: String? = null
        while (parser.eventType != XmlPullParser.END_DOCUMENT) {
            if (parser.eventType == XmlPullParser.START_TAG) {
                if (root == null) root = parser.name
                if (parser.name.equals("routelatlon", ignoreCase = true)) {
                    routeText = parser.nextText()
                }
            }
            parser.next()
        }
        if (root != "result" || routeText.isNullOrBlank()) {
            throw IllegalStateException("Tianditu driving returned no road geometry")
        }
        val coordinates = routeText.split(';').filter { it.isNotBlank() }.map { pair ->
            val parts = pair.trim().split(',')
            if (parts.size != 2) throw IllegalStateException("Invalid driving coordinate")
            val lng = parts[0].trim().toDoubleOrNull()
            val lat = parts[1].trim().toDoubleOrNull()
            if (lng == null || lat == null || !lng.isFinite() || !lat.isFinite() ||
                lng !in -180.0..180.0 || lat !in -90.0..90.0
            ) throw IllegalStateException("Invalid driving coordinate")
            listOf(lng, lat)
        }
        if (coordinates.size < 2) throw IllegalStateException("Tianditu driving route is empty")
        return coordinates
    }

    private fun encode(value: String): String = URLEncoder.encode(value, "UTF-8")
}
