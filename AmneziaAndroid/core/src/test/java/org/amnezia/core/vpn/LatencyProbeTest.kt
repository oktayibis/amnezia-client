package org.amnezia.core.vpn

import org.amnezia.core.models.ConnectionStats
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.ServerSocket
import kotlin.concurrent.thread

class LatencyProbeTest {

    @Test
    fun tcpPingMeasuresRoundTripTimeToLocalServerSocket() {
        ServerSocket(0).use { server ->
            val port = server.localPort
            val acceptThread = thread {
                runCatching { server.accept().close() }
            }
            val latencyMs = LatencyProbe.tcpPingMs("127.0.0.1", port, timeoutMs = 1_000)
            acceptThread.join(1_000)
            assertNotNull(latencyMs)
            assertTrue("Expected positive latency in ms, got $latencyMs", latencyMs!! >= 1L)
        }
    }

    @Test
    fun tcpPingReturnsNullOnClosedPort() {
        val closedPort = ServerSocket(0).use { it.localPort }
        val latencyMs = LatencyProbe.tcpPingMs("127.0.0.1", closedPort, timeoutMs = 200)
        assertNull(latencyMs)
    }

    @Test
    fun parsesCloudflareTraceResponseAndComputesMbps() {
        val traceBody = """
            fl=29f123
            h=1.1.1.1
            ip=94.138.209.154
            ts=1795729718.123
            visit_scheme=https
            uag=AWGConnect-Diagnostics/1.0
            colo=FRA
            sliver=none
            http=http/2
            loc=DE
            tls=TLSv1.3
            sni=off
            warp=off
        """.trimIndent()

        val trace = NetworkDiagnosticsTool.parseCloudflareTrace(traceBody)
        assertNotNull(trace)
        assertEquals("94.138.209.154", trace!!.ip)
        assertEquals("DE", trace.country)
        assertEquals("FRA", trace.colo)

        // 5 MB in 1.0 second = 40.0 Mbps
        assertEquals(40.0, NetworkDiagnosticsTool.computeMbps(5_000_000L, 1.0), 0.01)

        val stats = ConnectionStats(
            latencyMs = 58L,
            jitterMs = 3L,
            lastHandshakeEpochMs = System.currentTimeMillis() - 500L
        )
        assertEquals("Just now", stats.formattedHandshakeAge)
    }
}
