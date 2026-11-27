package org.amnezia.tv.ui.screens

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.ArrowDownward
import androidx.compose.material.icons.filled.ArrowUpward
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.NetworkCheck
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import kotlinx.coroutines.launch
import org.amnezia.core.vpn.NetworkDiagnosticsTool
import org.amnezia.tv.ui.components.TvFocusableButton
import org.amnezia.tv.ui.theme.SurfaceBorder
import org.amnezia.tv.ui.theme.SurfaceDark
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import org.amnezia.core.models.ConnectionState
import org.amnezia.core.models.ConnectionStats
import org.amnezia.core.models.ProtocolType
import org.amnezia.core.models.ServerProfile
import org.amnezia.tv.BuildConfig
import org.amnezia.tv.ui.components.TvConnectButton
import org.amnezia.tv.ui.components.TvFocusableCard
import org.amnezia.tv.ui.theme.AwgPurple
import org.amnezia.tv.ui.theme.ConnectingOrange
import org.amnezia.tv.ui.theme.CyberGreen
import org.amnezia.tv.ui.theme.DarkBackground
import org.amnezia.tv.ui.theme.ErrorRed
import org.amnezia.tv.ui.theme.NeonCyan
import org.amnezia.tv.ui.theme.SurfaceCard
import org.amnezia.tv.ui.theme.TextPrimary
import org.amnezia.tv.ui.theme.TextSecondary
import org.amnezia.tv.viewmodel.TvAppState

@Composable
fun TvDashboardScreen(
    appState: TvAppState,
    onNavigateToServers: () -> Unit,
    modifier: Modifier = Modifier
) {
    val connectionState by appState.connectionState.collectAsStateWithLifecycle()
    val selectedProfile by appState.selectedProfile.collectAsStateWithLifecycle()
    val stats by appState.stats.collectAsStateWithLifecycle()
    val isSimulated by appState.isSimulatedTunnel.collectAsStateWithLifecycle()
    val providesTrafficStats by appState.providesTrafficStats.collectAsStateWithLifecycle()
    val errorMessage by appState.errorMessage.collectAsStateWithLifecycle()

    Row(
        modifier = modifier
            .fillMaxSize()
            .background(DarkBackground)
            .padding(horizontal = 48.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.spacedBy(36.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Left Column: Power Connect Button & Status
        Column(
            modifier = Modifier
                .weight(1f)
                .fillMaxHeight(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            TvStatusPill(state = connectionState)

            Spacer(modifier = Modifier.height(16.dp))

            TvConnectButton(
                connectionState = connectionState,
                onClick = { appState.toggleConnection() }
            )

            val errorText = (connectionState as? ConnectionState.Error)?.message ?: errorMessage
            if (errorText != null) {
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    text = errorText,
                    color = ErrorRed,
                    fontSize = 13.sp,
                    textAlign = TextAlign.Center,
                    maxLines = 3,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.width(360.dp)
                )
            }

            if (BuildConfig.DEBUG && isSimulated) {
                Spacer(modifier = Modifier.height(10.dp))
                Box(
                    modifier = Modifier
                        .clip(RoundedCornerShape(6.dp))
                        .background(ConnectingOrange.copy(alpha = 0.15f))
                        .border(1.dp, ConnectingOrange.copy(alpha = 0.3f), RoundedCornerShape(6.dp))
                        .padding(horizontal = 8.dp, vertical = 3.dp)
                ) {
                    Text(
                        text = "SIMULATED TUNNEL ACTIVE",
                        color = ConnectingOrange,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold
                    )
                }
            }
        }

        // Right Column: Active Server & Live Speed Gauges
        Column(
            modifier = Modifier
                .weight(1.2f)
                .fillMaxHeight(),
            verticalArrangement = Arrangement.Center
        ) {
            // Selected Server Card
            Text(
                text = "ACTIVE SERVER",
                color = TextSecondary,
                fontSize = 11.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = 1.2.sp,
                modifier = Modifier.padding(start = 4.dp, bottom = 6.dp)
            )

            TvFocusableCard(onClick = onNavigateToServers) { isFocused ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Box(
                        modifier = Modifier
                            .size(46.dp)
                            .clip(CircleShape)
                            .background(if (isFocused) CyberGreen.copy(alpha = 0.25f) else Color(0x1AFFFFFF)),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            imageVector = Icons.Default.Dns,
                            contentDescription = null,
                            tint = if (isFocused) CyberGreen else TextPrimary,
                            modifier = Modifier.size(24.dp)
                        )
                    }

                    Spacer(modifier = Modifier.width(14.dp))

                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = selectedProfile?.name ?: "No Server Selected",
                            color = TextPrimary,
                            fontSize = 17.sp,
                            fontWeight = FontWeight.Bold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis
                        )
                        Spacer(modifier = Modifier.height(3.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            val badgeColor = when (selectedProfile?.protocol) {
                                ProtocolType.AMNEZIA_WG -> AwgPurple
                                ProtocolType.WIREGUARD -> NeonCyan
                                else -> CyberGreen
                            }
                            Box(
                                modifier = Modifier
                                    .clip(RoundedCornerShape(4.dp))
                                    .background(badgeColor.copy(alpha = 0.2f))
                                    .padding(horizontal = 6.dp, vertical = 2.dp)
                            ) {
                                Text(
                                    text = selectedProfile?.protocol?.displayName ?: "Config Required",
                                    color = badgeColor,
                                    fontSize = 10.sp,
                                    fontWeight = FontWeight.Bold
                                )
                            }
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                text = selectedProfile?.let { "${it.host}:${it.port}" } ?: "Press to add or paste server",
                                color = TextSecondary,
                                fontSize = 12.sp,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis
                            )
                        }
                    }

                    Icon(
                        imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                        contentDescription = "Switch Server",
                        tint = if (isFocused) CyberGreen else TextSecondary,
                        modifier = Modifier.size(24.dp)
                    )
                }
            }

            Spacer(modifier = Modifier.height(14.dp))

            // Live network metrics are shown only when the backend reports real byte counters.
            if (providesTrafficStats) {
                var showDiagnosticsDialog by remember { mutableStateOf(false) }

                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(start = 4.dp, bottom = 6.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text(
                        text = "NETWORK METRICS",
                        color = TextSecondary,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = 1.2.sp
                    )
                    Text(
                        text = "PRESS [OK] ON METRICS FOR SPEEDTEST & TOOLS",
                        color = CyberGreen,
                        fontSize = 10.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                }

                TvMetricsCard(
                    stats = stats,
                    onClick = { showDiagnosticsDialog = true }
                )

                Spacer(modifier = Modifier.height(10.dp))

                TvFocusableButton(
                    text = "SPEEDTEST & NETWORK TOOLS",
                    icon = Icons.Default.Speed,
                    isPrimary = false,
                    onClick = { showDiagnosticsDialog = true },
                    modifier = Modifier.fillMaxWidth(),
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 10.dp)
                )

                if (showDiagnosticsDialog) {
                    TvDiagnosticsDialog(
                        appState = appState,
                        stats = stats,
                        profile = selectedProfile,
                        onDismiss = { showDiagnosticsDialog = false }
                    )
                }
            }
        }
    }
}

