package org.amnezia.tv

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Dns
import androidx.compose.material.icons.filled.PowerSettingsNew
import androidx.compose.material.icons.filled.Settings
import androidx.compose.foundation.BorderStroke
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import org.amnezia.tv.ui.screens.TvDashboardScreen
import org.amnezia.tv.ui.screens.TvPrivacyNoticeScreen
import org.amnezia.tv.ui.screens.TvServersScreen
import org.amnezia.tv.ui.screens.TvSettingsScreen
import org.amnezia.tv.ui.theme.AmneziaTvTheme
import org.amnezia.tv.ui.theme.CyberGreen
import org.amnezia.tv.ui.theme.DarkBackground
import org.amnezia.tv.ui.theme.SurfaceBorder
import org.amnezia.tv.ui.theme.SurfaceCard
import org.amnezia.tv.ui.theme.TextPrimary
import org.amnezia.tv.ui.theme.TextSecondary
import org.amnezia.tv.viewmodel.TvAppState

class TvMainActivity : ComponentActivity() {

    private lateinit var appState: TvAppState

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        appState = (application as AmneziaTvApp).appState
        handleIntent(intent)

        setContent {
            AmneziaTvTheme {
                var privacyAccepted by remember { mutableStateOf(appState.settings.privacyNoticeAccepted) }

                if (!privacyAccepted) {
                    // Google Play VpnService policy: disclose data handling before any VPN use.
                    TvPrivacyNoticeScreen(onAccept = {
                        appState.settings.privacyNoticeAccepted = true
                        privacyAccepted = true
                    })
                } else {
                    TvAppScaffold(appState = appState)
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        val uri = intent?.data ?: return
        val urlString = uri.toString()
        val payload = when {
            urlString.startsWith("vpn://") -> urlString
            urlString.startsWith("awgconnect://") -> urlString.removePrefix("awgconnect://")
            else -> return
        }
        try {
            appState.importFromText(payload)
        } catch (_: Exception) {
        }
    }
}

private enum class TvTab(val title: String, val icon: ImageVector) {
    DASHBOARD("CONNECT", Icons.Default.PowerSettingsNew),
    SERVERS("SERVERS", Icons.Default.Dns),
    SETTINGS("SETTINGS", Icons.Default.Settings)
}

@Composable
private fun TvAppScaffold(appState: TvAppState) {
    var selectedTab by remember { mutableIntStateOf(0) }
    val pendingVpnPermission by appState.pendingVpnPermission.collectAsStateWithLifecycle()

    // System VPN consent dialog (VpnService.prepare) — launched when the state layer asks for it.
    val vpnPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.StartActivityForResult()
    ) { result ->
        appState.onVpnPermissionResult(result.resultCode == Activity.RESULT_OK)
    }
    LaunchedEffect(pendingVpnPermission) {
        pendingVpnPermission?.let { vpnPermissionLauncher.launch(it) }
    }
    LaunchedEffect(Unit) {
        appState.connectOnLaunchIfNeeded()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(DarkBackground)
    ) {
        // Top TV Header Bar
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(SurfaceCard.copy(alpha = 0.5f))
                .border(width = 1.dp, color = SurfaceBorder)
                .padding(horizontal = 48.dp, vertical = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Brand Title
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = "AWG CONNECT",
                    color = CyberGreen,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Black,
                    letterSpacing = 2.sp
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = "TV",
                    color = TextPrimary,
                    fontSize = 20.sp,
                    fontWeight = FontWeight.Light,
                    letterSpacing = 1.sp
                )
            }

            // Top Navigation Tabs
            Row(
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                TvTab.entries.forEachIndexed { index, tab ->
                    TvNavTabButton(
                        tab = tab,
                        isSelected = selectedTab == index,
                        onClick = { selectedTab = index }
                    )
                }
            }
        }

        // Content Body
        Box(
            modifier = Modifier
                .fillMaxSize()
                .weight(1f)
        ) {
            when (selectedTab) {
                0 -> TvDashboardScreen(
                    appState = appState,
                    onNavigateToServers = { selectedTab = 1 }
                )
                1 -> TvServersScreen(appState = appState)
                2 -> TvSettingsScreen(appState = appState)
            }
        }
    }
}

@Composable
private fun TvNavTabButton(
    tab: TvTab,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    var isFocused by remember { mutableStateOf(false) }

    val scale by androidx.compose.animation.core.animateFloatAsState(
        targetValue = if (isFocused) 1.08f else 1.0f,
        animationSpec = androidx.compose.animation.core.tween(150),
        label = "tabScale"
    )

    val backgroundColor by animateColorAsState(
        targetValue = when {
            isFocused && isSelected -> CyberGreen
            isFocused -> Color(0xFF28364D)
            isSelected -> Color(0x1FFFFFFF)
            else -> Color.Transparent
        },
        animationSpec = androidx.compose.animation.core.tween(150),
        label = "tabBg"
    )

    val contentColor by animateColorAsState(
        targetValue = when {
            isFocused && isSelected -> DarkBackground
            isFocused -> Color.White
            isSelected -> CyberGreen
            else -> TextSecondary
        },
        animationSpec = androidx.compose.animation.core.tween(150),
        label = "tabContent"
    )

    val borderColor by animateColorAsState(
        targetValue = when {
            isFocused -> Color.White
            isSelected -> CyberGreen.copy(alpha = 0.5f)
            else -> Color.Transparent
        },
        animationSpec = androidx.compose.animation.core.tween(150),
        label = "tabBorder"
    )

    Surface(
        onClick = onClick,
        modifier = Modifier
            .scale(scale)
            .onFocusChanged { isFocused = it.isFocused },
        shape = RoundedCornerShape(10.dp),
        color = backgroundColor,
        border = BorderStroke(
            width = if (isFocused) 2.5.dp else if (isSelected) 1.dp else 0.dp,
            color = borderColor
        )
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            modifier = Modifier.padding(horizontal = 18.dp, vertical = 8.dp)
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = tab.icon,
                    contentDescription = null,
                    tint = contentColor,
                    modifier = Modifier.size(18.dp)
                )
                Spacer(modifier = Modifier.width(8.dp))
                Text(
                    text = tab.title,
                    color = contentColor,
                    fontSize = 13.sp,
                    fontWeight = if (isFocused || isSelected) FontWeight.Bold else FontWeight.Medium,
                    letterSpacing = 1.sp
                )
            }

            // Active page indicator bar (visible when this page is currently active)
            if (isSelected && !isFocused) {
                Spacer(modifier = Modifier.height(3.dp))
                Box(
                    modifier = Modifier
                        .width(24.dp)
                        .height(2.5.dp)
                        .clip(RoundedCornerShape(2.dp))
                        .background(CyberGreen)
                )
            }
        }
    }
}
