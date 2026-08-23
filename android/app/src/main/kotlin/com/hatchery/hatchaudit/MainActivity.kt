package com.hatchery.hatchaudit

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.chickmark/realtime_background"
    private val activationTimeoutMillis = 5_000L
    private var channel: MethodChannel? = null
    private var pendingActivation: MethodChannel.Result? = null
    private var activationTimeout: Runnable? = null
    private var receiverRegistered = false

    private val lifecycleReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                PipRealtimeForegroundService.ACTION_STARTED -> completeActivationSuccess()
                PipRealtimeForegroundService.ACTION_START_FAILED ->
                    completeActivationError("foreground_service_start_failed", "Could not start Pip Live background service.")
                PipRealtimeForegroundService.ACTION_END_REQUESTED ->
                    channel?.invokeMethod("requestEnd", null)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        registerLifecycleReceiver()
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).also { methodChannel ->
            methodChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "activate" -> activate(result)
                    "deactivate" -> {
                        stopService(Intent(this, PipRealtimeForegroundService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun activate(result: MethodChannel.Result) {
        if (pendingActivation != null) {
            result.error("foreground_service_start_pending", "Pip Live background service is already starting.", null)
            return
        }
        pendingActivation = result
        val timeout = Runnable {
            completeActivationError("foreground_service_start_timeout", "Pip Live background service did not start in time.")
        }
        activationTimeout = timeout
        window.decorView.postDelayed(timeout, activationTimeoutMillis)
        try {
            val intent = Intent(this, PipRealtimeForegroundService::class.java)
                .setAction(PipRealtimeForegroundService.ACTION_START)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
        } catch (_: Exception) {
            completeActivationError("foreground_service_start_failed", "Could not start Pip Live background service.")
        }
    }

    private fun completeActivationSuccess() {
        val result = pendingActivation ?: return
        clearPendingActivation()
        result.success(null)
    }

    private fun completeActivationError(code: String, message: String) {
        val result = pendingActivation ?: return
        clearPendingActivation()
        stopService(Intent(this, PipRealtimeForegroundService::class.java))
        result.error(code, message, null)
    }

    private fun clearPendingActivation() {
        activationTimeout?.let { window.decorView.removeCallbacks(it) }
        activationTimeout = null
        pendingActivation = null
    }

    private fun registerLifecycleReceiver() {
        val filter = IntentFilter().apply {
            addAction(PipRealtimeForegroundService.ACTION_STARTED)
            addAction(PipRealtimeForegroundService.ACTION_START_FAILED)
            addAction(PipRealtimeForegroundService.ACTION_END_REQUESTED)
        }
        ContextCompat.registerReceiver(
            this,
            lifecycleReceiver,
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        receiverRegistered = true
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        pendingActivation?.error("foreground_service_activity_destroyed", "Pip Live activity was closed while starting.", null)
        clearPendingActivation()
        stopService(Intent(this, PipRealtimeForegroundService::class.java))
        if (receiverRegistered) unregisterReceiver(lifecycleReceiver)
        receiverRegistered = false
        channel?.setMethodCallHandler(null)
        channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
