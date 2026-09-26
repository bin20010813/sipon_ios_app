package com.example.sipon.map

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PointF
import android.graphics.RectF
import android.os.Bundle
import android.view.View
import com.example.sipon.BuildConfig
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import okhttp3.Dispatcher
import okhttp3.OkHttpClient
import org.json.JSONArray
import org.json.JSONObject
import org.maplibre.android.MapLibre
import org.maplibre.android.camera.CameraPosition
import org.maplibre.android.camera.CameraUpdateFactory
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.geometry.LatLngBounds
import org.maplibre.android.maps.MapLibreMap
import org.maplibre.android.maps.MapView
import org.maplibre.android.maps.Style
import org.maplibre.android.module.http.HttpRequestUtil
import org.maplibre.android.style.expressions.Expression
import org.maplibre.android.style.layers.CircleLayer
import org.maplibre.android.style.layers.LineLayer
import org.maplibre.android.style.layers.PropertyFactory.*
import org.maplibre.android.style.layers.RasterLayer
import org.maplibre.android.style.layers.SymbolLayer
import org.maplibre.android.style.sources.GeoJsonSource
import org.maplibre.android.style.sources.GeoJsonOptions
import java.net.URLEncoder
import kotlin.math.max

/** One Flutter PlatformView owns one MapView, channel, style and business frame. */
internal class SiponTiandituView(
    context: Context,
    viewId: Int,
    messenger: BinaryMessenger,
    private val onDisposed: (SiponTiandituView) -> Unit,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val mapView: MapView
    private val channel = MethodChannel(messenger, "sipon/tianditu_$viewId")
    private val density = context.resources.displayMetrics.density
    private var map: MapLibreMap? = null
    private var alive = true
    private var ready = false
    private var setupRequested = false
    private var sentReady = false
    private var styleRevision = 0
    private var requestedStyleRevision = 0L
    private var routeRevision = -1L
    private var styleId = "standard"
    private var dark = false
    private val useDarkPalette get() = dark || styleId == "muted"
    private var bottomPaddingDp = 0.0
    private var frame: Map<*, *>? = null
    private var route: JSONArray? = null
    private val assets = mutableMapOf<String, Bitmap>()
    private val markerImages = mutableSetOf<String>()
    private data class MarkerCandidate(
        val feature: JSONObject,
        val location: LatLng,
        val width: Int,
        val height: Int,
        val selected: Boolean,
    )
    private var markerCandidates = emptyList<MarkerCandidate>()
    private var circleCandidates = emptyList<JSONObject>()
    private var lastCamera: Map<*, *>? = null
    private val cameraIdle = MapLibreMap.OnCameraIdleListener {
        if (ready && alive) {
            updateMarkerVisibility()
            send("onViewportSettled", viewport())
        }
    }
    private val mapClick = MapLibreMap.OnMapClickListener { point ->
        val current = map ?: return@OnMapClickListener false
        val pixel = current.projection.toScreenLocation(point)
        val radius = 22f * density
        val hits = current.queryRenderedFeatures(
            RectF(pixel.x - radius, pixel.y - radius, pixel.x + radius, pixel.y + radius),
            "sipon-selected-label", "sipon-labels", "sipon-selected", "sipon-circles", "sipon-clusters",
        )
        val venueId = hits.firstNotNullOfOrNull { feature ->
            if (feature.hasProperty("venueId")) feature.getStringProperty("venueId").takeIf { it.isNotBlank() } else null
        }
        if (venueId == null && hits.any { it.hasProperty("point_count") }) {
            current.animateCamera(CameraUpdateFactory.newLatLngZoom(point, (current.cameraPosition.zoom + 1.5).coerceAtMost(20.0)))
        } else if (venueId == null) send("onBlankTapped", null)
        else send("onVenueTapped", mapOf("venueId" to venueId))
        true
    }

    companion object {
        private const val BROWSER_USER_AGENT =
            "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
        private var tileHttpClientInstalled = false

        /**
         * 天地图对“浏览器端”Key 强制校验浏览器 User-Agent（否则 403，code 301012 权限类型错误），
         * MapLibre 默认 UA 为 “MapLibre Android/…” 会被拒绝。这里只对天地图域名覆写 UA，
         * 其余请求保持 MapLibre 默认客户端行为（含 SDK>=21 时 maxRequestsPerHost=20 的调度器）。
         */
        private fun installTileHttpClient() {
            if (tileHttpClientInstalled) return
            val dispatcher = Dispatcher().apply { maxRequestsPerHost = 20 }
            HttpRequestUtil.setOkHttpClient(
                OkHttpClient.Builder()
                    .dispatcher(dispatcher)
                    .addInterceptor { chain ->
                        val request = chain.request()
                        if (request.url.host.endsWith("tianditu.gov.cn")) {
                            chain.proceed(request.newBuilder().header("User-Agent", BROWSER_USER_AGENT).build())
                        } else {
                            chain.proceed(request)
                        }
                    }
                    .build(),
            )
            tileHttpClientInstalled = true
        }
    }

    init {
        // HttpRequestImpl 的静态初始化经 HttpIdentifier 读取 MapLibre 应用上下文，
        // 必须先 MapLibre.getInstance 再注入自定义 OkHttpClient，否则抛 MapLibreConfigurationException。
        MapLibre.getInstance(context)
        installTileHttpClient()
        mapView = MapView(context)
        mapView.addOnLayoutChangeListener { _, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom ->
            if (ready && (right - left != oldRight - oldLeft || bottom - top != oldBottom - oldTop)) {
                updateMarkerVisibility()
            }
        }
        channel.setMethodCallHandler(this)
        mapView.onCreate(Bundle())
        mapView.onStart()
        mapView.onResume()
        mapView.getMapAsync { loaded ->
            if (!alive) return@getMapAsync
            map = loaded
            loaded.addOnCameraIdleListener(cameraIdle)
            loaded.addOnMapClickListener(mapClick)
            loaded.uiSettings.isTiltGesturesEnabled = false
            loaded.uiSettings.isCompassEnabled = false
            loaded.uiSettings.isAttributionEnabled = true
            if (setupRequested) loadStyle()
        }
    }

    override fun getView(): View = mapView

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (!alive) {
            result.error("disposed", "Map view was disposed", null)
            return
        }
        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        try {
            when (call.method) {
                "setup" -> {
                    setupRequested = true
                    styleId = args["styleId"] as? String ?: "standard"
                    val start = point(args)
                    val city = args["city"] as? String ?: ""
                    val fallback = cityCenter(city)
                    val target = start ?: fallback
                    lastCamera = mapOf(
                        "lng" to target.lng, "lat" to target.lat,
                        "zoom" to ((args["zoom"] as? Number)?.toDouble()
                            ?: if (start == null) 11.8 else 15.0),
                        "bearing" to 0.0, "bottomPadding" to 0.0,
                    )
                    if (map != null) loadStyle()
                    result.success(null)
                }
                "setStyle" -> {
                    styleId = args["styleId"] as? String ?: "standard"
                    requestedStyleRevision = (args["revision"] as? Number)?.toLong() ?: requestedStyleRevision + 1
                    if (map != null && setupRequested) loadStyle()
                    result.success(null)
                }
                "setAppearance" -> {
                    val changed = dark != (args["brightness"] == "dark")
                    dark = args["brightness"] == "dark"
                    if (ready && changed) {
                        applyRasterAppearance()
                        renderFrame()
                    }
                    result.success(null)
                }
                "registerAssets" -> {
                    (args["assets"] as? Map<*, *>)?.forEach { (key, value) ->
                        if (key is String && value is ByteArray) {
                            BitmapFactory.decodeByteArray(value, 0, value.size)?.let { assets[key] = it }
                        }
                    }
                    if (ready) renderFrame()
                    result.success(null)
                }
                "renderFrame" -> {
                    frame = args
                    if (ready) renderFrame()
                    result.success(null)
                }
                "setGestures" -> {
                    map?.uiSettings?.apply {
                        isRotateGesturesEnabled = args["rotateEnabled"] != false
                        isZoomGesturesEnabled = args["zoomEnabled"] != false
                        isScrollGesturesEnabled = args["panEnabled"] != false
                        isTiltGesturesEnabled = false
                    }
                    result.success(null)
                }
                "readViewport" -> result.success(viewport())
                "focusOn", "flyToCity" -> {
                    lastCamera = args
                    if (ready) moveCamera(args)
                    result.success(null)
                }
                "applyStage" -> {
                    if (ready) applyStage(args)
                    result.success(null)
                }
                "setRouteGeometry" -> {
                    val revision = (args["revision"] as? Number)?.toLong() ?: routeRevision + 1
                    if (revision < routeRevision) {
                        result.success(false)
                    } else {
                        val geometry = parseRoute(args["legs"])
                        if (geometry == null) {
                            result.success(false)
                        } else {
                            routeRevision = revision
                            route = geometry
                            if (ready) {
                                renderRoute()
                                fitRoute()
                            }
                            result.success(true)
                        }
                    }
                }
                "clearRoute" -> {
                    routeRevision++
                    route = null
                    if (ready) renderRoute()
                    result.success(null)
                }
                "drawRoute" -> result.success(false) // Road planning is owned by the Dart/backend planner.
                "dispose" -> { dispose(); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("tianditu_map", error.message, null)
            sendError("native", error.message ?: "Map operation failed")
        }
    }

    private fun loadStyle() {
        val current = map ?: return
        if (BuildConfig.TDT_KEY.isBlank()) {
            ready = false
            sendError("configuration", "TDT_KEY is missing")
            return
        }
        ready = false
        val revision = ++styleRevision
        val base = if (styleId == "satellite") "img" else "vec"
        val labels = if (styleId == "satellite") "cia" else "cva"
        current.setStyle(Style.Builder().fromJson(styleJson(base, labels))) { style ->
            if (!alive || revision != styleRevision) return@setStyle
            try {
                installBusinessLayers(style)
                applyRasterAppearance()
                ready = true
                lastCamera?.let(::moveCamera)
                renderFrame()
                renderRoute()
                updateAttribution()
                if (!sentReady) {
                    sentReady = true
                    send("onMapReady", null)
                } else {
                    send("onStyleLoaded", mapOf("styleId" to styleId, "revision" to requestedStyleRevision))
                }
            } catch (error: Exception) {
                ready = false
                sendError("style", error.message ?: "Could not create business layers")
            }
        }
    }

    private fun styleJson(base: String, labels: String): String {
        val root = JSONObject().put("version", 8).put("name", "Sipon Tianditu")
        val sources = JSONObject()
        val layers = JSONArray()
        layers.put(JSONObject().put("id", "map-background").put("type", "background")
            .put("paint", JSONObject().put("background-color", "#F8F5F8")))
        for ((id, layer) in listOf("base" to base, "labels" to labels)) {
            val source = JSONObject()
                .put("type", "raster")
                .put("tiles", JSONArray().put(tileUrl(layer)))
                .put("tileSize", 256)
                .put("minzoom", 1)
                .put("maxzoom", 18)
                .put("attribution", "© 天地图")
            sources.put(id, source)
            // WMTS annotations are already baked into images; individual names
            // cannot participate in symbol collision. Reduce their low-zoom density.
            layers.put(JSONObject().put("id", id).put("type", "raster").put("source", id)
                .put("minzoom", if (id == "labels") 12 else 0))
        }
        return root.put("sources", sources).put("layers", layers).toString()
    }

    private fun tileUrl(layer: String): String {
        val key = URLEncoder.encode(BuildConfig.TDT_KEY, "UTF-8")
        val url = "https://t0.tianditu.gov.cn/${layer}_w/wmts?SERVICE=WMTS&REQUEST=GetTile" +
            "&VERSION=1.0.0&LAYER=$layer&STYLE=default&TILEMATRIXSET=w&FORMAT=tiles" +
            "&TILEMATRIX={z}&TILEROW={y}&TILECOL={x}&tk=$key"
        // 天地图控制台为应用绑定“安全密钥”后，服务端要求额外携带 sk，否则返回 403/301020。
        val secret = BuildConfig.TDT_SK.trim()
        return if (secret.isEmpty()) url else "$url&sk=${URLEncoder.encode(secret, "UTF-8")}"
    }

    private fun applyRasterAppearance() {
        val style = map?.style ?: return
        val base = style.getLayer("base") as? RasterLayer ?: return
        val labels = style.getLayer("labels") as? RasterLayer ?: return
        if (useDarkPalette) {
            // WMTS base and annotations are separate raster layers. Grade each
            // layer in MapLibre so transparent annotation pixels stay transparent.
            val satellite = styleId == "satellite"
            style.getLayer("map-background")?.setProperties(backgroundColor(Color.rgb(38, 32, 43)))
            base.setProperties(
                rasterBrightnessMin(0f),
                rasterBrightnessMax(if (satellite) 0.48f else 0.38f),
                rasterSaturation(if (satellite) -0.28f else -0.72f),
                rasterContrast(if (satellite) 0.08f else 0.16f),
                rasterOpacity(if (satellite) 0.95f else 0.82f),
            )
            labels.setProperties(
                rasterBrightnessMin(0.78f),
                rasterBrightnessMax(1f),
                rasterSaturation(-0.65f),
                rasterContrast(0.10f),
                rasterOpacity(0.86f),
            )
        } else {
            style.getLayer("map-background")?.setProperties(backgroundColor(Color.rgb(248, 245, 248)))
            val satellite = styleId == "satellite"
            base.setProperties(
                rasterBrightnessMin(0f), rasterBrightnessMax(1f),
                rasterSaturation(if (satellite) 0f else -0.55f),
                rasterContrast(if (satellite) 0f else -0.06f),
                rasterOpacity(if (satellite) 1f else 0.82f),
            )
            labels.setProperties(
                rasterBrightnessMin(0f), rasterBrightnessMax(1f),
                rasterSaturation(if (satellite) 0f else -0.40f),
                rasterContrast(0f),
                rasterOpacity(if (satellite) 1f else 0.82f),
            )
        }
    }

    private fun installBusinessLayers(style: Style) {
        for (name in listOf("circles", "selected", "markers", "route")) {
            style.addSource(if (name == "circles") {
                GeoJsonSource("sipon-$name", emptyCollection(), GeoJsonOptions()
                    .withCluster(true).withClusterRadius(56).withClusterMaxZoom(19))
            } else GeoJsonSource("sipon-$name", emptyCollection()))
        }
        style.addLayer(LineLayer("sipon-route-line", "sipon-route").withProperties(
            lineColor(Color.rgb(247, 82, 78)), lineWidth(5f), lineOpacity(0.88f),
        ))
        style.addLayer(CircleLayer("sipon-clusters", "sipon-circles").withProperties(
            circleColor(Color.rgb(227, 74, 67)), circleRadius(16f),
            circleStrokeColor(Color.WHITE), circleStrokeWidth(2f),
        ).apply { setFilter(Expression.has("point_count")) })
        style.addLayer(SymbolLayer("sipon-cluster-count", "sipon-circles").withProperties(
            textField("{point_count_abbreviated}"), textSize(12f), textColor(Color.WHITE),
            textAllowOverlap(true), textIgnorePlacement(true),
        ).apply { setFilter(Expression.has("point_count")) })
        style.addLayer(CircleLayer("sipon-circles", "sipon-circles").withProperties(
            circleColor(Color.rgb(231, 74, 74)), circleRadius(7f),
            circleStrokeColor(Color.WHITE), circleStrokeWidth(2f),
        ).apply { setFilter(Expression.not(Expression.has("point_count"))) })
        style.addLayer(CircleLayer("sipon-selected", "sipon-selected").withProperties(
            circleColor(Color.argb(90, 242, 74, 71)), circleRadius(18f),
            circleStrokeColor(Color.rgb(238, 68, 65)), circleStrokeWidth(3f),
        ))
        // Ordinary capsules use symbol collision; the selected capsule is on a
        // separate layer so it remains visible even in a crowded viewport.
        style.addLayer(SymbolLayer("sipon-labels", "sipon-markers").withProperties(
            iconImage("{image}"),
            iconAllowOverlap(false),
            iconIgnorePlacement(false),
            iconPadding(4f),
            symbolSortKey(Expression.get("sortKey")),
        ).apply { setFilter(Expression.not(Expression.get("selected"))) })
        style.addLayer(SymbolLayer("sipon-selected-label", "sipon-markers").withProperties(
            iconImage("{image}"), iconAllowOverlap(true), iconIgnorePlacement(true),
        ).apply { setFilter(Expression.get("selected")) })
    }

    private fun renderFrame() {
        val style = map?.style ?: return
        val current = frame ?: return
        val markers = current["markers"] as? List<*> ?: emptyList<Any>()
        val selectedVenueId = (current["selected"] as? Map<*, *>)?.get("venueId") as? String
        val circles = mutableListOf<JSONObject>()
        (current["circles"] as? List<*>)?.forEach { raw ->
            val item = raw as? Map<*, *> ?: return@forEach
            feature(item)?.let(circles::add)
        }
        circleCandidates = circles
        val selected = JSONArray()
        (current["selected"] as? Map<*, *>)?.let { feature(it)?.let(selected::put) }
        source(style, "selected")?.setGeoJson(collection(selected))

        val candidates = mutableListOf<MarkerCandidate>()
        markers.forEachIndexed { index, raw ->
            val item = raw as? Map<*, *> ?: return@forEachIndexed
            val data = feature(item) ?: return@forEachIndexed
            val imageId = "marker-$index"
            val bitmap = makeMarkerBitmap(item)
            style.addImage(imageId, bitmap)
            markerImages.add(imageId)
            val properties = data.getJSONObject("properties")
            properties.put("image", imageId)
            properties.put("selected", selectedVenueId != null && item["venueId"] == selectedVenueId)
            properties.put(
                "sortKey",
                when {
                    selectedVenueId != null && item["venueId"] == selectedVenueId -> -2.0
                    item["sequence"] != null -> -1.0
                    else -> 0.0
                },
            )
            val coordinates = data.getJSONObject("geometry").getJSONArray("coordinates")
            candidates.add(MarkerCandidate(
                data, LatLng(coordinates.getDouble(1), coordinates.getDouble(0)),
                bitmap.width, bitmap.height, properties.getBoolean("selected"),
            ))
        }
        markerCandidates = candidates
        updateMarkerVisibility()
    }

    private fun updateMarkerVisibility() {
        val current = map ?: return
        val style = current.style ?: return
        val source = source(style, "markers") ?: return
        val width = mapView.width
        val height = mapView.height
        if (width <= 0 || height <= 0) return

        // Collision alone can still fill every gap with a capsule. Reserve
        // space for the page controls and sheet, then keep a small, spread-out
        // set of labels. The underlying circles/clusters remain interactive.
        val fullMap = height / density >= 500f
        val topInset = if (fullMap) 140f * density else 0f
        val bottomInset = if (fullMap)
            max(245f * density, (bottomPaddingDp * density).toFloat()) else 0f
        val usableHeight = (height - topInset - bottomInset).coerceAtLeast(1f)
        val maxLabels = ((((width / density) / 140f) *
            ((usableHeight / density) / 110f)) * 0.8f).toInt().coerceIn(3, 10)
        val occupied = mutableListOf<RectF>()
        val visible = JSONArray()
        val visibleVenueIds = mutableSetOf<String>()
        val ordered = markerCandidates.sortedByDescending { it.selected }
        for (candidate in ordered) {
            val pixel = current.projection.toScreenLocation(candidate.location)
            if (!candidate.selected && (pixel.x < 0 || pixel.x > width ||
                    pixel.y < topInset || pixel.y > height - bottomInset)) continue
            val halfWidth = candidate.width / 2f + 12f * density
            val halfHeight = candidate.height / 2f + 14f * density
            val bounds = RectF(pixel.x - halfWidth, pixel.y - halfHeight,
                pixel.x + halfWidth, pixel.y + halfHeight)
            if (!candidate.selected && (visible.length() >= maxLabels ||
                    occupied.any { RectF.intersects(it, bounds) })) continue
            visible.put(candidate.feature)
            candidate.feature.getJSONObject("properties").optString("venueId")
                .takeIf { it.isNotEmpty() }?.let(visibleVenueIds::add)
            occupied.add(bounds)
        }
        source.setGeoJson(collection(visible))
        val circles = JSONArray()
        for (circle in circleCandidates) {
            val venueId = circle.getJSONObject("properties").optString("venueId")
            if (venueId !in visibleVenueIds) circles.put(circle)
        }
        source(style, "circles")?.setGeoJson(collection(circles))
    }

    private fun makeMarkerBitmap(item: Map<*, *>): Bitmap {
        val label = ((item["sequence"] as? Number)?.toInt()?.toString() ?: item["label"] as? String ?: "").take(28)
        val rating = (item["rating"] as? Number)?.toDouble()?.takeIf { it.isFinite() }?.let { "  ★ %.1f".format(it) } ?: ""
        val message = "$label$rating"
        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = if (useDarkPalette) Color.WHITE else Color.rgb(42, 35, 33)
            textSize = 13f * density
            isFakeBoldText = true
        }
        val icon = assets[item["category"] as? String]
        val iconSize = 20f * density
        val width = max(48, (textPaint.measureText(message) + 28f * density + if (icon != null) iconSize else 0f).toInt())
        val height = (36f * density).toInt().coerceAtLeast(36)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val background = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = if (useDarkPalette) Color.rgb(48, 43, 42) else Color.WHITE }
        canvas.drawRoundRect(1f, 1f, width - 1f, height - 1f, height / 2f, height / 2f, background)
        val border = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(227, 74, 67); style = Paint.Style.STROKE; strokeWidth = density }
        canvas.drawRoundRect(1f, 1f, width - 1f, height - 1f, height / 2f, height / 2f, border)
        var x = 12f * density
        if (icon != null) {
            val top = (height - iconSize) / 2f
            canvas.drawBitmap(icon, null, RectF(x, top, x + iconSize, top + iconSize), Paint(Paint.ANTI_ALIAS_FLAG))
            x += iconSize + 5f * density
        }
        canvas.drawText(message, x, (height - (textPaint.ascent() + textPaint.descent())) / 2f, textPaint)
        return bitmap
    }

    private fun renderRoute() {
        val style = map?.style ?: return
        val features = JSONArray()
        route?.let { legs ->
            for (index in 0 until legs.length()) {
                features.put(JSONObject().put("type", "Feature")
                    .put("geometry", JSONObject().put("type", "LineString").put("coordinates", legs.getJSONArray(index)))
                    .put("properties", JSONObject()))
            }
        }
        source(style, "route")?.setGeoJson(collection(features))
    }

    private fun fitRoute() {
        val current = map ?: return
        val legs = route ?: return
        if (mapView.width <= 0 || mapView.height <= 0) {
            mapView.post { if (alive && ready) fitRoute() }
            return
        }
        val bounds = LatLngBounds.Builder()
        for (legIndex in 0 until legs.length()) {
            val leg = legs.getJSONArray(legIndex)
            for (pointIndex in 0 until leg.length()) {
                val pair = leg.getJSONArray(pointIndex)
                bounds.include(LatLng(pair.getDouble(1), pair.getDouble(0)))
            }
        }
        current.moveCamera(CameraUpdateFactory.newLatLngBounds(
            bounds.build(),
            (60 * density).toInt(), (90 * density).toInt(),
            (60 * density).toInt(), (max(140.0, bottomPaddingDp + 40.0) * density).toInt(),
        ))
    }

    private fun parseRoute(raw: Any?): JSONArray? {
        val legs = raw as? List<*> ?: return null
        if (legs.isEmpty()) return null
        val result = JSONArray()
        for (leg in legs) {
            val coordinates = (leg as? Map<*, *>)?.get("coordinates") as? List<*> ?: return null
            if (coordinates.size < 2) return null
            val output = JSONArray()
            for (rawPoint in coordinates) {
                val pair = rawPoint as? List<*> ?: return null
                if (pair.size < 2) return null
                val lng = (pair[0] as? Number)?.toDouble() ?: return null
                val lat = (pair[1] as? Number)?.toDouble() ?: return null
                if (!MapCoordinateAdapter.valid(lng, lat)) return null
                val display = MapCoordinateAdapter.toDisplay(Wgs84Point(lng, lat))
                output.put(JSONArray().put(display.lng).put(display.lat))
            }
            result.put(output)
        }
        return result
    }

    private fun feature(item: Map<*, *>): JSONObject? {
        val business = point(item) ?: return null
        val display = MapCoordinateAdapter.toDisplay(business)
        val props = JSONObject()
        for (key in listOf("id", "venueId", "category", "label", "rating", "sequence")) {
            val value = item[key]
            if (value != null) props.put(key, value)
        }
        return JSONObject().put("type", "Feature")
            .put("geometry", JSONObject().put("type", "Point")
                .put("coordinates", JSONArray().put(display.lng).put(display.lat)))
            .put("properties", props)
    }

    private fun point(args: Map<*, *>): Wgs84Point? {
        val lng = (args["lng"] as? Number)?.toDouble() ?: return null
        val lat = (args["lat"] as? Number)?.toDouble() ?: return null
        return if (MapCoordinateAdapter.valid(lng, lat)) Wgs84Point(lng, lat) else null
    }

    private fun moveCamera(args: Map<*, *>) {
        val current = map ?: return
        val target = point(args) ?: return
        bottomPaddingDp = (args["bottomPadding"] as? Number)?.toDouble()?.coerceAtLeast(0.0) ?: bottomPaddingDp
        updateAttribution()
        val display = MapCoordinateAdapter.toDisplay(target)
        val zoom = ((args["zoom"] as? Number)?.toDouble() ?: 15.0).coerceIn(1.0, 20.0)
        val camera = CameraPosition.Builder()
            .target(LatLng(display.lat, display.lng))
            .zoom(CameraZoomAdapter.toNative(zoom))
            .bearing((args["bearing"] as? Number)?.toDouble() ?: 0.0)
            .tilt(0.0)
            .padding(0.0, 0.0, 0.0, bottomPaddingDp * density)
            .build()
        current.moveCamera(CameraUpdateFactory.newCameraPosition(camera))
    }

    private fun applyStage(args: Map<*, *>) {
        bottomPaddingDp = (args["bottomPadding"] as? Number)?.toDouble()?.coerceAtLeast(0.0) ?: bottomPaddingDp
        updateAttribution()
        val focus = point(args)
        if (focus != null) {
            val current = map ?: return
            val display = MapCoordinateAdapter.toDisplay(focus)
            val camera = CameraPosition.Builder(current.cameraPosition)
                .target(LatLng(display.lat, display.lng))
                .padding(0.0, 0.0, 0.0, bottomPaddingDp * density)
                .build()
            current.moveCamera(CameraUpdateFactory.newCameraPosition(camera))
        } else {
            map?.moveCamera(CameraUpdateFactory.paddingTo(0.0, 0.0, 0.0, bottomPaddingDp * density))
        }
    }

    private fun updateAttribution() {
        map?.uiSettings?.setAttributionMargins(8, 0, 8, (bottomPaddingDp * density).toInt() + 8)
    }

    private fun viewport(): Map<String, Double>? {
        val current = map ?: return null
        val projection = current.projection
        val bounds = projection.visibleRegion.latLngBounds
        val center = projection.fromScreenLocation(PointF(mapView.width / 2f, mapView.height / 2f))
        val business = MapCoordinateAdapter.toBusiness(Cgcs2000Point(center.longitude, center.latitude))
        val sw = MapCoordinateAdapter.toBusiness(Cgcs2000Point(bounds.longitudeWest, bounds.latitudeSouth))
        val ne = MapCoordinateAdapter.toBusiness(Cgcs2000Point(bounds.longitudeEast, bounds.latitudeNorth))
        return mapOf(
            "west" to sw.lng, "south" to sw.lat, "east" to ne.lng, "north" to ne.lat,
            "zoom" to CameraZoomAdapter.toBusiness(current.cameraPosition.zoom),
            "centerLng" to business.lng, "centerLat" to business.lat,
        )
    }

    private fun send(event: String, arguments: Any?) {
        if (alive) channel.invokeMethod(event, arguments)
    }

    private fun sendError(code: String, message: String) =
        send("onMapError", mapOf("code" to code, "message" to message))

    fun onActivityStart() { if (alive) mapView.onStart() }
    fun onActivityResume() { if (alive) mapView.onResume() }
    fun onActivityPause() { if (alive) mapView.onPause() }
    fun onActivityStop() { if (alive) mapView.onStop() }
    fun onLowMemory() { if (alive) mapView.onLowMemory() }

    override fun dispose() {
        if (!alive) return
        alive = false
        ready = false
        styleRevision++
        map?.removeOnCameraIdleListener(cameraIdle)
        map?.removeOnMapClickListener(mapClick)
        channel.setMethodCallHandler(null)
        mapView.onPause()
        mapView.onStop()
        mapView.onDestroy()
        assets.values.forEach { if (!it.isRecycled) it.recycle() }
        assets.clear()
        onDisposed(this)
    }

    private fun source(style: Style, name: String) = style.getSourceAs<GeoJsonSource>("sipon-$name")
    private fun collection(features: JSONArray) = JSONObject().put("type", "FeatureCollection").put("features", features).toString()
    private fun emptyCollection() = collection(JSONArray())

    private fun cityCenter(city: String): Wgs84Point = when (city) {
        "北京" -> Wgs84Point(116.4074, 39.9042)
        "广州" -> Wgs84Point(113.2644, 23.1291)
        "深圳" -> Wgs84Point(114.0579, 22.5431)
        "杭州" -> Wgs84Point(120.1551, 30.2741)
        "成都" -> Wgs84Point(104.0665, 30.5723)
        else -> Wgs84Point(121.4712, 31.2227)
    }
}
