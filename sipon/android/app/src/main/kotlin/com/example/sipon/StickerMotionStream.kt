package com.example.sipon

import android.app.Activity
import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.view.Surface
import io.flutter.plugin.common.EventChannel

/** Screen-relative gravity in g, matching the iOS sticker_motion channel. */
class StickerMotionStream(private val activity: Activity) :
    EventChannel.StreamHandler, SensorEventListener {
    private val manager = activity.getSystemService(Context.SENSOR_SERVICE) as SensorManager
    private var sink: EventChannel.EventSink? = null
    private var active = true
    private var listening = false
    private var filteredX = 0.0
    private var filteredY = 0.0
    private var initialized = false
    private var lastTimestamp = 0L

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        stop()
        sink = events
        start()
    }

    override fun onCancel(arguments: Any?) {
        stop()
        sink = null
    }

    fun setActive(value: Boolean) {
        active = value
        if (value) start() else stop()
    }

    private fun start() {
        if (!active || sink == null || listening) return
        try {
            for (type in listOf(Sensor.TYPE_GRAVITY, Sensor.TYPE_ACCELEROMETER)) {
                val sensor = manager.getDefaultSensor(type) ?: continue
                if (manager.registerListener(this, sensor, 33_333)) {
                    listening = true
                    return
                }
            }
        } catch (_: SecurityException) {
            // Keep the existing static gravity if device policy disables sensors.
        }
        sink?.endOfStream()
        sink = null
    }

    private fun stop() {
        manager.unregisterListener(this)
        listening = false
        initialized = false
        lastTimestamp = 0L
    }

    override fun onSensorChanged(event: SensorEvent) {
        if (!listening || !active || sink == null) return
        if (lastTimestamp != 0L && event.timestamp - lastTimestamp < 30_000_000L) return
        lastTimestamp = event.timestamp
        val x = event.values[0].toDouble()
        val y = event.values[1].toDouble()
        if (!x.isFinite() || !y.isFinite()) return
        // Accelerometers include hand movement; remove it with a low-pass filter.
        val alpha = if (event.sensor.type == Sensor.TYPE_ACCELEROMETER && initialized) 0.18 else 1.0
        filteredX += alpha * (x - filteredX)
        filteredY += alpha * (y - filteredY)
        initialized = true
        val gx = filteredX / SensorManager.GRAVITY_EARTH
        val gy = filteredY / SensorManager.GRAVITY_EARTH
        @Suppress("DEPRECATION")
        val rotation = activity.windowManager.defaultDisplay.rotation
        val gravity = when (rotation) {
            Surface.ROTATION_90 -> listOf(gy, gx)
            Surface.ROTATION_180 -> listOf(gx, -gy)
            Surface.ROTATION_270 -> listOf(-gy, -gx)
            else -> listOf(-gx, gy)
        }
        sink?.success(gravity)
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
}
