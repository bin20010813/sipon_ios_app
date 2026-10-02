package com.example.sipon.map

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.*
import android.hardware.*
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Looper
import android.view.Surface
import android.view.View
import org.maplibre.android.geometry.LatLng
import org.maplibre.android.maps.MapLibreMap

/** Screen overlay: geographic position comes only from the device, never the camera. */
internal class SiponUserLocationView(context: Context) : View(context), SensorEventListener, LocationListener {
    var map: MapLibreMap? = null
    var dark = false
    private val sensors = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private val locations = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG)
    private val density = resources.displayMetrics.density
    private var position: Location? = null
    val businessPosition: Gcj02Point?
        get() = position?.let {
            MapCoordinateAdapter.toBusiness(Cgcs2000Point(it.longitude, it.latitude))
        }
    private var heading: Float? = null
    private var running = false
    private var resumed = true
    private val cameraMove = MapLibreMap.OnCameraMoveListener { invalidate() }

    fun resume() { resumed = true; start() }
    fun pause() { resumed = false; stop() }
    fun refreshPermission() { start() }

    override fun onAttachedToWindow() { super.onAttachedToWindow(); start() }
    override fun onDetachedFromWindow() { stop(); super.onDetachedFromWindow() }

    @Suppress("MissingPermission")
    private fun start() {
        if (running || !resumed || !isAttachedToWindow) return
        val fine = context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED
        val coarse = context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (!fine && !coarse) return
        running = true
        map?.addOnCameraMoveListener(cameraMove)
        try {
            for (provider in listOf(LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER)) {
                if (provider == LocationManager.GPS_PROVIDER && !fine) continue
                if (!locations.isProviderEnabled(provider)) continue
                locations.getLastKnownLocation(provider)?.let { acceptLocation(it) }
                locations.requestLocationUpdates(provider, 1000L, 1f, this, Looper.getMainLooper())
            }
        } catch (_: SecurityException) { stop(); return }
          catch (_: IllegalArgumentException) { /* Unavailable provider: retain available fixes. */ }
        sensors.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)?.let {
            sensors.registerListener(this, it, SensorManager.SENSOR_DELAY_GAME)
        }
    }

    private fun stop() {
        running = false
        sensors.unregisterListener(this)
        locations.removeUpdates(this)
        map?.removeOnCameraMoveListener(cameraMove)
        heading = null
        position = null
        invalidate()
    }

    override fun onLocationChanged(location: Location) { acceptLocation(location) }
    override fun onProviderDisabled(provider: String) {
        if (position?.provider == provider) { position = null; invalidate() }
    }
    override fun onProviderEnabled(provider: String) {}
    @Deprecated("Legacy platform callback")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}

    private fun acceptLocation(location: Location) {
        val age = (android.os.SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos) / 1_000_000
        if (age !in 0..120_000 || !location.latitude.isFinite() || !location.longitude.isFinite()) return
        if (position != null && location.elapsedRealtimeNanos < position!!.elapsedRealtimeNanos) return
        position = location
        invalidate()
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        if (accuracy == SensorManager.SENSOR_STATUS_UNRELIABLE) { heading = null; invalidate() }
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (event.accuracy == SensorManager.SENSOR_STATUS_UNRELIABLE) {
            heading = null
            invalidate()
            return
        }
        val matrix = FloatArray(9)
        val remapped = FloatArray(9)
        SensorManager.getRotationMatrixFromVector(matrix, event.values)
        val axes = when (display?.rotation) {
            Surface.ROTATION_90 -> SensorManager.AXIS_Y to SensorManager.AXIS_MINUS_X
            Surface.ROTATION_180 -> SensorManager.AXIS_MINUS_X to SensorManager.AXIS_MINUS_Y
            Surface.ROTATION_270 -> SensorManager.AXIS_MINUS_Y to SensorManager.AXIS_X
            else -> SensorManager.AXIS_X to SensorManager.AXIS_Y
        }
        SensorManager.remapCoordinateSystem(matrix, axes.first, axes.second, remapped)
        val orientation = SensorManager.getOrientation(remapped, FloatArray(3))
        val declination = position?.let {
            GeomagneticField(it.latitude.toFloat(), it.longitude.toFloat(), it.altitude.toFloat(), System.currentTimeMillis()).declination
        } ?: 0f
        val next = ((Math.toDegrees(orientation[0].toDouble()).toFloat() + declination) % 360 + 360) % 360
        if (!next.isFinite()) return
        heading = heading?.let { (it + ((next - it + 540) % 360 - 180) * 0.25f + 360) % 360 } ?: next
        postInvalidateOnAnimation()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val location = position ?: return
        val current = map ?: return
        val point = current.projection.toScreenLocation(LatLng(location.latitude, location.longitude))
        val color = if (dark) Color.rgb(232, 160, 204) else Color.rgb(154, 61, 120)
        canvas.save()
        canvas.translate(point.x, point.y)
        canvas.scale(density, density)
        heading?.let {
            canvas.save()
            canvas.rotate(it - current.cameraPosition.bearing.toFloat())
            paint.shader = RadialGradient(0f, 0f, 48f,
                intArrayOf((color and 0x00ffffff) or (140 shl 24), color and 0x00ffffff),
                floatArrayOf(0f, 1f), Shader.TileMode.CLAMP)
            canvas.drawArc(RectF(-48f, -48f, 48f, 48f), -126f, 72f, true, paint)
            paint.shader = null
            canvas.restore()
        }
        paint.color = Color.WHITE
        canvas.drawCircle(0f, 0f, 9f, paint)
        paint.color = color
        canvas.drawCircle(0f, 0f, 6f, paint)
        canvas.restore()
    }
}
