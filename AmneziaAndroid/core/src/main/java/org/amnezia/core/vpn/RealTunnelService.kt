package org.amnezia.core.vpn

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.VpnService
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.amnezia.awg.backend.GoBackend
import org.amnezia.awg.backend.NoopTunnelActionHandler
import org.amnezia.awg.backend.Tunnel
import org.amnezia.core.models.ConnectionState
import org.amnezia.core.models.ConnectionStats
import org.amnezia.core.models.ServerProfile

/**
 * Fully functional [VpnTunnelService] backed by the native AmneziaWG [GoBackend].
 *
 * Encrypts all device IP traffic using WireGuard / AmneziaWG obfuscation,
 * manages the TUN adapter in kernel space, and streams real Rx/Tx statistics.
 */
class RealTunnelService(
    context: Context,
    private val scope: CoroutineScope = CoroutineScope(Dispatchers.Main)
) : VpnTunnelService {

    private val appContext = context.applicationContext
    private val backend = GoBackend(appContext, NoopTunnelActionHandler())
    private val tunnel = AwgTunnel("awg0")
    private val notificationHelper = VpnNotificationHelper(appContext)

    private val _state = MutableStateFlow<ConnectionState>(ConnectionState.Disconnected)
    override val state: StateFlow<ConnectionState> = _state.asStateFlow()

    private val _stats = MutableStateFlow(ConnectionStats())
    override val stats: StateFlow<ConnectionStats> = _stats.asStateFlow()

    /** Live kernel statistics are streamed directly from GoBackend. */
    override val providesTrafficStats: Boolean = true

    private var statsJob: Job? = null
    private var activeProfile: ServerProfile? = null

    private val disconnectReceiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context?, intent: Intent?) {
            if (intent?.action == VpnNotificationHelper.ACTION_DISCONNECT_BROADCAST) {
                scope.launch { stopTunnel() }
            }
        }
    }

    init {
        val filter = IntentFilter(VpnNotificationHelper.ACTION_DISCONNECT_BROADCAST)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            appContext.registerReceiver(disconnectReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            ContextCompat.registerReceiver(appContext, disconnectReceiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
        }
    }

    /** Non-null when the user has not yet accepted the system VPN consent dialog. */
    fun prepareIntent(): Intent? = VpnService.prepare(appContext)

    override suspend fun startTunnel(profile: ServerProfile, options: TunnelOptions) {
        if (prepareIntent() != null) {
            throw VpnPermissionRequiredException()
        }

        _state.value = ConnectionState.Connecting
        activeProfile = profile

        try {
            val awgConfig = profile.toAwgConfig(options.dnsOverride)

            withContext(Dispatchers.IO) {
                backend.setState(tunnel, Tunnel.State.UP, awgConfig)
            }

            // The TUN interface being up says nothing about the server: WireGuard has no connect
            // phase, so only report Connected once the peer has actually completed a handshake.
            if (!awaitHandshake()) {
                if (_state.value != ConnectionState.Connecting) return // cancelled by the user
                withContext(Dispatchers.IO) {
                    runCatching { backend.setState(tunnel, Tunnel.State.DOWN, null) }
                }
                activeProfile = null
                _state.value = ConnectionState.Error(
                    "The server did not respond. Check that the server is online and the config is current."
                )
                return
            }

            _state.value = ConnectionState.Connected
            notificationHelper.showConnected(profile)
            startStatsPolling(profile)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start AmneziaWG tunnel", e)
            _state.value = ConnectionState.Error(e.localizedMessage ?: "Failed to establish VPN tunnel")
            stopStatsPolling()
            notificationHelper.cancel()
        }
    }

    /** Polls peer stats until a handshake is seen; false on timeout or if the attempt was cancelled. */
    private suspend fun awaitHandshake(): Boolean = withContext(Dispatchers.IO) {
        val deadline = System.currentTimeMillis() + HANDSHAKE_TIMEOUT_MS
        while (System.currentTimeMillis() < deadline && _state.value == ConnectionState.Connecting) {
            val handshaked = runCatching {
                val statistics = backend.getStatistics(tunnel)
                statistics.peers().any { statistics.peer(it)?.latestHandshakeEpochMillis()?.let { t -> t > 0 } == true }
            }.getOrDefault(false)
            if (handshaked) return@withContext true
            delay(HANDSHAKE_POLL_MS)
        }
        false
    }

    override suspend fun stopTunnel() {
        if (_state.value == ConnectionState.Disconnected) return

        _state.value = ConnectionState.Disconnecting
        stopStatsPolling()

        try {
            withContext(Dispatchers.IO) {
                backend.setState(tunnel, Tunnel.State.DOWN, null)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Error while bringing tunnel down", e)
        } finally {
            _state.value = ConnectionState.Disconnected
            _stats.value = ConnectionStats()
            notificationHelper.cancel()
            activeProfile = null
        }
    }

    private fun startStatsPolling(profile: ServerProfile) {
        stopStatsPolling()
        val connectStartTime = System.currentTimeMillis()

        statsJob = scope.launch(Dispatchers.Default) {
            var lastRx = 0L
            var lastTx = 0L

            while (isActive && _state.value is ConnectionState.Connected) {
                delay(1000)
                try {
                    val statistics = backend.getStatistics(tunnel)
                    val currentRx = statistics.totalRx()
                    val currentTx = statistics.totalTx()

                    val speedDown = if (lastRx > 0L) (currentRx - lastRx).coerceAtLeast(0L) else 0L
                    val speedUp = if (lastTx > 0L) (currentTx - lastTx).coerceAtLeast(0L) else 0L

                    lastRx = currentRx
                    lastTx = currentTx

                    val durationSecs = (System.currentTimeMillis() - connectStartTime) / 1000L

                    _stats.value = ConnectionStats(
                        bytesIn = currentRx,
                        bytesOut = currentTx,
                        bytesInPerSecond = speedDown,
                        bytesOutPerSecond = speedUp,
                        durationSeconds = durationSecs,
                        latencyMs = profile.pingMs
                    )
                } catch (e: Exception) {
                    Log.v(TAG, "Stats poll exception: ${e.message}")
                }
            }
        }
    }

    private fun stopStatsPolling() {
        statsJob?.cancel()
        statsJob = null
    }

    private inner class AwgTunnel(private val name: String) : Tunnel {
        override fun getName(): String = name

        // The backend unboxes these without a null check.
        override fun isIpv4ResolutionPreferred(): Boolean = true
        override fun isMetered(): Boolean = false

        override fun onStateChange(newState: Tunnel.State) {
            Log.d(TAG, "Tunnel state changed to: $newState")
            when (newState) {
                // Connected is set by startTunnel once a handshake is confirmed.
                Tunnel.State.UP -> Unit
                Tunnel.State.DOWN -> {
                    if (_state.value != ConnectionState.Disconnected) {
                        _state.value = ConnectionState.Disconnected
                        stopStatsPolling()
                        notificationHelper.cancel()
                    }
                }
            }
        }
    }

    companion object {
        private const val TAG = "RealTunnelService"
        private const val HANDSHAKE_TIMEOUT_MS = 15_000L
        private const val HANDSHAKE_POLL_MS = 500L
    }
}
