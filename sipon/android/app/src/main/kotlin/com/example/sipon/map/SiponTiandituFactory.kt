package com.example.sipon.map

import android.content.Context
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

internal class SiponTiandituFactory(
    private val messenger: BinaryMessenger,
    private val onCreated: (SiponTiandituView) -> Unit,
    private val onDisposed: (SiponTiandituView) -> Unit,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView =
        SiponTiandituView(context, viewId, messenger, onDisposed).also(onCreated)
}
