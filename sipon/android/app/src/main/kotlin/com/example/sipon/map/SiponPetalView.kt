package com.example.sipon.map

import android.content.Context
import android.graphics.*
import android.os.Bundle
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import android.util.Log
import android.util.LruCache
import android.widget.FrameLayout
import android.view.View
import com.example.sipon.BuildConfig
import com.huawei.hms.maps.*
import com.huawei.hms.maps.model.*
import io.flutter.plugin.common.*
import io.flutter.plugin.platform.PlatformView
import kotlin.math.ceil
import kotlin.math.max

private val POI_THEME_COLOR = Color.rgb(154, 61, 120)
private const val LIGHT_MAP_STYLE_ID = "2061929205284932992"
private const val DARK_MAP_STYLE_ID = "2061970525261063552"

/** One native Map Kit view per Flutter channel. Shared geometry stays GCJ-02. */
internal class SiponPetalView(
    context: Context,
    viewId: Int,
    messenger: BinaryMessenger,
    private val creationParams: Map<*, *>,
    private val onDisposed: (SiponPetalView) -> Unit,
) : PlatformView, MethodChannel.MethodCallHandler {
    private val container = FrameLayout(context)
    private val density = context.resources.displayMetrics.density
    private val channel = MethodChannel(messenger, "sipon/petal_$viewId")
    private val userLocation = SiponUserLocationView(context)
    private val routeArrows = PetalRouteArrowView(context)
    private var mapView: MapView? = null
    private var map: HuaweiMap? = null
    private var alive = true
    private var ready = false
    private var styleId = "standard"
    private var dark = creationParams["brightness"] == "dark"
    private val useDarkPalette get() = dark || styleId == "muted"
    private val customMapStyleId get() = if (useDarkPalette) DARK_MAP_STYLE_ID else LIGHT_MAP_STYLE_ID
    private var bottomPadding = 0
    private var frame: Map<*, *>? = null
    private var routeRevision = -1L
    private val assets = mutableMapOf<String, Bitmap>()
    private data class Poi(
        val id: String, val location: LatLng, val item: Map<*, *>,
        val hasLabel: Boolean, val selected: Boolean = false, val routeStop: Boolean = false,
    )
    private data class IconKey(
        val category: String?, val label: String, val rating: Double?, val sequence: Int?,
        val selected: Boolean, val dark: Boolean, val assetsRevision: Int,
    )
    private data class Artwork(val descriptor: BitmapDescriptor, val width: Int, val height: Int, val bytes: Int)
    private data class MarkerLayout(
        val name: StaticLayout, val rating: String, val ratingPaint: Paint, val icon: Bitmap?,
        val badgeWidth: Float, val badgeGap: Float, val width: Int, val height: Int,
    )
    private data class RenderedPoi(val marker: Marker, var location: LatLng, var icon: IconKey?)
    private val markers = mutableMapOf<String, RenderedPoi>()
    private var pois = emptyList<Poi>()
    private var assetsRevision = 0
    private var cameraMoving = false
    private val iconCache = object : LruCache<IconKey, Artwork>(4 * 1024 * 1024) {
        override fun sizeOf(key: IconKey, value: Artwork) = value.bytes
    }
    private val markerLayoutCache = LruCache<IconKey, MarkerLayout>(128)
    private var dotIcon: BitmapDescriptor? = null
    private val renderPois = Runnable { if (alive && ready && !cameraMoving) updatePoiLayout() }
    private val routes = mutableListOf<Polyline>()
    private val drivingService = PetalDrivingService()
    private var pendingSetup: Map<*, *>? = null

    init {
        container.addView(routeArrows, FrameLayout.LayoutParams(-1, -1))
        container.addView(userLocation, FrameLayout.LayoutParams(-1, -1))
        channel.setMethodCallHandler(this)
        container.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
            schedulePoiLayout()
        }
    }

    override fun getView(): View = container

    private fun setup(args: Map<*, *>) {
        pendingSetup = args
        styleId = args["styleId"] as? String ?: "standard"
        if (BuildConfig.PETAL_MAP_KEY.isBlank()) {
            send("onMapError", mapOf("code" to "configuration", "message" to "请配置花瓣地图 API Key（PETAL_MAP_KEY）"))
            return
        }
        if (mapView != null) { if (ready) configureMap(); return }
        MapsInitializer.setApiKey(BuildConfig.PETAL_MAP_KEY)
        if (BuildConfig.PETAL_APP_ID.isNotBlank()) MapsInitializer.setAppId(BuildConfig.PETAL_APP_ID)
        MapsInitializer.initialize(container.context.applicationContext)
        // SurfaceView bypasses Flutter's texture composition and can cover its
        // search controls and bottom sheets. Keep the map in the texture layer.
        val view = TextureMapView(container.context, HuaweiMapOptions()
            .zoomControlsEnabled(false).tiltGesturesEnabled(false)
            .dark(false).styleId(customMapStyleId))
        mapView = view
        container.addView(view, 0, FrameLayout.LayoutParams(-1, -1))
        view.onCreate(Bundle())
        view.onStart()
        view.onResume()
        view.getMapAsync { loaded ->
            if (!alive) return@getMapAsync
            map = loaded
            loaded.setGcj02CoordinateEnabled(true)
            loaded.setMarkersClustering(false)
            loaded.uiSettings.apply {
                isZoomControlsEnabled = false
                isMyLocationButtonEnabled = false
                isMapToolbarEnabled = false
                isTiltGesturesEnabled = false
                isCompassEnabled = creationParams["compassTopInset"] is Number
            }
            routeArrows.map = loaded
            loaded.setOnCameraMoveStartedListener { cameraMoving = true }
            loaded.setOnCameraMoveListener { routeArrows.invalidate() }
            loaded.setOnCameraIdleListener {
                if (alive && ready) {
                    cameraMoving = false
                    routeArrows.invalidate()
                    schedulePoiLayout(0)
                    send("onViewportSettled", viewport())
                }
            }
            loaded.setOnMarkerClickListener { marker ->
                val venue = marker.tag as? String
                if (!venue.isNullOrBlank()) {
                    send("onVenueTapped", mapOf("venueId" to venue))
                    true
                } else false
            }
            loaded.setOnMapClickListener { send("onBlankTapped", null) }
            userLocation.pause()
            userLocation.map = loaded
            userLocation.resume()
            ready = true
            configureMap()
            send("onMapReady", null)
        }
    }

    private fun configureMap() {
        applyAppearance()
        val args = pendingSetup ?: return
        val start = point(args) ?: cityCenter(args["city"] as? String ?: "")
        val zoom = (args["zoom"] as? Number)?.toFloat() ?: if (point(args) == null) 11.8f else 15f
        map?.moveCamera(CameraUpdateFactory.newLatLngZoom(start, zoom))
        renderFrame()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (!alive) { result.error("disposed", "Map view was disposed", null); return }
        val args = call.arguments as? Map<*, *> ?: emptyMap<Any, Any>()
        userLocation.refreshPermission()
        try {
            when (call.method) {
                "setup" -> { setup(args); result.success(null) }
                "setAppearance" -> {
                    dark = args["brightness"] == "dark"
                    applyAppearance(); renderFrame(); result.success(null)
                }
                "setStyle" -> {
                    styleId = args["styleId"] as? String ?: "standard"
                    applyAppearance(); renderFrame()
                    send("onStyleLoaded", mapOf("revision" to args["revision"]))
                    result.success(null)
                }
                "registerAssets" -> {
                    (args["assets"] as? Map<*, *>)?.forEach { (key, value) ->
                        if (key is String && value is ByteArray) BitmapFactory.decodeByteArray(value, 0, value.size)?.let { assets[key] = it }
                    }
                    assetsRevision++
                    iconCache.evictAll()
                    markerLayoutCache.evictAll()
                    renderFrame(); result.success(null)
                }
                "renderFrame" -> { frame = args; renderFrame(); result.success(null) }
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
                "focusOn", "flyToCity" -> { moveCamera(args); result.success(null) }
                "centerOnUser" -> {
                    val target = userLocation.businessPosition?.let { LatLng(it.lat, it.lng) } ?: point(args)
                    moveCamera(args, target); result.success(null)
                }
                "applyStage" -> {
                    val current = map
                    setPadding(args)
                    point(args)?.let { current?.moveCamera(CameraUpdateFactory.newLatLng(it)) }
                    schedulePoiLayout()
                    result.success(null)
                }
                "fitRouteStops" -> { fitPoints(parseStops(args)); result.success(null) }
                "planRoadRoute" -> {
                    val stops = parseStops(args)
                    require(stops.size in 2..12) { "Invalid route stops" }
                    // Directions API uses WGS-84; Map Kit itself is configured for GCJ-02.
                    drivingService.plan(stops.map {
                        MapCoordinateAdapter.toDisplay(Gcj02Point(it.longitude, it.latitude)).let { p -> p.lng to p.lat }
                    }) { legs, error ->
                        if (error != null) result.error("route_service", error, null)
                        else result.success(mapOf("crs" to MapCoordinateAdapter.businessCrs, "legs" to legs))
                    }
                }
                "setRouteGeometry" -> {
                    val revision = (args["revision"] as? Number)?.toLong() ?: routeRevision + 1
                    if (revision < routeRevision) result.success(false)
                    else {
                        val legs = args["legs"] as? List<*> ?: error("Invalid route geometry")
                        val geometry = legs.map { raw ->
                            val coordinates = (raw as? Map<*, *>)?.get("coordinates") as? List<*> ?: error("Invalid route leg")
                            coordinates.map { coordinate ->
                                val pair = coordinate as? List<*> ?: error("Invalid coordinate")
                                require(pair.size == 2)
                                point(mapOf("lng" to pair[0], "lat" to pair[1])) ?: error("Invalid coordinate")
                            }.also { require(it.size >= 2) }
                        }.also { require(it.isNotEmpty()) }
                        routeRevision = revision
                        routes.forEach { it.remove() }; routes.clear()
                        // Huawei's compatibility API renders at three times the supplied pixel width.
                        geometry.forEach { points -> map?.addPolyline(PolylineOptions().addAll(points).color(POI_THEME_COLOR)
                            .width(5f * density / 3f).startCap(RoundCap()).endCap(RoundCap())
                            .jointType(JointType.ROUND).zIndex(1f))?.let(routes::add) }
                        routeArrows.legs = geometry
                        fitPoints(geometry.flatten()); result.success(true)
                    }
                }
                "clearRoute" -> {
                    drivingService.cancel(); routeRevision++
                    routes.forEach { it.remove() }; routes.clear()
                    routeArrows.legs = emptyList(); result.success(null)
                }
                "dispose" -> { dispose(); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            result.error("petal_map", error.message, null)
            if (call.method == "setup") send("onMapError", mapOf("code" to "native", "message" to "花瓣地图初始化失败，请检查应用配置"))
        }
    }

    private fun applyAppearance() {
        map?.apply {
            mapType = if (styleId == "satellite") HuaweiMap.MAP_TYPE_HYBRID else HuaweiMap.MAP_TYPE_NORMAL
            // Use the selected cloud palette, never the SDK's built-in night palette.
            setDark(false)
            // The published styles own the palette and base-map POI visibility.
            // Applying a local JSON style here would override the cloud style.
            setStyleId(customMapStyleId)
            if (BuildConfig.DEBUG) Log.d("SiponMapAppearance",
                "styleId=$customMapStyleId, darkPalette=$useDarkPalette, sdkDark=$isDark")
            if (BuildConfig.DEBUG) container.postDelayed({
                runCatching {
                    val managerClass = Class.forName("com.huawei.hms.maps.provider.util.baf")
                    val manager = managerClass.getMethod("d").invoke(null)
                    val cache = managerClass.getField("a").get(manager)
                    val content = cache.javaClass.getField("c").get(cache) as? String
                    if (content != null) java.io.File(container.context.filesDir,
                        "petal-style-diagnostic.json").writeText(content)
                    Log.d("SiponMapAppearance", "downloadedStyleBytes=${content?.length}")
                }.onFailure { Log.d("SiponMapAppearance", "Style diagnostic unavailable", it) }
            }, 5000)
        }
        userLocation.dark = useDarkPalette
        userLocation.invalidate()
    }

    private fun point(args: Map<*, *>): LatLng? {
        val lng = (args["lng"] as? Number)?.toDouble() ?: return null
        val lat = (args["lat"] as? Number)?.toDouble() ?: return null
        return if (MapCoordinateAdapter.valid(lng, lat)) LatLng(lat, lng) else null
    }

    private fun parseStops(args: Map<*, *>): List<LatLng> =
        (args["points"] as? List<*> ?: error("Invalid route stops")).map {
            point(it as? Map<*, *> ?: error("Invalid route stop")) ?: error("Invalid route stop")
        }

    private fun setPadding(args: Map<*, *>) {
        bottomPadding = (((args["bottomPadding"] as? Number)?.toDouble() ?: 0.0) * density)
            .toInt().coerceIn(0, (container.height - 1).coerceAtLeast(0))
        map?.setPadding(0, 0, 0, bottomPadding)
    }

    private fun moveCamera(args: Map<*, *>, target: LatLng? = point(args)) {
        val current = map ?: return
        target ?: return
        setPadding(args)
        val zoom = (args["zoom"] as? Number)?.toFloat() ?: current.cameraPosition.zoom
        val bearing = (args["bearing"] as? Number)?.toFloat() ?: current.cameraPosition.bearing
        val update = CameraUpdateFactory.newCameraPosition(CameraPosition(target, zoom.coerceIn(current.minZoomLevel, current.maxZoomLevel), 0f, bearing))
        current.animateCamera(update)
    }

    private fun fitPoints(points: List<LatLng>) {
        val current = map ?: return
        if (points.isEmpty() || container.width == 0 || container.height <= bottomPadding) return
        if (points.distinct().size == 1) current.animateCamera(CameraUpdateFactory.newLatLngZoom(points.first(), 16f))
        else {
            val bounds = LatLngBounds.builder().also { builder -> points.forEach { builder.include(it) } }.build()
            val margin = (32 * density).toInt().coerceAtMost(minOf(container.width, container.height - bottomPadding) / 4)
            current.animateCamera(CameraUpdateFactory.newLatLngBounds(bounds, margin))
        }
    }

    private fun viewport(): Map<String, Double>? {
        val current = map ?: return null
        if (!ready || container.width == 0 || container.height == 0) return null
        val bounds = current.projection.visibleRegion.latLngBounds
        val center = current.projection.fromScreenLocation(Point(container.width / 2, container.height / 2))
        return mapOf("west" to bounds.southwest.longitude, "south" to bounds.southwest.latitude,
            "east" to bounds.northeast.longitude, "north" to bounds.northeast.latitude,
            "zoom" to current.cameraPosition.zoom.toDouble(), "centerLng" to center.longitude, "centerLat" to center.latitude)
    }

    private fun renderFrame() {
        val data = frame ?: return
        val selected = data["selected"] as? Map<*, *>
        val selectedId = selected?.get("venueId")
        val specs = (data["markers"] as? List<*>)?.filterIsInstance<Map<*, *>>() ?: emptyList()
        fun key(item: Map<*, *>, location: LatLng): String =
            (item["venueId"] as? String)?.takeIf { it.isNotBlank() }?.let { "venue:$it" }
                ?: "point:${item["id"] ?: location.toString()}"
        val entries = linkedMapOf<String, Poi>()
        val coordinateKeys = mutableMapOf<LatLng, String>()
        specs.forEach { item ->
            val location = point(item) ?: return@forEach
            val id = key(item, location)
            val isSelected = selectedId != null && item["venueId"] == selectedId
            entries[id] = Poi(id, location, item, true, isSelected, item["sequence"] != null)
            coordinateKeys[location] = id
        }
        (data["circles"] as? List<*>)?.filterIsInstance<Map<*, *>>()?.forEach { item ->
            val location = point(item) ?: return@forEach
            val id = coordinateKeys[location] ?: key(item, location)
            if (!entries.containsKey(id)) entries[id] = Poi(id, location, item, false)
            coordinateKeys[location] = id
        }
        if (selected != null) {
            point(selected)?.let { location ->
                val id = if (selectedId != null) key(selected, location) else coordinateKeys[location] ?: key(selected, location)
                val existing = entries[id]
                entries[id] = existing?.copy(location = location, selected = true)
                    ?: Poi(id, location, selected, true, selected = true)
            }
        }
        pois = entries.values.toList()
        schedulePoiLayout()
    }

    private fun schedulePoiLayout(delay: Long = 60) {
        if (!alive || !ready) return
        container.removeCallbacks(renderPois)
        container.postDelayed(renderPois, delay)
    }

    private fun iconKey(poi: Poi) = IconKey(poi.item["category"] as? String,
        poi.item["label"] as? String ?: "", (poi.item["rating"] as? Number)?.toDouble()?.takeIf { it.isFinite() },
        (poi.item["sequence"] as? Number)?.toInt(), poi.selected, useDarkPalette, assetsRevision)

    private fun artwork(key: IconKey): Artwork = iconCache.get(key) ?: run {
        val bitmap = makeMarkerBitmap(key, markerLayout(key))
        Artwork(BitmapDescriptorFactory.fromBitmap(bitmap), bitmap.width, bitmap.height, bitmap.byteCount)
            .also { iconCache.put(key, it) }
    }

    private fun dotArtwork(): BitmapDescriptor = dotIcon ?: run {
        val size = (12 * density).toInt().coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        Canvas(bitmap).drawCircle(size / 2f, size / 2f, 3.5f * density,
            Paint(Paint.ANTI_ALIAS_FLAG).apply { color = POI_THEME_COLOR })
        BitmapDescriptorFactory.fromBitmap(bitmap).also { dotIcon = it }
    }

    private fun updatePoiLayout() {
        val current = map ?: return
        if (container.width <= 0 || container.height <= 0) return
        val started = android.os.SystemClock.elapsedRealtime()
        val width = container.width / density.toDouble()
        val height = container.height / density.toDouble()
        val projection = current.projection
        val bounds = projection.visibleRegion.latLngBounds
        val lookup = pois.associateBy { it.id }
        val shortlist = PetalPoiLayout.shortlist(pois.map {
            PetalPoiLayout.GeoPoint(it.id, it.location.longitude, it.location.latitude,
                it.hasLabel, it.selected, it.routeStop)
        }, bounds.southwest.longitude, bounds.southwest.latitude,
            bounds.northeast.longitude, bounds.northeast.latitude, width, height)
        val candidates = shortlist.map { entry ->
            val poi = lookup.getValue(entry.id)
            val pixel = projection.toScreenLocation(poi.location)
            // Measure text without creating a bitmap or SDK marker. Short names
            // can share the screen instead of all reserving a 132 dp wide box.
            val label = if (poi.hasLabel || poi.selected || poi.routeStop) markerLayout(iconKey(poi)) else null
            PetalPoiLayout.Candidate(poi.id, pixel.x / density.toDouble(), pixel.y / density.toDouble(),
                poi.hasLabel, poi.selected, poi.routeStop,
                labelWidth = label?.let { it.width / density.toDouble() } ?: 0.0,
                labelHeight = label?.let { it.height / density.toDouble() } ?: 0.0)
        }
        val fullScreen = creationParams["showsUserHeading"] == true
        val placements = PetalPoiLayout.select(candidates, width, height, current.cameraPosition.zoom.toDouble(),
            if (fullScreen) (creationParams["compassTopInset"] as? Number)?.toDouble() ?: 140.0 else 0.0,
            if (fullScreen) max(220.0, bottomPadding / density.toDouble()) else bottomPadding / density.toDouble())
        val ids = placements.mapTo(hashSetOf()) { it.id }
        val removed = markers.keys.filter { it !in ids }
        removed.forEach { markers.remove(it)?.marker?.remove() }
        var created = 0
        var updated = 0
        for (placement in placements) {
            val poi = lookup.getValue(placement.id)
            val iconKey = if (placement.label) iconKey(poi) else null
            val existing = markers[poi.id]
            if (existing != null && existing.icon == iconKey && existing.location == poi.location) continue
            val image = iconKey?.let { artwork(it) }
            val descriptor = image?.descriptor ?: dotArtwork()
            val anchorV = if (image != null) 14f * density / image.height else 0.5f
            val zIndex = if (poi.selected) 5f else if (placement.label) 3f else 2f
            if (existing == null) {
                current.addMarker(MarkerOptions().position(poi.location).anchor(0.5f, anchorV)
                    .icon(descriptor).clusterable(false).zIndex(zIndex))?.let {
                    it.tag = poi.item["venueId"] as? String
                    markers[poi.id] = RenderedPoi(it, poi.location, iconKey)
                    created++
                }
            } else {
                if (existing.location != poi.location) existing.marker.position = poi.location
                if (existing.icon != iconKey) {
                    existing.marker.setIcon(descriptor)
                    existing.marker.setAnchor(0.5f, anchorV)
                    existing.marker.zIndex = zIndex
                }
                existing.location = poi.location
                existing.icon = iconKey
                updated++
            }
        }
        if (BuildConfig.DEBUG) Log.d("SiponPetalPoi", "input=${pois.size} projected=${shortlist.size} " +
            "labels=${placements.count { it.label }} dots=${placements.count { !it.label }} " +
            "created=$created updated=$updated removed=${removed.size} ms=${android.os.SystemClock.elapsedRealtime() - started}")
        userLocation.invalidate()
    }

    private fun send(event: String, arguments: Any?) { if (alive) channel.invokeMethod(event, arguments) }
    fun onActivityStart() { if (alive) mapView?.onStart() }
    fun onActivityResume() { if (alive) { mapView?.onResume(); userLocation.resume() } }
    fun onActivityPause() { if (alive) { userLocation.pause(); mapView?.onPause() } }
    fun onActivityStop() { if (alive) mapView?.onStop() }
    fun onLowMemory() { if (alive) mapView?.onLowMemory() }

    override fun dispose() {
        if (!alive) return
        alive = false; ready = false
        container.removeCallbacks(renderPois)
        drivingService.dispose()
        userLocation.pause(); userLocation.map = null
        routeArrows.legs = emptyList(); routeArrows.map = null
        mapView?.onPause(); mapView?.onStop(); mapView?.onDestroy()
        map = null; mapView = null
        channel.setMethodCallHandler(null)
        container.removeAllViews()
        assets.clear(); markers.clear(); pois = emptyList(); iconCache.evictAll(); markerLayoutCache.evictAll(); dotIcon = null; routes.clear()
        onDisposed(this)
    }

    private fun cityCenter(city: String): LatLng = when (city) {
        "北京" -> LatLng(39.9042, 116.4074)
        "广州" -> LatLng(23.1291, 113.2644)
        "深圳" -> LatLng(22.5431, 114.0579)
        "杭州" -> LatLng(30.2741, 120.1551)
        "成都" -> LatLng(30.5723, 104.0665)
        else -> LatLng(31.2227, 121.4712)
    }
    private fun markerLayout(key: IconKey): MarkerLayout = markerLayoutCache.get(key) ?: run {
        val name = key.sequence?.toString() ?: key.label
        val rating = key.rating?.let { "★ %.1f".format(it) } ?: ""
        val namePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            // TextPaint has its own density (default 1), which otherwise shadows
            // the view density here and makes names much smaller than badges.
            density = this@SiponPetalView.density
            color = if (key.dark) Color.rgb(194, 182, 194) else Color.rgb(42, 35, 33)
            textSize = 10f * density
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            if (key.dark) setShadowLayer(2f * density, 0f, 0f, Color.BLACK)
        }
        val nameWidth = ceil(Layout.getDesiredWidth(name, namePaint).toDouble()).toInt()
            .coerceIn(1, (128f * density).toInt().coerceAtLeast(1))
        val nameLayout = StaticLayout.Builder.obtain(name, 0, name.length, namePaint, nameWidth)
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setIncludePad(false)
            .setMaxLines(2)
            .setEllipsize(TextUtils.TruncateAt.END)
            .build()
        val icon = assets[key.category]
        val iconSize = 16f * density
        val ratingPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = if (key.selected || key.dark) Color.WHITE else Color.rgb(42, 35, 33)
            textSize = 13f * density
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
        MarkerLayout(nameLayout, rating, ratingPaint, icon, badgeWidth, badgeGap, width, height)
            .also { markerLayoutCache.put(key, it) }
    }

    private fun makeMarkerBitmap(key: IconKey, layout: MarkerLayout): Bitmap {
        val width = layout.width
        val height = layout.height
        val badgeWidth = layout.badgeWidth
        val badgeHeight = 28f * density
        val iconSize = 16f * density
        val badgePadding = 7f * density
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val background = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = if (key.selected) POI_THEME_COLOR else if (key.dark) Color.rgb(48, 43, 42) else Color.WHITE
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
        if (layout.icon != null) {
            val top = (badgeHeight - iconSize) / 2f
            val iconPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                if (key.selected) colorFilter = PorterDuffColorFilter(Color.WHITE, PorterDuff.Mode.SRC_IN)
            }
            canvas.drawBitmap(layout.icon, null, RectF(x, top, x + iconSize, top + iconSize), iconPaint)
            x += iconSize + layout.badgeGap
        }
        if (layout.rating.isNotEmpty()) {
            canvas.drawText(layout.rating, x,
                (badgeHeight - layout.ratingPaint.ascent() - layout.ratingPaint.descent()) / 2f, layout.ratingPaint)
        }
        canvas.save()
        canvas.translate((width - layout.name.width) / 2f, badgeHeight + 5f * density)
        if (!key.dark) {
            // A solid halo separates names from roads and buildings; a blurred
            // shadow alone loses contrast when the SDK scales the marker bitmap.
            val namePaint = layout.name.paint
            val fillPaint = TextPaint().apply { set(namePaint) }
            try {
                namePaint.color = Color.WHITE
                namePaint.style = Paint.Style.STROKE
                namePaint.strokeWidth = 3f * density
                namePaint.strokeJoin = Paint.Join.ROUND
                layout.name.draw(canvas)
            } finally {
                // Layouts are cached and must retain their original fill paint.
                namePaint.set(fillPaint)
            }
        }
        layout.name.draw(canvas)
        canvas.restore()
        return bitmap
    }

}
