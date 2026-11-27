package org.amnezia.core.vpn

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.amnezia.core.models.ConnectionState
import org.amnezia.core.models.ConnectionStats
import org.amnezia.core.models.ServerProfile
import kotlin.random.Random

/** Debug-only simulation of a tunnel. Never wired into release builds. */
class MockTunnelService(
    private val scope: CoroutineScope = CoroutineScope(Dispatchers.Default)
) : VpnTunnelService {

    private val _state = MutableStateFlow<ConnectionState>(ConnectionState.Disconnected)
    override val state: StateFlow<ConnectionState> = _state.asStateFlow()

    private val _stats = MutableStateFlow(ConnectionStats())
    override val stats: StateFlow<ConnectionStats> = _stats.asStateFlow()

    override val providesTrafficStats: Boolean = true

    private var simulationJob: Job? = null
    private var startTime: Long = 0L

    override suspend fun startTunnel(profile: ServerProfile, options: TunnelOptions) {
        simulationJob?.cancel()

        _state.value = ConnectionState.Connecting
        delay(700)

        startTime = System.currentTimeMillis()
        _state.value = ConnectionState.Connected

        simulationJob = scope.launch {
            var totalIn = 0L
            var totalOut = 0L

            while (isActive) {
                delay(1000)
                if (_state.value != ConnectionState.Connected) break

                val duration = (System.currentTimeMillis() - startTime) / 1000
                val rateIn = Random.nextLong(150_000, 1_800_000)
                val rateOut = Random.nextLong(20_000, 450_000)
                totalIn += rateIn
                totalOut += rateOut
                val latency = Random.nextLong(22, 58)

                _stats.value = ConnectionStats(
                    bytesIn = totalIn,
                    bytesOut = totalOut,
                    bytesInPerSecond = rateIn,
                    bytesOutPerSecond = rateOut,
                    durationSeconds = duration,
                    latencyMs = latency,
                    jitterMs = Random.nextLong(1, 8),
                    packetLossPercent = 0,
                    lastHandshakeEpochMs = startTime
                )
            }
        }
    }

    override suspend fun stopTunnel() {
        if (_state.value == ConnectionState.Disconnected) return
        _state.value = ConnectionState.Disconnecting
        simulationJob?.cancel()
        simulationJob = null
        delay(300)
        _state.value = ConnectionState.Disconnected
        _stats.value = ConnectionStats()
    }
}
