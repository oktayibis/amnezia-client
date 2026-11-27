@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package org.amnezia.mobile.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Shield
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.AssistChipDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CenterAlignedTopAppBar
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.SuggestionChipDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import kotlinx.coroutines.launch
import org.amnezia.core.models.ConnectionStats
import org.amnezia.core.models.ServerProfile
import org.amnezia.core.vpn.NetworkDiagnosticsTool
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import org.amnezia.mobile.BuildConfig
import org.amnezia.mobile.ui.components.ConnectButton
import org.amnezia.mobile.ui.components.ConnectionStatusCard
import org.amnezia.mobile.ui.components.LiveTrafficStatsView
import org.amnezia.mobile.ui.components.StatusPill
import org.amnezia.mobile.viewmodel.MobileAppState

@Composable
fun DashboardScreen(
    appState: MobileAppState,
    onNavigateToServers: () -> Unit,
    onOpenAddServer: () -> Unit,
    modifier: Modifier = Modifier
) {
    val connectionState by appState.connectionState.collectAsStateWithLifecycle()
    val selectedProfile by appState.selectedProfile.collectAsStateWithLifecycle()
    val stats by appState.stats.collectAsStateWithLifecycle()
    val errorMessage by appState.errorMessage.collectAsStateWithLifecycle()
    val isSimulated by appState.isSimulatedTunnel.collectAsStateWithLifecycle()
    val providesTrafficStats by appState.providesTrafficStats.collectAsStateWithLifecycle()

    val scrollState = rememberScrollState()

    BoxWithConstraints(
        modifier = modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        val screenHeight = maxHeight

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(scrollState)
                .heightIn(min = screenHeight)
                .padding(horizontal = 20.dp, vertical = 8.dp),
            verticalArrangement = Arrangement.SpaceBetween,
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // Section 1: Official Material 3 Top App Bar
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                CenterAlignedTopAppBar(
                    title = {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                text = "AWG Connect",
                                style = MaterialTheme.typography.titleLarge,
                                fontWeight = FontWeight.Bold,
                                color = MaterialTheme.colorScheme.onSurface
                            )
                            if (BuildConfig.DEBUG && isSimulated) {
                                Spacer(modifier = Modifier.width(8.dp))
                                SuggestionChip(
                                    onClick = {},
                                    label = {
                                        Text(
                                            text = "Simulated",
                                            style = MaterialTheme.typography.labelSmall
                                        )
                                    },
                                    colors = SuggestionChipDefaults.suggestionChipColors(
                                        containerColor = MaterialTheme.colorScheme.tertiaryContainer,
                                        labelColor = MaterialTheme.colorScheme.onTertiaryContainer
                                    ),
                                    border = null
                                )
                            }
                        }
                    },
                    actions = {
                        IconButton(onClick = { appState.importFromClipboard() }) {
                            Icon(
                                imageVector = Icons.Default.ContentPaste,
                                contentDescription = "Import from clipboard",
                                tint = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                        IconButton(onClick = onOpenAddServer) {
                            Icon(
                                imageVector = Icons.Default.Add,
                                contentDescription = "Add server",
                                tint = MaterialTheme.colorScheme.primary
                            )
                        }
                    },
                    colors = TopAppBarDefaults.centerAlignedTopAppBarColors(
                        containerColor = MaterialTheme.colorScheme.background
                    )
                )

                // Error message banner using M3 ErrorContainer
                AnimatedVisibility(
                    visible = errorMessage != null,
                    enter = fadeIn(),
                    exit = fadeOut()
                ) {
                    errorMessage?.let { error ->
                        Spacer(modifier = Modifier.height(4.dp))
                        Card(
                            modifier = Modifier.fillMaxWidth(),
                            shape = RoundedCornerShape(12.dp),
                            colors = CardDefaults.cardColors(
                                containerColor = MaterialTheme.colorScheme.errorContainer,
                                contentColor = MaterialTheme.colorScheme.onErrorContainer
                            )
                        ) {
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(14.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(
                                    imageVector = Icons.Default.ErrorOutline,
                                    contentDescription = null,
                                    tint = MaterialTheme.colorScheme.error,
                                    modifier = Modifier.size(20.dp)
                                )
                                Spacer(modifier = Modifier.width(10.dp))
                                Text(
                                    text = error,
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onErrorContainer,
                                    modifier = Modifier.weight(1f)
                                )
                                IconButton(
                                    onClick = { appState.clearErrorMessage() },
                                    modifier = Modifier.size(28.dp)
                                ) {
                                    Icon(
                                        imageVector = Icons.Default.Close,
                                        contentDescription = "Dismiss",
                                        tint = MaterialTheme.colorScheme.onErrorContainer,
                                        modifier = Modifier.size(16.dp)
                                    )
                                }
                            }
                        }
                    }
                }
            }

            // Section 2: Center Hero Area (StatusPill + ConnectButton + Subtitle)
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 16.dp),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                StatusPill(state = connectionState)

                Spacer(modifier = Modifier.height(28.dp))

                ConnectButton(
                    connectionState = connectionState,
                    onClick = { appState.toggleConnection() }
                )

                Spacer(modifier = Modifier.height(20.dp))

                Text(
                    text = when {
                        connectionState.isConnected -> "Tunnel is active & secured"
                        connectionState.isBusy -> "Establishing tunnel..."
                        else -> "Tap power button to connect"
                    },
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }

            // Section 3: Bottom Section (Security telemetry chips + Traffic Stats + Server Card)
            var showDiagnosticsDialog by remember { mutableStateOf(false) }

            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                // Live traffic meters
                if (providesTrafficStats) {
                    LiveTrafficStatsView(
                        stats = stats,
                        onOpenDiagnostics = { showDiagnosticsDialog = true }
                    )
                    Spacer(modifier = Modifier.height(14.dp))
                }

                // Official M3 AssistChips for security features & Speedtest tool
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(bottom = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.CenterHorizontally)
                ) {
                    M3SecurityChip(icon = Icons.Default.Shield, label = "Zero logs")
                    M3SecurityChip(icon = Icons.Default.Bolt, label = "AmneziaWG")
                    M3SecurityChip(
                        icon = Icons.Default.Speed,
                        label = "Speedtest",
                        onClick = { showDiagnosticsDialog = true }
                    )
                }

                // Selected Server Card
                ConnectionStatusCard(
                    profile = selectedProfile,
                    onClick = onNavigateToServers
                )

                Spacer(modifier = Modifier.height(16.dp))
            }

            if (showDiagnosticsDialog) {
                MobileDiagnosticsDialog(
                    appState = appState,
                    stats = stats,
                    profile = selectedProfile,
                    onDismiss = { showDiagnosticsDialog = false }
                )
            }
        }
    }
}