@Composable
private fun TvStatusPill(state: ConnectionState) {
    val infiniteTransition = rememberInfiniteTransition(label = "pulse")
    val pulseAlpha by infiniteTransition.animateFloat(
        initialValue = 0.3f,
        targetValue = 1.0f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 800, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "pulseAlpha"
    )

    val (statusColor, statusText, isPulsing) = when (state) {
        is ConnectionState.Connected -> Triple(CyberGreen, "CONNECTED", false)
        is ConnectionState.Connecting -> Triple(ConnectingOrange, "CONNECTING...", true)
        is ConnectionState.Reconnecting -> Triple(ConnectingOrange, "RECONNECTING...", true)
        is ConnectionState.Disconnecting -> Triple(ConnectingOrange, "DISCONNECTING...", true)
        is ConnectionState.Error -> Triple(ErrorRed, "ERROR", false)
        is ConnectionState.Disconnected -> Triple(TextSecondary, "DISCONNECTED", false)
    }

    Row(
        modifier = Modifier
            .clip(RoundedCornerShape(50.dp))
            .background(statusColor.copy(alpha = 0.12f))
            .border(1.dp, statusColor.copy(alpha = 0.3f), RoundedCornerShape(50.dp))
            .padding(horizontal = 20.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(10.dp)
                .then(if (isPulsing) Modifier.alpha(pulseAlpha) else Modifier)
                .clip(CircleShape)
                .background(statusColor)
        )
        Spacer(modifier = Modifier.width(10.dp))
        Text(
            text = statusText,
            color = statusColor,
            fontSize = 14.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = 1.5.sp
        )
    }
}

