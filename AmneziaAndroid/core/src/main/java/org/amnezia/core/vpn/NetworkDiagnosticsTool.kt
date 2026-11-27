package org.amnezia.core.vpn

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.amnezia.core.models.ServerProfile
import java.net.HttpURLConnection
import java.net.URL
import kotlin.math.abs
import kotlin.math.roundToLong

/**
 * Built-in network diagnostics & speedtest tool for Android Mobile and Android TV.
 *
 * Provides:
 * - Multi-sample Ping, Jitter, and Packet Loss measurement
 * - DNS resolution / server reachability latency check
 * - Public exit IP, country, and Cloudflare datacenter trace (`1.1.1.1/cdn-cgi/trace`)
 * - Live Download and Upload bandwidth speedtest (in Mbps) over HTTPS
 */
object NetworkDiagnosticsTool {

    data class PingSampleResult(
        val avgLatencyMs: Long?,
        val minLatencyMs: Long?,
        val maxLatencyMs: Long?,
        val jitterMs: Long?,
        val packetLossPercent: Int
    )

    data class PublicIpTrace(
        val ip: String,
        val country: String,
        val colo: String,
        val warp: String? = null
    )

    data class DiagnosticsSnapshot(
        val publicIp: String? = null,
        val country: String? = null,
        val colo: String? = null,
        val pingMs: Long? = null,
        val minPingMs: Long? = null,
        val maxPingMs: Long? = null,
        val jitterMs: Long? = null,
        val packetLossPercent: Int? = null,
        val dnsLatencyMs: Long? = null
    )

    data class SpeedtestResult(
        val downloadMbps: Double,
        val uploadMbps: Double,
        val pingMs: Long?,
        val jitterMs: Long?,
        val packetLossPercent: Int,
        val publicIp: String? = null,
        val country: String? = null,
        val colo: String? = null,
        val dnsLatencyMs: Long? = null
    )

    /**
     * Runs [samples] back-to-back latency probes to compute average/min/max ping, jitter, and packet loss.
     */
    suspend fun measurePingJitterAndLoss(
        profile: ServerProfile?,
        dnsOverride: List<String>? = null,
        samples: Int = 4
    ): PingSampleResult = withContext(Dispatchers.IO) {
        val totalSamples = samples.coerceIn(1, 10)
        val rtts = mutableListOf<Long>()
        var failures = 0

        repeat(totalSamples) {
            val rtt = if (profile != null) {
                LatencyProbe.measureTunnelLatencyMs(profile, dnsOverride)
            } else {
                LatencyProbe.tcpPingMs("1.1.1.1", 53) ?: LatencyProbe.tcpPingMs("1.1.1.1", 443)
            }
            if (rtt != null) {
                rtts.add(rtt)
            } else {
                failures++
            }
        }

        val lossPercent = ((failures * 100.0) / totalSamples).roundToLong().toInt().coerceIn(0, 100)
        if (rtts.isEmpty()) {
            return@withContext PingSampleResult(
                avgLatencyMs = null,
                minLatencyMs = null,
                maxLatencyMs = null,
                jitterMs = null,
                packetLossPercent = lossPercent
            )
        }

        val avg = rtts.average().roundToLong().coerceAtLeast(1L)
        val min = rtts.minOrNull()
        val max = rtts.maxOrNull()
        val jitter = if (rtts.size >= 2) {
            rtts.zipWithNext { a, b -> abs(b - a) }.average().roundToLong()
        } else {
            0L
        }

        PingSampleResult(
            avgLatencyMs = avg,
            minLatencyMs = min,
            maxLatencyMs = max,
            jitterMs = jitter,
            packetLossPercent = lossPercent
        )
    }

    /**
     * Measures DNS server TCP reachability latency in milliseconds.
     */
    suspend fun measureDnsLatencyMs(
        profile: ServerProfile?,
        dnsOverride: List<String>? = null
    ): Long? = withContext(Dispatchers.IO) {
        val dns = (dnsOverride?.takeIf { it.isNotEmpty() } ?: profile?.dnsServers)
            ?.firstOrNull { it.isNotBlank() && !it.startsWith("$") }
            ?.trim()
            ?: "1.1.1.1"
        LatencyProbe.tcpPingMs(dns, 53, timeoutMs = 1_500)
            ?: LatencyProbe.tcpPingMs(dns, 443, timeoutMs = 1_500)
    }

