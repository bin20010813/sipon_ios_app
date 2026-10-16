package com.example.sipon.map

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PathMeasure
import android.view.View
import com.huawei.hms.maps.HuaweiMap
import com.huawei.hms.maps.model.LatLng

/** Screen-space chevrons keep a constant size and spacing at every map zoom. */
internal class PetalRouteArrowView(context: Context) : View(context) {
    var map: HuaweiMap? = null
    var legs: List<List<LatLng>> = emptyList()
        set(value) { field = value; invalidate() }

    private val density = resources.displayMetrics.density
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        style = Paint.Style.STROKE
        strokeWidth = 1.4f * density
        strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND
    }
    private val line = Path()
    private val arrow = Path()
    private val measure = PathMeasure()
    private val position = FloatArray(2)
    private val tangent = FloatArray(2)

    init {
        isClickable = false
        isFocusable = false
        importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val projection = map?.projection ?: return
        val spacing = 64f * density
        val length = 4f * density
        val halfWidth = 1.6f * density
        for (points in legs) {
            line.rewind()
            points.forEachIndexed { index, point ->
                val pixel = projection.toScreenLocation(point)
                if (index == 0) line.moveTo(pixel.x.toFloat(), pixel.y.toFloat())
                else line.lineTo(pixel.x.toFloat(), pixel.y.toFloat())
            }
            measure.setPath(line, false)
            var distance = spacing / 2
            while (distance < measure.length - length) {
                if (measure.getPosTan(distance, position, tangent)) {
                    val x = position[0]
                    val y = position[1]
                    if (x >= -length && x <= width + length && y >= -length && y <= height + length) {
                        val dx = tangent[0]
                        val dy = tangent[1]
                        arrow.rewind()
                        arrow.moveTo(x - dx * length - dy * halfWidth, y - dy * length + dx * halfWidth)
                        arrow.lineTo(x, y)
                        arrow.lineTo(x - dx * length + dy * halfWidth, y - dy * length - dx * halfWidth)
                        canvas.drawPath(arrow, paint)
                    }
                }
                distance += spacing
            }
        }
    }
}
