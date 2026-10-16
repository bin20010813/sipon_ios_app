package com.example.sipon.map

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

internal class SiponPetalFactory(
    private val messenger: BinaryMessenger,
    private val onCreated: (SiponPetalView) -> Unit,
    private val onDisposed: (SiponPetalView) -> Unit,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        SiponPetalView(context, viewId, messenger, args as? Map<*, *> ?: emptyMap<Any, Any>(), onDisposed).also(onCreated)
}