    /**
     * Fetches public exit IP, country code, and edge colo from Cloudflare's trace endpoint.
     */
    suspend fun fetchPublicIpTrace(): PublicIpTrace? = withContext(Dispatchers.IO) {
        val urls = listOf(
            "https://1.1.1.1/cdn-cgi/trace",
            "https://1.0.0.1/cdn-cgi/trace",
            "https://cloudflare.com/cdn-cgi/trace"
        )
        for (urlStr in urls) {
            val parsed = runCatching {
                val conn = (URL(urlStr).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 3_000
                    readTimeout = 3_000
                    requestMethod = "GET"
                    useCaches = false
                    setRequestProperty("User-Agent", "AWGConnect-Diagnostics/1.0")
                }
                try {
                    if (conn.responseCode in 200..299) {
                        val body = conn.inputStream.bufferedReader().use { it.readText() }
                        parseCloudflareTrace(body)
                    } else null
                } finally {
                    conn.disconnect()
                }
            }.getOrNull()
            if (parsed != null) return@withContext parsed
        }
        null
    }

    internal fun parseCloudflareTrace(body: String): PublicIpTrace? {
        val kv = mutableMapOf<String, String>()
        body.lineSequence().forEach { line ->
            val idx = line.indexOf('=')
            if (idx > 0) {
                val k = line.substring(0, idx).trim()
                val v = line.substring(idx + 1).trim()
                if (k.isNotEmpty() && v.isNotEmpty()) {
                    kv[k] = v
                }
            }
        }
        val ip = kv["ip"] ?: return null
        return PublicIpTrace(
            ip = ip,
            country = kv["loc"] ?: "--",
            colo = kv["colo"] ?: "--",
            warp = kv["warp"]
        )
    }

    /**
     * Runs a fast diagnostic check (Ping, Jitter, Packet Loss, DNS Latency, Public Exit IP & Country).
     */
    suspend fun runDiagnostics(
        profile: ServerProfile?,
        dnsOverride: List<String>? = null
    ): DiagnosticsSnapshot = withContext(Dispatchers.IO) {
        val pingResult = measurePingJitterAndLoss(profile, dnsOverride, samples = 4)
        val dnsLatency = measureDnsLatencyMs(profile, dnsOverride)
        val trace = fetchPublicIpTrace()
        DiagnosticsSnapshot(
            publicIp = trace?.ip,
            country = trace?.country,
            colo = trace?.colo,
            pingMs = pingResult.avgLatencyMs,
            minPingMs = pingResult.minLatencyMs,
            maxPingMs = pingResult.maxLatencyMs,
            jitterMs = pingResult.jitterMs,
            packetLossPercent = pingResult.packetLossPercent,
            dnsLatencyMs = dnsLatency
        )
    }

    /**
     * Measures download speed in Mbps over HTTPS.
     */
    suspend fun measureDownloadMbps(
        bytes: Int = 4_000_000,
        onProgress: ((Double) -> Unit)? = null
    ): Double = withContext(Dispatchers.IO) {
        val endpoints = listOf(
            "https://speed.cloudflare.com/__down?bytes=$bytes",
            "https://speed.cloudflare.com/__down?bytes=1000000"
        )
        for (urlStr in endpoints) {
            val mbps = runCatching {
                val conn = (URL(urlStr).openConnection() as HttpURLConnection).apply {
                    connectTimeout = 4_000
                    readTimeout = 8_000
                    requestMethod = "GET"
                    useCaches = false
                    setRequestProperty("Cache-Control", "no-cache")
                }
                try {
                    val startNs = System.nanoTime()
                    var totalBytes = 0L
                    val buf = ByteArray(32 * 1024)
                    conn.inputStream.use { input ->
                        var lastReportNs = startNs
                        while (true) {
                            val read = input.read(buf)
                            if (read <= 0) break
                            totalBytes += read
                            val nowNs = System.nanoTime()
                            if (nowNs - startNs > 6_000_000_000L) break // cap at 6s for snappy UX
                            if (onProgress != null && nowNs - lastReportNs >= 250_000_000L) {
                                lastReportNs = nowNs
                                val secs = (nowNs - startNs) / 1_000_000_000.0
                                if (secs > 0.05) {
                                    onProgress( computeMbps(totalBytes, secs) )
                                }
                            }
                        }
                    }
                    val elapsedSec = ((System.nanoTime() - startNs) / 1_000_000_000.0).coerceAtLeast(0.001)
                    if (totalBytes > 0L) computeMbps(totalBytes, elapsedSec) else null
                } finally {
                    conn.disconnect()
                }
            }.getOrNull()
            if (mbps != null && mbps > 0.0) return@withContext mbps
        }
        0.0
    }

