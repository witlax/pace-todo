package com.witlax.tasktodo

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat

/**
 * 专注前台服务。
 *
 * 只做一件事：在计时期间把进程保活，并在通知栏显示剩余时间。
 * 计时本身仍由 Dart 侧持有；通知每秒自算剩余，避免依赖 Dart 心跳。
 */
class FocusService : Service() {
    companion object {
        const val ACTION_START = "com.witlax.tasktodo.focus.START"
        const val ACTION_STOP = "com.witlax.tasktodo.focus.STOP"
        const val EXTRA_TITLE = "title"
        const val EXTRA_END_AT = "endAt"

        private const val CHANNEL_ID = "focus_timer"
        private const val NOTIFICATION_ID = 4201
    }

    private val handler = Handler(Looper.getMainLooper())
    private var endAt: Long = 0L
    private var title: String = "专注中"
    private var ticker: Runnable? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopTicker()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                title = intent?.getStringExtra(EXTRA_TITLE) ?: "专注中"
                endAt = intent?.getLongExtra(EXTRA_END_AT, 0L) ?: 0L
                createChannel()
                startForeground(NOTIFICATION_ID, buildNotification(remainingText()))
                startTicker()
            }
        }
        return START_STICKY
    }

    private fun startTicker() {
        stopTicker()
        val runnable = object : Runnable {
            override fun run() {
                val text = remainingText()
                notify(buildNotification(text))
                if (text == "00:00") {
                    finishNaturally()
                } else {
                    handler.postDelayed(this, 1000)
                }
            }
        }
        ticker = runnable
        handler.postDelayed(runnable, 1000)
    }

    private fun stopTicker() {
        ticker?.let { handler.removeCallbacks(it) }
        ticker = null
    }

    /**
     * 自然结束：只收尾，不再发通知。
     * 「专注结束」的提醒由 Dart 侧统一发（NotificationService.showFocusDone），
     * 两边都发会出现两条同样意思的通知。
     */
    private fun finishNaturally() {
        stopTicker()
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun remainingText(): String {
        if (endAt <= 0L) return "00:00"
        val left = ((endAt - System.currentTimeMillis()) / 1000).coerceAtLeast(0)
        return "%02d:%02d".format(left / 60, left % 60)
    }

    private fun buildNotification(time: String): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(time)
            .setContentText(title)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openAppIntent())
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_STOPWATCH)
            .build()
    }

    private fun openAppIntent(): PendingIntent {
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun notify(notification: Notification) {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, notification)
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "专注计时",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "专注时在通知栏显示剩余时间"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    override fun onDestroy() {
        stopTicker()
        super.onDestroy()
    }
}
