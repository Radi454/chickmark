package com.hatchery.hatchaudit

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder

class PipRealtimeForegroundService : Service() {
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startCallForeground()
            ACTION_END -> endCall()
        }
        return START_NOT_STICKY
    }

    private fun startCallForeground() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                getSystemService(NotificationManager::class.java).createNotificationChannel(
                    NotificationChannel(
                        NOTIFICATION_CHANNEL_ID,
                        "Pip Live calls",
                        NotificationManager.IMPORTANCE_LOW,
                    ),
                )
            }
            val endIntent = Intent(this, PipRealtimeForegroundService::class.java)
                .setAction(ACTION_END)
            val endPendingIntent = PendingIntent.getService(
                this,
                0,
                endIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val notificationBuilder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Notification.Builder(this, NOTIFICATION_CHANNEL_ID)
            } else {
                Notification.Builder(this)
            }
            val notification = notificationBuilder
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("Pip Live")
                .setContentText("Live voice conversation in progress")
                .setOngoing(true)
                .addAction(Notification.Action.Builder(null, "End", endPendingIntent).build())
                .build()
            startForeground(NOTIFICATION_ID, notification)
            sendAppBroadcast(ACTION_STARTED)
        } catch (_: Exception) {
            sendAppBroadcast(ACTION_START_FAILED)
            stopSelf()
        }
    }

    private fun endCall() {
        sendAppBroadcast(ACTION_END_REQUESTED)
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun sendAppBroadcast(action: String) {
        sendBroadcast(Intent(action).setPackage(packageName))
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val ACTION_START = "com.chickmark.pip.realtime.START"
        const val ACTION_STARTED = "com.chickmark.pip.realtime.STARTED"
        const val ACTION_START_FAILED = "com.chickmark.pip.realtime.START_FAILED"
        const val ACTION_END = "com.chickmark.pip.realtime.END"
        const val ACTION_END_REQUESTED = "com.chickmark.pip.realtime.END_REQUESTED"
        const val NOTIFICATION_CHANNEL_ID = "pip_live_call"
        const val NOTIFICATION_ID = 2401
    }
}
