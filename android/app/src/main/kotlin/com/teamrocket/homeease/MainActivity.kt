package com.teamrocket.homeease

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.os.Build
import android.content.pm.PackageManager

class MainActivity : FlutterActivity() {
    private var pendingPermission: MethodChannel.Result? = null
    private var permissionRequested = false
    private val lanPermission = "android.permission.ACCESS_LOCAL_NETWORK"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "homeease/network")
            .setMethodCallHandler { call, result ->
                if (call.method != "ensureLocalNetwork") {
                    result.notImplemented()
                } else if (Build.VERSION.SDK_INT < 37 || checkSelfPermission(lanPermission) == PackageManager.PERMISSION_GRANTED) {
                    result.success(true)
                } else if (permissionRequested || pendingPermission != null) {
                    // Polling must not repeatedly prompt after a denial.
                    result.success(false)
                } else {
                    permissionRequested = true
                    pendingPermission = result
                    requestPermissions(arrayOf(lanPermission), 1001)
                }
            }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1001) {
            pendingPermission?.success(grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED)
            pendingPermission = null
        }
    }
}
