package com.example.sipon.map

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PointF
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.RectF
import android.os.Bundle
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import android.view.View
import android.widget.FrameLayout
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
import kotlin.math.ceil
import kotlin.math.max

private const val TIANDITU_ANNOTATION_MIN_ZOOM = 13
private const val TIANDITU_ANNOTATION_OPACITY = 0.88f
private const val TIANDITU_MAX_TILE_ZOOM = 18
private val POI_THEME_COLOR = Color.rgb(154, 61, 120)

/** One Flutter PlatformView owns one MapView, channel, style and business frame. */
internal class SiponTiandituView(
    context: Context,
    viewId: Int,
    messenger: BinaryMessenger,
    private val onDisposed: (SiponTiandituView) -> Unit,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val mapView: MapView
    private val container = FrameLayout(context)
    private val userLocation = SiponUserLocationView(context)
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
    private val drivingService = TiandituDrivingService()
    private val assets = mutableMapOf<String, Bitmap>()
    private val markerImages = mutableSetOf<String>()
    private data class MarkerCandidate(
        val feature: JSONObject,
        val location: LatLng,
        val width: Int,
        val height: Int,
        val selected: Boolean,
        val routeStop: Boolean,
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
            current.animateCamera(CameraUpdateFactory.newLatLngZoom(
                point,
                (current.cameraPosition.zoom + 1.5).coerceAtMost(CameraZoomAdapter.toNative(TIANDITU_MAX_TILE_ZOOM.toDouble())),
            ))
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
        container.addView(mapView, FrameLayout.LayoutParams(-1, -1))
        container.addView(userLocation, FrameLayout.LayoutParams(-1, -1))
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
            userLocation.pause()
            userLocation.map = loaded
            userLocation.resume()
            // The 256 px WMTS tiles use the business zoom scale (native zoom + 1).
            loaded.setMaxZoomPreference(CameraZoomAdapter.toNative(TIANDITU_MAX_TILE_ZOOM.toDouble()))
            loaded.addOnCameraIdleListener(cameraIdle)
            loaded.addOnMapClickListener(mapClick)
            loaded.uiSettings.isTiltGesturesEnabled = false
            loaded.uiSettings.isCompassEnabled = false
            loaded.uiSettings.isLogoEnabled = false
            loaded.uiSettings.isAttributionEnabled = false
            if (setupRequested) loadStyle()
        }
    }

    override fun getView(): View = container

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (!alive) {
            result.error("disposed", "Map view was disposed", null)
            return
        }
        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        // 定位授权可能在地图创建后才完成；后续地图指令会重试订阅。
        userLocation.refreshPermission()
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
                    userLocation.dark = useDarkPalette
                    userLocation.invalidate()
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
                "fitRouteStops" -> {
                    val rawPoints = args["points"] as? List<*>
                    val points = rawPoints?.mapNotNull { raw ->
                        (raw as? Map<*, *>)?.let(::point)
                    }
                    if (rawPoints == null || points == null || points.size != rawPoints.size) {
                        result.error("route_input", "Invalid route stops", null)
                    } else {
                        if (ready) fitRouteStops(points)
                        result.success(null)
                    }
                }
                "planRoadRoute" -> {
                    val rawPoints = args["points"] as? List<*>
                    val stops = rawPoints?.mapNotNull { raw ->
                        val point = raw as? Map<*, *> ?: return@mapNotNull null
                        val lng = (point["lng"] as? Number)?.toDouble()
                        val lat = (point["lat"] as? Number)?.toDouble()
                        if (lng == null || lat == null || !lng.isFinite() || !lat.isFinite() ||
                            lng !in -180.0..180.0 || lat !in -90.0..90.0
                        ) null else lng to lat
                    }
                    if (rawPoints == null || stops == null || stops.size != rawPoints.size || stops.size !in 2..12) {
                        result.error("route_input", "Invalid route stops", null)
                    } else {
                        drivingService.plan(stops) { legs, error ->
                            if (error != null) result.error("route_service", error, null)
                            else result.success(mapOf("crs" to "CGCS2000", "legs" to legs))
                        }
                    }
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
                    drivingService.cancel()
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
        userLocation.dark = useDarkPalette
        userLocation.invalidate()
        val current = map ?: return
        if (BuildConfig.TDT_KEY.isBlank()) {
            ready = false
            sendError("configuration", "TDT_KEY is missing")
            return
        }
        ready = false
        val revision = ++styleRevision
        val base = if (styleId == "satellite") "img" else "vec"
        val annotations = if (styleId == "satellite") "cia" else "cva"
        current.setStyle(Style.Builder().fromJson(styleJson(base, annotations))) { style ->
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

    private fun styleJson(base: String, annotations: String): String {
        val root = JSONObject().put("version", 8).put("name", "Sipon Tianditu")
        val sources = JSONObject()
        val layers = JSONArray()
        layers.put(JSONObject().put("id", "map-background").put("type", "background")
            .put("paint", JSONObject().put("background-color", "#F8F5F8")))
        sources.put("base", JSONObject()
            .put("type", "raster")
            .put("tiles", JSONArray().put(tileUrl(base)))
            .put("tileSize", 256)
            .put("minzoom", 1)
            .put("maxzoom", TIANDITU_MAX_TILE_ZOOM)
            .put("attribution", "© 天地图"))
        sources.put("annotations", JSONObject()
            .put("type", "raster")
            .put("tiles", JSONArray().put(tileUrl(annotations)))
            .put("tileSize", 256)
            .put("minzoom", 1)
            .put("maxzoom", TIANDITU_MAX_TILE_ZOOM)
            .put("attribution", "© 天地图"))
        layers.put(JSONObject().put("id", "base").put("type", "raster").put("source", "base")
            .put("minzoom", 0))
        layers.put(JSONObject().put("id", "annotations").put("type", "raster").put("source", "annotations")
            .put("minzoom", TIANDITU_ANNOTATION_MIN_ZOOM))
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
        val annotations = style.getLayer("annotations") as? RasterLayer ?: return
        annotations.setProperties(rasterOpacity(TIANDITU_ANNOTATION_OPACITY))
        if (useDarkPalette) {
            // Keep annotations independent so their visibility and opacity can be tuned.
            val satellite = styleId == "satellite"
            style.getLayer("map-background")?.setProperties(backgroundColor(Color.rgb(38, 32, 43)))
            base.setProperties(
                rasterBrightnessMin(0f),
                rasterBrightnessMax(if (satellite) 0.48f else 0.38f),
                rasterSaturation(if (satellite) -0.28f else -0.72f),
                rasterContrast(if (satellite) 0.08f else 0.16f),
                rasterOpacity(if (satellite) 0.95f else 0.82f),
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
            circleColor(POI_THEME_COLOR), circleRadius(13f),
            circleStrokeColor(Color.WHITE), circleStrokeWidth(1.5f),
        ).apply { setFilter(Expression.has("point_count")) })
        style.addLayer(SymbolLayer("sipon-cluster-count", "sipon-circles").withProperties(
            textField("{point_count_abbreviated}"), textSize(12f), textColor(Color.WHITE),
            textAllowOverlap(true), textIgnorePlacement(true),
        ).apply { setFilter(Expression.has("point_count")) })
        style.addLayer(CircleLayer("sipon-circles", "sipon-circles").withProperties(
            circleColor(POI_THEME_COLOR), circleRadius(3.5f),
            circleStrokeColor(Color.WHITE), circleStrokeWidth(1f),
        ).apply { setFilter(Expression.not(Expression.has("point_count"))) })
        style.addLayer(CircleLayer("sipon-selected", "sipon-selected").withProperties(
            circleColor(POI_THEME_COLOR), circleRadius(3.5f),
            circleStrokeColor(Color.WHITE), circleStrokeWidth(1f),
        ))
        // Ordinary capsules use symbol collision; the selected capsule is on a
        // separate layer so it remains visible even in a crowded viewport.
        style.addLayer(SymbolLayer("sipon-labels", "sipon-markers").withProperties(
            iconImage("{image}"),
            iconAllowOverlap(false),
            iconIgnorePlacement(false),
            iconPadding(4f),
            symbolSortKey(Expression.get("sortKey")),
        ).apply { setFilter(Expression.all(
            Expression.not(Expression.get("selected")),
            Expression.not(Expression.has("sequence")),
        )) })
        style.addLayer(SymbolLayer("sipon-route-stops", "sipon-markers").withProperties(
            iconImage("{image}"), iconAllowOverlap(true), iconIgnorePlacement(true),
        ).apply { setFilter(Expression.has("sequence")) })
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
            val isSelected = selectedVenueId != null && item["venueId"] == selectedVenueId
            val bitmap = makeMarkerBitmap(item, isSelected)
            style.addImage(imageId, bitmap)
            markerImages.add(imageId)
            val properties = data.getJSONObject("properties")
            properties.put("image", imageId)
            properties.put("selected", isSelected)
            properties.put(
                "sortKey",
                when {
                    isSelected -> -2.0
                    item["sequence"] != null -> -1.0
                    else -> 0.0
                },
            )
            val coordinates = data.getJSONObject("geometry").getJSONArray("coordinates")
            candidates.add(MarkerCandidate(
                data, LatLng(coordinates.getDouble(1), coordinates.getDouble(0)),
                bitmap.width, bitmap.height, properties.getBoolean("selected"), item["sequence"] != null,
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
            if (!candidate.selected && !candidate.routeStop && (pixel.x < 0 || pixel.x > width ||
                    pixel.y < topInset || pixel.y > height - bottomInset)) continue
            val halfWidth = candidate.width / 2f + 12f * density
            val halfHeight = candidate.height / 2f + 14f * density
            val bounds = RectF(pixel.x - halfWidth, pixel.y - halfHeight,
                pixel.x + halfWidth, pixel.y + halfHeight)
            if (!candidate.selected && !candidate.routeStop && (visible.length() >= maxLabels ||
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

    private fun makeMarkerBitmap(item: Map<*, *>, isSelected: Boolean): Bitmap {
        val name = (item["sequence"] as? Number)?.toInt()?.toString() ?: item["label"] as? String ?: ""
        val rating = (item["rating"] as? Number)?.toDouble()?.takeIf { it.isFinite() }?.let { "★ %.1f".format(it) } ?: ""
        val namePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = if (useDarkPalette) Color.rgb(194, 182, 194) else Color.rgb(102, 108, 118)
            textSize = 45f * density
            setShadowLayer(2f * density, 0f, 0f, if (useDarkPalette) Color.BLACK else Color.WHITE)
        }
        val nameWidth = ceil(Layout.getDesiredWidth(name, namePaint).toDouble()).toInt()
            .coerceIn(1, (128f * density).toInt().coerceAtLeast(1))
        val nameLayout = StaticLayout.Builder.obtain(name, 0, name.length, namePaint, nameWidth)
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setIncludePad(false)
            .setMaxLines(2)
            .setEllipsize(TextUtils.TruncateAt.END)
            .build()
        val icon = assets[item["category"] as? String]
        val iconSize = 16f * density
        val ratingPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = if (isSelected || useDarkPalette) Color.WHITE else Color.rgb(42, 35, 33)
            textSize = 11f * density
            isFakeBoldText = true
        }
        val badgePadding = 7f * density
        val badgeGap = if (icon != null && rating.isNotEmpty()) 4f * density else 0f
        val badgeWidth = max(28f * density, badgePadding * 2 +
            (if (icon != null) iconSize else 0f) + badgeGap + ratingPaint.measureText(rating))
        val badgeHeight = 28f * density
        val nameGap = 5f * density
        val width = ceil((max(badgeWidth, nameWidth.toFloat()) + 4f * density).toDouble()).toInt()
        val height = ceil((badgeHeight + nameGap + nameLayout.height + 3f * density).toDouble()).toInt()
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val background = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = if (isSelected) POI_THEME_COLOR else if (useDarkPalette) Color.rgb(48, 43, 42) else Color.WHITE
        }
        val badgeLeft = (width - badgeWidth) / 2f
        canvas.drawRoundRect(badgeLeft + 1f, 1f, badgeLeft + badgeWidth - 1f, badgeHeight - 1f,
            badgeHeight / 2f, badgeHeight / 2f, background)
        val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = POI_THEME_COLOR
            style = Paint.Style.STROKE
            strokeWidth = density
        }
        canvas.drawRoundRect(badgeLeft + 1f, 1f, badgeLeft + badgeWidth - 1f, badgeHeight - 1f,
            badgeHeight / 2f, badgeHeight / 2f, border)
        var x = badgeLeft + badgePadding
        if (icon != null) {
            val top = (badgeHeight - iconSize) / 2f
            val iconPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                if (isSelected) colorFilter = PorterDuffColorFilter(Color.WHITE, PorterDuff.Mode.SRC_IN)
            }
            canvas.drawBitmap(icon, null, RectF(x, top, x + iconSize, top + iconSize), iconPaint)
            x += iconSize + badgeGap
        }
        if (rating.isNotEmpty()) {
            canvas.drawText(rating, x, (badgeHeight - ratingPaint.ascent() - ratingPaint.descent()) / 2f, ratingPaint)
        }
        canvas.save()
        canvas.translate((width - nameWidth) / 2f, badgeHeight + nameGap)
        nameLayout.draw(canvas)
        canvas.restore()
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

    private fun fitRouteStops(points: List<Wgs84Point>) {
        val current = map ?: return
        if (points.isEmpty()) return
        if (mapView.width <= 0 || mapView.height <= 0) {
            mapView.post { if (alive && ready) fitRouteStops(points) }
            return
        }
        val display = points.map(MapCoordinateAdapter::toDisplay)
        if (display.map { it.lng to it.lat }.toSet().size == 1) {
            val point = display.first()
            current.moveCamera(CameraUpdateFactory.newLatLngZoom(LatLng(point.lat, point.lng), 15.0))
            return
        }
        val bounds = LatLngBounds.Builder()
        display.forEach { bounds.include(LatLng(it.lat, it.lng)) }
        current.moveCamera(CameraUpdateFactory.newLatLngBounds(
            bounds.build(),
            (48 * density).toInt(), (60 * density).toInt(),
            (48 * density).toInt(), (60 * density).toInt(),
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
        val zoom = ((args["zoom"] as? Number)?.toDouble() ?: 15.0)
            .coerceIn(1.0, TIANDITU_MAX_TILE_ZOOM.toDouble())
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
    fun onActivityResume() { if (alive) { mapView.onResume(); userLocation.resume() } }
    fun onActivityPause() { if (alive) { userLocation.pause(); mapView.onPause() } }
    fun onActivityStop() { if (alive) mapView.onStop() }
    fun onLowMemory() { if (alive) mapView.onLowMemory() }

    override fun dispose() {
        if (!alive) return
        alive = false
        userLocation.pause()
        drivingService.dispose()
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