@Composable
private fun TvMetricsCard(
    stats: ConnectionStats,
    onClick: () -> Unit = {}
) {
    TvFocusableCard(onClick = onClick) { _ ->
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 18.dp, vertical = 14.dp)
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                TvMetricItem(
                    icon = Icons.Default.NetworkCheck,
                    label = "PING",
                    value = stats.latencyMs?.let { "${it}ms" } ?: "--",
                    color = CyberGreen
                )
                TvMetricItem(
                    icon = Icons.Default.ArrowDownward,
                    label = "DOWNLOAD",
                    value = stats.formattedDownloadSpeed,
                    color = CyberGreen
                )
                TvMetricItem(
                    icon = Icons.Default.ArrowUpward,
                    label = "UPLOAD",
                    value = stats.formattedUploadSpeed,
                    color = NeonCyan
                )
                TvMetricItem(
                    icon = Icons.Default.Timer,
                    label = "DURATION",
                    value = stats.formattedDuration,
                    color = TextSecondary
                )
            }

            Spacer(modifier = Modifier.height(10.dp))
            HorizontalDivider(color = Color(0x1AFFFFFF), thickness = 1.dp)
            Spacer(modifier = Modifier.height(8.dp))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly
            ) {
                TvSubMetricItem(
                    label = "JITTER",
                    value = stats.jitterMs?.let { "${it}ms" } ?: "--"
                )
                TvSubMetricItem(
                    label = "TOTAL DOWN",
                    value = stats.formattedBytesIn
                )
                TvSubMetricItem(
                    label = "TOTAL UP",
                    value = stats.formattedBytesOut
                )
                TvSubMetricItem(
                    label = "HANDSHAKE",
                    value = stats.formattedHandshakeAge
                )
            }
        }
    }
}