    /**
     * Measures upload speed in Mbps over HTTPS.
     */
    suspend fun measureUploadMbps(
        bytes: Int = 1_500_000,
        onProgress: ((Double) -> Unit)? = null
    ): Double = withContext(Dispatchers.IO) {
        runCatching {
            val conn = (URL("https://speed.cloudflare.com/__up").openConnection() as HttpURLConnection).apply {
                connectTimeout = 4_000
                readTimeout = 8_000
                requestMethod = "POST"
                doOutput = true
                useCaches = false
                setFixedLengthStreamingMode(bytes)
                setRequestProperty("Content-Type", "application/octet-stream")
            }
            try {
                val chunk = ByteArray(32 * 1024) { 0x41 }
                val startNs = System.nanoTime()
                var sent = 0L
                var lastReportNs = startNs
                conn.outputStream.use { out ->
                    while (sent < bytes) {
                        val toWrite = minOf(chunk.size.toLong(), bytes - sent).toInt()
                        out.write(chunk, 0, toWrite)
                        sent += toWrite
                        val nowNs = System.nanoTime()
                        if (onProgress != null && nowNs - lastReportNs >= 200_000_000L) {
                            lastReportNs = nowNs
                            val secs = (nowNs - startNs) / 1_000_000_000.0
                            if (secs > 0.05) {
                                onProgress(computeMbps(sent, secs))
                            }
                        }
                    }
                    out.flush()
                }
                conn.responseCode
                val elapsedSec = ((System.nanoTime() - startNs) / 1_000_000_000.0).coerceAtLeast(0.001)
                computeMbps(sent, elapsedSec)
            } finally {
                conn.disconnect()
            }
        }.getOrDefault(0.0)
    }

    /**
     * Full end-to-end speedtest: Ping/Jitter/Loss + Public IP trace + Download Mbps + Upload Mbps.
     */
    suspend fun runSpeedtest(
        profile: ServerProfile?,
        dnsOverride: List<String>? = null,
        onPhase: (phase: String, downloadMbps: Double?, uploadMbps: Double?) -> Unit = { _, _, _ -> }
    ): SpeedtestResult = withContext(Dispatchers.IO) {
        onPhase("Measuring ping & jitter...", null, null)
        val pingResult = measurePingJitterAndLoss(profile, dnsOverride, samples = 4)
        val dnsLatency = measureDnsLatencyMs(profile, dnsOverride)
        val trace = fetchPublicIpTrace()

        onPhase("Testing download speed...", 0.0, null)
        val downMbps = measureDownloadMbps { liveDown ->
            onPhase("Testing download speed...", liveDown, null)
        }

        onPhase("Testing upload speed...", downMbps, 0.0)
        val upMbps = measureUploadMbps { liveUp ->
            onPhase("Testing upload speed...", downMbps, liveUp)
        }

        onPhase("Complete", downMbps, upMbps)
        SpeedtestResult(
            downloadMbps = downMbps,
            uploadMbps = upMbps,
            pingMs = pingResult.avgLatencyMs,
            jitterMs = pingResult.jitterMs,
            packetLossPercent = pingResult.packetLossPercent,
            publicIp = trace?.ip,
            country = trace?.country,
            colo = trace?.colo,
            dnsLatencyMs = dnsLatency
        )
    }

    internal fun computeMbps(bytes: Long, seconds: Double): Double {
        if (bytes <= 0L || seconds <= 0.0) return 0.0
        val raw = (bytes * 8.0) / (seconds * 1_000_000.0)
        return (raw * 10.0).roundToLong() / 10.0
    }
}
