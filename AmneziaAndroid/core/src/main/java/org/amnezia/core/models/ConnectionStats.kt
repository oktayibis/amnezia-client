package org.amnezia.core.models

data class ConnectionStats(
    val bytesIn: Long = 0L,
    val bytesOut: Long = 0L,
    val bytesInPerSecond: Long = 0L,
    val bytesOutPerSecond: Long = 0L,
    val durationSeconds: Long = 0L,
    val latencyMs: Long? = null,
    val jitterMs: Long? = null,
    val packetLossPercent: Int? = null,
    val lastHandshakeEpochMs: Long? = null
) {
    val formattedDuration: String
        get() {
            val hours = durationSeconds / 3600
            val minutes = (durationSeconds % 3600) / 60
            val seconds = durationSeconds % 60
            return if (hours > 0) {
                String.format("%02d:%02d:%02d", hours, minutes, seconds)
            } else {
                String.format("%02d:%02d", minutes, seconds)
            }
        }

    val formattedDownloadSpeed: String
        get() = formatBytesRate(bytesInPerSecond)

    val formattedUploadSpeed: String
        get() = formatBytesRate(bytesOutPerSecond)

    val formattedBytesIn: String
        get() = formatByteCount(bytesIn)

    val formattedBytesOut: String
        get() = formatByteCount(bytesOut)

    val formattedHandshakeAge: String
        get() {
            val hs = lastHandshakeEpochMs?.takeIf { it > 0L } ?: return "--"
            val ageSec = ((System.currentTimeMillis() - hs) / 1000L).coerceAtLeast(0L)
            return when {
                ageSec < 2L -> "Just now"
                ageSec < 60L -> "${ageSec}s ago"
                ageSec < 3600L -> "${ageSec / 60}m ${ageSec % 60}s ago"
                else -> "${ageSec / 3600}h ${(ageSec % 3600) / 60}m ago"
            }
        }

    private fun formatBytesRate(bytesPerSec: Long): String {
        return when {
            bytesPerSec >= 1_000_000_000L -> String.format("%.1f GB/s", bytesPerSec / 1_000_000_000.0)
            bytesPerSec >= 1_000_000L -> String.format("%.1f MB/s", bytesPerSec / 1_000_000.0)
            bytesPerSec >= 1_000L -> String.format("%.1f KB/s", bytesPerSec / 1_000.0)
            else -> "$bytesPerSec B/s"
        }
    }

    private fun formatByteCount(bytes: Long): String {
        return when {
            bytes >= 1_000_000_000L -> String.format("%.2f GB", bytes / 1_000_000_000.0)
            bytes >= 1_000_000L -> String.format("%.1f MB", bytes / 1_000_000.0)
            bytes >= 1_000L -> String.format("%.1f KB", bytes / 1_000.0)
            else -> "$bytes B"
        }
    }
}
