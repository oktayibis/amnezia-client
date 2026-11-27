package org.amnezia.core.vpn

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.amnezia.core.models.ServerProfile
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import kotlin.system.measureNanoTime

/**
 * Measures round-trip network latency (ping) in milliseconds.
 *
 * Uses a multi-stage probe so latency works reliably across Android phones and Android TV devices
 * (even when ICMP is filtered or restricted inside the app sandbox):
 * 1. TCP handshake (SYN -> SYN-ACK) to active DNS / probe endpoints on port 53 or 443
 *    (which routes through `tun0` while the VPN is connected).
 * 2. System `/system/bin/ping -c 1 -W 1` fallback if raw ICMP is permitted.
 * 3. `InetAddress.isReachable` fallback.
 */
object LatencyProbe {

    private const val CONNECT_TIMEOUT_MS = 1_500
    private val FALLBACK_TARGETS = listOf(
        "1.1.1.1" to 53,
        "1.1.1.1" to 443,
        "8.8.8.8" to 53,
        "1.0.0.1" to 53
    )

    /**
     * Measures live tunnel round-trip latency while connected.
     */
    suspend fun measureTunnelLatencyMs(
        profile: ServerProfile,
        dnsOverride: List<String>? = null
    ): Long? = withContext(Dispatchers.IO) {
        val primaryDns = (dnsOverride?.takeIf { it.isNotEmpty() } ?: profile.dnsServers)
            .firstOrNull { it.isNotBlank() && !it.startsWith("$") }
            ?.trim()

        val candidates = buildList {
            if (!primaryDns.isNullOrEmpty()) {
                add(primaryDns to 53)
                add(primaryDns to 443)
            }
            addAll(FALLBACK_TARGETS)
        }.distinct()

        for ((host, port) in candidates) {
            tcpPingMs(host, port)?.let { return@withContext it }
        }

        val icmpHost = primaryDns ?: "1.1.1.1"
        icmpPingMs(icmpHost) ?: reachablePingMs(icmpHost)
    }

    /**
     * Measures reachability/latency to a [ServerProfile]'s host (or its DNS fallback).
     */
    suspend fun measureServerLatencyMs(profile: ServerProfile): Long? = withContext(Dispatchers.IO) {
        val host = profile.host.trim()
        if (host.isNotEmpty()) {
            icmpPingMs(host)?.let { return@withContext it }
            reachablePingMs(host)?.let { return@withContext it }
            for (port in listOf(443, 80, 53, profile.port)) {
                tcpPingMs(host, port)?.let { return@withContext it }
            }
        }
        measureTunnelLatencyMs(profile)
    }

    internal fun tcpPingMs(host: String, port: Int, timeoutMs: Int = CONNECT_TIMEOUT_MS): Long? {
        return try {
            Socket().use { socket ->
                socket.reuseAddress = true
                val address = InetSocketAddress(host, port)
                if (address.isUnresolved) return null
                val elapsedNanos = measureNanoTime {
                    socket.connect(address, timeoutMs)
                }
                (elapsedNanos / 1_000_000L).coerceAtLeast(1L)
            }
        } catch (_: Exception) {
            null
        }
    }

    internal fun icmpPingMs(host: String): Long? {
        return try {
            val process = ProcessBuilder("/system/bin/ping", "-c", "1", "-W", "1", host)
                .redirectErrorStream(true)
                .start()
            val output = process.inputStream.bufferedReader().use { it.readText() }
            val exitCode = process.waitFor()
            if (exitCode != 0) return null
            val match = Regex("""time[=<]([\d.]+)\s*ms""", RegexOption.IGNORE_CASE).find(output)
            match?.groupValues?.getOrNull(1)?.toDoubleOrNull()?.toLong()?.coerceAtLeast(1L)
        } catch (_: Exception) {
            null
        }
    }

    private fun reachablePingMs(host: String): Long? {
        return try {
            val addr = InetAddress.getByName(host)
            var reachable = false
            val elapsedNanos = measureNanoTime {
                reachable = addr.isReachable(CONNECT_TIMEOUT_MS)
            }
            if (reachable) (elapsedNanos / 1_000_000L).coerceAtLeast(1L) else null
        } catch (_: Exception) {
            null
        }
    }
}
