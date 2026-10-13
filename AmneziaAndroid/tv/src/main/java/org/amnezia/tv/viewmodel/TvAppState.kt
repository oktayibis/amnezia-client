package org.amnezia.tv.viewmodel

import android.content.Context
import android.content.Intent
import android.net.Uri
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import org.amnezia.core.models.ConnectionState
import org.amnezia.core.models.ConnectionStats
import org.amnezia.core.models.ServerProfile
import org.amnezia.core.parsers.AmneziaUrlDecoder
import org.amnezia.core.parsers.WgQuickConfigParser
import org.amnezia.core.storage.AppSettings
import org.amnezia.core.storage.ProfileStorage
import org.amnezia.core.vpn.MockTunnelService
import org.amnezia.core.vpn.RealTunnelService
import org.amnezia.core.vpn.TunnelOptions
import org.amnezia.core.vpn.VpnPermissionRequiredException
import org.amnezia.core.vpn.VpnTunnelService
import org.amnezia.tv.BuildConfig

@OptIn(ExperimentalCoroutinesApi::class)
class TvAppState(
    private val context: Context,
    private val scope: CoroutineScope = CoroutineScope(Dispatchers.Main)
) {
    private val storage = ProfileStorage(context)
    val settings = AppSettings(context)

    private val realTunnel = RealTunnelService(context)
    private val mockTunnel: MockTunnelService? = if (BuildConfig.DEBUG) MockTunnelService() else null

    private val _tunnelService = MutableStateFlow(selectTunnel(settings.simulatedTunnel))
    private val tunnelService: VpnTunnelService get() = _tunnelService.value

    val connectionState: StateFlow<ConnectionState> = _tunnelService
        .flatMapLatest { it.state }
        .stateIn(scope, SharingStarted.Eagerly, ConnectionState.Disconnected)

    val stats: StateFlow<ConnectionStats> = _tunnelService
        .flatMapLatest { it.stats }
        .stateIn(scope, SharingStarted.Eagerly, ConnectionStats())

    val providesTrafficStats: StateFlow<Boolean> = _tunnelService
        .map { it.providesTrafficStats }
        .stateIn(scope, SharingStarted.Eagerly, tunnelService.providesTrafficStats)

    /** Debug builds only. Always false in release. */
    val isSimulatedTunnel: StateFlow<Boolean> = _tunnelService
        .map { it is MockTunnelService }
        .stateIn(scope, SharingStarted.Eagerly, tunnelService is MockTunnelService)

    private val _profiles = MutableStateFlow<List<ServerProfile>>(emptyList())
    val profiles: StateFlow<List<ServerProfile>> = _profiles.asStateFlow()

    private val _selectedProfile = MutableStateFlow<ServerProfile?>(null)
    val selectedProfile: StateFlow<ServerProfile?> = _selectedProfile.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val _pendingVpnPermission = MutableStateFlow<Intent?>(null)
    val pendingVpnPermission: StateFlow<Intent?> = _pendingVpnPermission.asStateFlow()

    init {
        loadProfiles()
    }

    private fun selectTunnel(simulated: Boolean): VpnTunnelService {
        val mock = mockTunnel
        return if (BuildConfig.DEBUG && simulated && mock != null) mock else realTunnel
    }

    fun clearErrorMessage() {
        _errorMessage.value = null
    }

    fun setSimulatedTunnel(enabled: Boolean) {
        if (!BuildConfig.DEBUG) return
        settings.simulatedTunnel = enabled
        scope.launch {
            runCatching { tunnelService.stopTunnel() }
            _tunnelService.value = selectTunnel(enabled)
        }
    }

    fun loadProfiles() {
        val loaded = storage.loadProfiles()

        _profiles.value = loaded

        if (loaded.isEmpty()) {
            _selectedProfile.value = null
            return
        }

        val storedSelected = storage.selectedProfile()
        if (storedSelected != null && loaded.any { it.id == storedSelected.id }) {
            _selectedProfile.value = storedSelected
        } else {
            val first = loaded.first()
            _selectedProfile.value = first
            storage.selectProfile(first.id)
        }
    }

    private fun currentOptions() = TunnelOptions(dnsOverride = settings.resolveDnsOverride())

    fun selectProfile(profile: ServerProfile) {
        _selectedProfile.value = profile
        storage.selectProfile(profile.id)

        if (connectionState.value.isConnected) {
            scope.launch { startTunnelSafely(profile) }
        }
    }

    fun addProfile(profile: ServerProfile) {
        storage.addProfile(profile)
        loadProfiles()
        selectProfile(profile)
    }

    fun deleteProfile(profile: ServerProfile) {
        if (_selectedProfile.value?.id == profile.id) {
            _selectedProfile.value = null
            if (connectionState.value.isConnected) {
                scope.launch { runCatching { tunnelService.stopTunnel() } }
            }
        }
        storage.deleteProfile(profile.id)
        loadProfiles()
    }

    fun toggleConnection() {
        _errorMessage.value = null
        scope.launch {
            if (connectionState.value.isConnected || connectionState.value.isBusy) {
                runCatching { tunnelService.stopTunnel() }
                    .onFailure { _errorMessage.value = it.localizedMessage ?: "Failed to disconnect" }
            } else {
                val profile = _selectedProfile.value
                if (profile == null) {
                    _errorMessage.value = "No server selected. Please add or select a server first."
                    return@launch
                }
                startTunnelSafely(profile)
            }
        }
    }

    private suspend fun startTunnelSafely(profile: ServerProfile) {
        try {
            tunnelService.startTunnel(profile, currentOptions())
        } catch (e: VpnPermissionRequiredException) {
            _pendingVpnPermission.value = realTunnel.prepareIntent()
        } catch (e: Exception) {
            _errorMessage.value = e.localizedMessage ?: "Connection error"
        }
    }

    fun onVpnPermissionResult(granted: Boolean) {
        _pendingVpnPermission.value = null
        if (granted) {
            toggleConnection()
        } else {
            _errorMessage.value = "VPN permission was denied. Allow it in the system dialog to connect."
        }
    }

    fun connectOnLaunchIfNeeded() {
        if (settings.connectOnLaunch &&
            !connectionState.value.isConnected &&
            !connectionState.value.isBusy &&
            _selectedProfile.value != null
        ) {
            toggleConnection()
        }
    }

    fun importFromText(input: String): ServerProfile {
        val trimmed = input.trim()
        val profile = when {
            trimmed.lowercase().startsWith("vpn://") -> AmneziaUrlDecoder.decode(trimmed)
            trimmed.contains("[Interface]") && trimmed.contains("[Peer]") -> WgQuickConfigParser.parse(trimmed)
            trimmed.startsWith("{") -> AmneziaUrlDecoder.decode(trimmed)
            else -> AmneziaUrlDecoder.decode("vpn://$trimmed")
        }
        profile.rawConfig = trimmed
        addProfile(profile)
        return profile
    }

    fun importFromUri(uri: Uri): ServerProfile {
        val content = context.contentResolver.openInputStream(uri)?.use {
            it.bufferedReader().readText()
        } ?: throw IllegalArgumentException("Could not read file content")
        return importFromText(content)
    }
}