/**
 * Official Material 3 AssistChip for security indicators
 */
@Composable
private fun M3SecurityChip(
    icon: ImageVector,
    label: String,
    onClick: () -> Unit = {},
    modifier: Modifier = Modifier
) {
    AssistChip(
        onClick = onClick,
        label = {
            Text(
                text = label,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        },
        leadingIcon = {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(16.dp)
            )
        },
        colors = AssistChipDefaults.assistChipColors(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow
        ),
        border = AssistChipDefaults.assistChipBorder(
            enabled = true,
            borderColor = MaterialTheme.colorScheme.outlineVariant
        ),
        modifier = modifier
    )
}

@Composable
private fun MobileDiagnosticsDialog(
    appState: MobileAppState,
    stats: ConnectionStats,
    profile: ServerProfile?,
    onDismiss: () -> Unit
) {
    val scope = rememberCoroutineScope()
    var snapshot by remember { mutableStateOf<NetworkDiagnosticsTool.DiagnosticsSnapshot?>(null) }
    var isDiagnosing by remember { mutableStateOf(false) }
    var isSpeedtesting by remember { mutableStateOf(false) }
    var phaseText by remember { mutableStateOf<String?>(null) }
    var liveDownMbps by remember { mutableStateOf<Double?>(null) }
    var liveUpMbps by remember { mutableStateOf<Double?>(null) }
    var speedtestResult by remember { mutableStateOf<NetworkDiagnosticsTool.SpeedtestResult?>(null) }

    fun refreshDiagnostics() {
        if (isDiagnosing) return
        isDiagnosing = true
        scope.launch {
            try {
                snapshot = NetworkDiagnosticsTool.runDiagnostics(
                    profile = profile,
                    dnsOverride = appState.settings.resolveDnsOverride()
                )
            } finally {
                isDiagnosing = false
            }
        }
    }

    fun startSpeedtest() {
        if (isSpeedtesting) return
        isSpeedtesting = true
        speedtestResult = null
        liveDownMbps = null
        liveUpMbps = null
        scope.launch {
            try {
                val res = NetworkDiagnosticsTool.runSpeedtest(
                    profile = profile,
                    dnsOverride = appState.settings.resolveDnsOverride()
                ) { phase, down, up ->
                    phaseText = phase
                    if (down != null) liveDownMbps = down
                    if (up != null) liveUpMbps = up
                }
                speedtestResult = res
                snapshot = NetworkDiagnosticsTool.DiagnosticsSnapshot(
                    publicIp = res.publicIp ?: snapshot?.publicIp,
                    country = res.country ?: snapshot?.country,
                    colo = res.colo ?: snapshot?.colo,
                    pingMs = res.pingMs ?: snapshot?.pingMs,
                    jitterMs = res.jitterMs ?: snapshot?.jitterMs,
                    packetLossPercent = res.packetLossPercent,
                    dnsLatencyMs = res.dnsLatencyMs ?: snapshot?.dnsLatencyMs
                )
            } finally {
                isSpeedtesting = false
            }
        }
    }

    LaunchedEffect(Unit) {
        refreshDiagnostics()
    }

    val downMbps = speedtestResult?.downloadMbps ?: liveDownMbps
    val upMbps = speedtestResult?.uploadMbps ?: liveUpMbps
    val pingMs = speedtestResult?.pingMs ?: snapshot?.pingMs ?: stats.latencyMs
    val jitterMs = speedtestResult?.jitterMs ?: snapshot?.jitterMs ?: stats.jitterMs
    val lossPct = speedtestResult?.packetLossPercent ?: snapshot?.packetLossPercent ?: 0

    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = MaterialTheme.colorScheme.surfaceContainerHigh,
        title = {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = Icons.Default.Speed,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "Speedtest & Diagnostics",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold
                )
            }
        },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (isDiagnosing || isSpeedtesting) {
                    Text(
                        text = phaseText ?: "Probing tunnel metrics...",
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.primary
                    )
                }

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceEvenly
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("DOWNLOAD", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(
                            text = downMbps?.let { String.format("%.1f Mbps", it) } ?: "-- Mbps",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.primary
                        )
                    }
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("UPLOAD", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(
                            text = upMbps?.let { String.format("%.1f Mbps", it) } ?: "-- Mbps",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            color = MaterialTheme.colorScheme.tertiary
                        )
                    }
                }

                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

                val exitIp = snapshot?.publicIp ?: if (isDiagnosing) "Checking..." else (profile?.host ?: "--")
                val exitLoc = listOfNotNull(snapshot?.country, snapshot?.colo)
                    .filter { it.isNotEmpty() && it != "--" }
                    .joinToString(" • ")
                    .ifEmpty { "--" }

                DiagInfoRow("Ping / Jitter / Loss", "${pingMs?.let { "${it}ms" } ?: "--"} / ${jitterMs?.let { "${it}ms" } ?: "--"} / $lossPct%")
                DiagInfoRow("DNS Latency", snapshot?.dnsLatencyMs?.let { "${it}ms" } ?: "--")
                DiagInfoRow("Public Exit IP", "$exitIp ($exitLoc)")
                DiagInfoRow("Tunnel IP & MTU", "${profile?.clientIp ?: "--"} • MTU ${profile?.mtu ?: 1280}")
                DiagInfoRow("Last Handshake", stats.formattedHandshakeAge)
                DiagInfoRow("Session Traffic", "↓ ${stats.formattedBytesIn} • ↑ ${stats.formattedBytesOut}")
            }
        },
        confirmButton = {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                TextButton(onClick = { refreshDiagnostics() }, enabled = !isDiagnosing && !isSpeedtesting) {
                    Icon(imageVector = Icons.Default.Refresh, contentDescription = null, modifier = Modifier.size(16.dp))
                    Spacer(modifier = Modifier.width(4.dp))
                    Text("Refresh")
                }
                Button(onClick = { startSpeedtest() }, enabled = !isSpeedtesting) {
                    Text(if (isSpeedtesting) "Testing..." else "Run Speedtest")
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Close")
            }
        }
    )
}

@Composable
private fun DiagInfoRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = value,
            style = MaterialTheme.typography.bodySmall,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface
        )
    }
}