@Composable
private fun TvSubMetricItem(label: String, value: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(text = label, color = TextSecondary, fontSize = 9.sp, fontWeight = FontWeight.SemiBold)
        Spacer(modifier = Modifier.height(2.dp))
        Text(text = value, color = TextPrimary, fontSize = 12.sp, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun TvDiagnosticsDialog(
    appState: TvAppState,
    stats: ConnectionStats,
    profile: ServerProfile?,
    onDismiss: () -> Unit
) {
    val scope = rememberCoroutineScope()
    var snapshot by remember { mutableStateOf<NetworkDiagnosticsTool.DiagnosticsSnapshot?>(null) }
    var isDiagnosing by remember { mutableStateOf(false) }
    var isSpeedtesting by remember { mutableStateOf(false) }
    var speedtestPhase by remember { mutableStateOf<String?>(null) }
    var liveDownMbps by remember { mutableStateOf<Double?>(null) }
    var liveUpMbps by remember { mutableStateOf<Double?>(null) }
    var speedtestResult by remember { mutableStateOf<NetworkDiagnosticsTool.SpeedtestResult?>(null) }

    fun triggerDiagnostics() {
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

    fun triggerSpeedtest() {
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
                    speedtestPhase = phase
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
        triggerDiagnostics()
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        properties = androidx.compose.ui.window.DialogProperties(usePlatformDefaultWidth = false),
        modifier = Modifier.width(720.dp),
        containerColor = SurfaceDark,
        title = {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(imageVector = Icons.Default.Speed, contentDescription = null, tint = CyberGreen, modifier = Modifier.size(22.dp))
                    Spacer(modifier = Modifier.width(10.dp))
                    Text("SPEEDTEST & CONNECTION DIAGNOSTICS", color = TextPrimary, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                }
                if (isDiagnosing || isSpeedtesting) {
                    Text(
                        text = speedtestPhase ?: "Probing tunnel...",
                        color = ConnectingOrange,
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }
        },
        text = {
            Column(modifier = Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                // Speedtest Result / Live Gauges Box
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .background(SurfaceCard)
                        .border(1.dp, SurfaceBorder, RoundedCornerShape(12.dp))
                        .padding(14.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceEvenly
                    ) {
                        val downVal = speedtestResult?.downloadMbps ?: liveDownMbps
                        val upVal = speedtestResult?.uploadMbps ?: liveUpMbps
                        val pingVal = speedtestResult?.pingMs ?: snapshot?.pingMs ?: stats.latencyMs
                        val jitterVal = speedtestResult?.jitterMs ?: snapshot?.jitterMs ?: stats.jitterMs
                        val lossVal = speedtestResult?.packetLossPercent ?: snapshot?.packetLossPercent ?: 0

                        TvMetricItem(
                            icon = Icons.Default.ArrowDownward,
                            label = "SPEEDTEST DOWN",
                            value = downVal?.let { String.format("%.1f Mbps", it) } ?: "-- Mbps",
                            color = CyberGreen
                        )
                        TvMetricItem(
                            icon = Icons.Default.ArrowUpward,
                            label = "SPEEDTEST UP",
                            value = upVal?.let { String.format("%.1f Mbps", it) } ?: "-- Mbps",
                            color = NeonCyan
                        )
                        TvMetricItem(
                            icon = Icons.Default.NetworkCheck,
                            label = "PING / JITTER",
                            value = "${pingVal?.let { "${it}ms" } ?: "--"} / ${jitterVal?.let { "${it}ms" } ?: "--"}",
                            color = CyberGreen
                        )
                        TvMetricItem(
                            icon = Icons.Default.Public,
                            label = "PACKET LOSS",
                            value = "$lossVal%",
                            color = if (lossVal == 0) CyberGreen else ConnectingOrange
                        )
                    }
                }

                // Detailed Connection & Exit Node Info
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(12.dp))
                        .background(SurfaceCard)
                        .border(1.dp, SurfaceBorder, RoundedCornerShape(12.dp))
                        .padding(14.dp)
                ) {
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        val exitIp = snapshot?.publicIp ?: if (isDiagnosing) "Checking..." else (profile?.host ?: "--")
                        val exitLoc = listOfNotNull(snapshot?.country, snapshot?.colo)
                            .filter { it.isNotEmpty() && it != "--" }
                            .joinToString(" • ")
                            .ifEmpty { "--" }
                        val dnsStr = snapshot?.dnsLatencyMs?.let { "${it}ms" } ?: "--"
                        val protoStr = if (profile?.awg3 != null) "AmneziaWG 3.1" else profile?.protocol?.displayName ?: "--"

                        TvDiagRow("Public Exit IP & Edge", "$exitIp ($exitLoc)")
                        TvDiagRow("Protocol & Endpoint", "$protoStr  •  ${profile?.endpointString ?: "--"}")
                        TvDiagRow("Tunnel IP & MTU", "${profile?.clientIp ?: "--"}  •  MTU ${profile?.mtu ?: 1280}  •  Keepalive ${profile?.persistentKeepaliveValue ?: "25"}s")
                        TvDiagRow("DNS Latency & Handshake", "DNS $dnsStr  •  Handshake ${stats.formattedHandshakeAge}")
                        TvDiagRow("Session Traffic", "Downloaded ${stats.formattedBytesIn}  •  Uploaded ${stats.formattedBytesOut}")
                    }
                }
            }
        },
        confirmButton = {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                TvFocusableButton(
                    text = if (isSpeedtesting) "RUNNING SPEEDTEST..." else "RUN SPEEDTEST",
                    icon = Icons.Default.Speed,
                    isPrimary = true,
                    onClick = { triggerSpeedtest() },
                    contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp)
                )
                TvFocusableButton(
                    text = "REFRESH INFO",
                    icon = Icons.Default.Refresh,
                    isPrimary = false,
                    onClick = { triggerDiagnostics() },
                    contentPadding = PaddingValues(horizontal = 14.dp, vertical = 8.dp)
                )
            }
        },
        dismissButton = {
            TvFocusableButton(
                text = "CLOSE",
                isPrimary = false,
                onClick = onDismiss,
                contentPadding = PaddingValues(horizontal = 14.dp, vertical = 8.dp)
            )
        }
    )
}

@Composable
private fun TvDiagRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(text = label, color = TextSecondary, fontSize = 12.sp)
        Text(text = value, color = TextPrimary, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun TvMetricItem(
    icon: ImageVector,
    label: String,
    value: String,
    color: Color
) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(imageVector = icon, contentDescription = null, tint = color, modifier = Modifier.size(15.dp))
            Spacer(modifier = Modifier.width(4.dp))
            Text(text = label, color = TextSecondary, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
        }
        Spacer(modifier = Modifier.height(6.dp))
        Text(text = value, color = TextPrimary, fontSize = 16.sp, fontWeight = FontWeight.Bold)
    }
}
