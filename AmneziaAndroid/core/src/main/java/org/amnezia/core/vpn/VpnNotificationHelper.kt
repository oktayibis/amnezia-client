package org.amnezia.core.vpn

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import org.amnezia.core.models.ServerProfile

/**
 * Manages the ongoing system notification displayed when the AmneziaWG VPN tunnel is active.
 */
class VpnNotificationHelper(private val context: Context) {

    private val notificationManager =
        context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    init {
        createChannel()
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "VPN Connection Status",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Shows when the VPN tunnel is actively encrypting traffic"
                setShowBadge(false)
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    fun showConnected(profile: ServerProfile) {
        val notification = buildNotification(profile)
        notificationManager.notify(NOTIFICATION_ID, notification)
    }

    fun cancel() {
        notificationManager.cancel(NOTIFICATION_ID)
    }

    private fun buildNotification(profile: ServerProfile): Notification {
        val disconnectIntent = PendingIntent.getBroadcast(
            context,
            REQUEST_DISCONNECT,
            Intent(ACTION_DISCONNECT_BROADCAST).setPackage(context.packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentTitle("${appLabel()} Active")
            .setContentText("Connected to ${profile.name} (${profile.endpointString})")
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(launchIntent())
            .addAction(0, "Disconnect", disconnectIntent)
            .build()
    }

    private fun launchIntent(): PendingIntent? {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return null
        return PendingIntent.getActivity(
            context,
            0,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun appLabel(): String =
        context.applicationInfo.loadLabel(context.packageManager).toString()

    companion object {
        const val CHANNEL_ID = "awg_vpn_status"
        const val NOTIFICATION_ID = 4001
        const val ACTION_DISCONNECT_BROADCAST = "org.amnezia.vpn.ACTION_DISCONNECT"
        private const val REQUEST_DISCONNECT = 101
    }
}
