package at.ecrumedia.safernotes

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL_NAME = "at.ecrumedia.safernotes/incoming_links"
    }

    private var incomingLinksChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        incomingLinksChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialLink" -> result.success(intent?.dataString)
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.dataString?.let { link ->
            incomingLinksChannel?.invokeMethod("link", link)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        incomingLinksChannel?.setMethodCallHandler(null)
        incomingLinksChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
