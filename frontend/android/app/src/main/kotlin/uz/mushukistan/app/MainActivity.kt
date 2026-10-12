package uz.mushukistan.app

import android.content.ActivityNotFoundException
import android.content.Intent
import android.app.NotificationManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mushukistan/notification_settings")
            .setMethodCallHandler { call, result ->
                if (call.method == "notificationPermissionStatus") {
                    val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
                    val enabled = Build.VERSION.SDK_INT < Build.VERSION_CODES.N || manager.areNotificationsEnabled()
                    result.success(if (enabled) "allowed" else "denied")
                    return@setMethodCallHandler
                }
                if (call.method != "openNotificationSettings") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                try {
                    val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                            .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                    } else {
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:$packageName"))
                    }
                    try {
                        startActivity(intent)
                    } catch (_: ActivityNotFoundException) {
                        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:$packageName")))
                    }
                    result.success(null)
                } catch (error: Exception) {
                    result.error("SETTINGS_UNAVAILABLE", "Could not open Android settings", null)
                }
            }
    }
}
