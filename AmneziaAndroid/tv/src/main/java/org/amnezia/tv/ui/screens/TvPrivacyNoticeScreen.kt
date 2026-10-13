package org.amnezia.tv.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.SwapHoriz
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.amnezia.tv.ui.theme.CyberGreen
import org.amnezia.tv.ui.theme.DarkBackground
import org.amnezia.tv.ui.theme.SurfaceCard
import org.amnezia.tv.ui.theme.TextPrimary
import org.amnezia.tv.ui.theme.TextSecondary

import org.amnezia.tv.ui.components.TvFocusableButton

const val TV_PRIVACY_POLICY_URL = "https://github.com/oktayibis/amnezia-clinet/blob/main/PRIVACY.md"

/** First-launch VpnService disclosure for Android TV (fits single 540dp screen, D-pad friendly). */
@Composable
fun TvPrivacyNoticeScreen(onAccept: () -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(DarkBackground)
            .padding(horizontal = 72.dp, vertical = 20.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Icon(
            imageVector = Icons.Default.Security,
            contentDescription = null,
            tint = CyberGreen,
            modifier = Modifier.size(36.dp)
        )
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "Your Privacy Comes First",
            color = TextPrimary,
            fontSize = 22.sp,
            fontWeight = FontWeight.Bold
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            text = "AWG Connect TV is an independent client for your own WireGuard and AmneziaWG servers.",
            color = TextSecondary,
            fontSize = 13.sp,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(14.dp))

        Column(
            modifier = Modifier
                .widthIn(max = 680.dp)
                .background(SurfaceCard, RoundedCornerShape(12.dp))
                .padding(horizontal = 20.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            Bullet(Icons.Default.VisibilityOff, "Zero data collection", "No analytics, no accounts, no logs of browsing, DNS or device.")
            Bullet(Icons.Default.Lock, "Configs stay on this device", "Server keys stored locally and never uploaded.")
            Bullet(Icons.Default.SwapHoriz, "Traffic goes to your server only", "All traffic is routed only to the VPN server you imported.")
        }

        Spacer(modifier = Modifier.height(8.dp))
        Text(text = "Full policy: $TV_PRIVACY_POLICY_URL", color = TextSecondary.copy(alpha = 0.7f), fontSize = 11.sp)
        Spacer(modifier = Modifier.height(14.dp))

        TvFocusableButton(
            text = "I Understand & Agree",
            onClick = onAccept,
            modifier = Modifier.widthIn(min = 280.dp),
            isPrimary = true
        )
    }
}

@Composable
private fun Bullet(icon: ImageVector, title: String, text: String) {
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Icon(imageVector = icon, contentDescription = null, tint = CyberGreen, modifier = Modifier.size(18.dp))
        Spacer(modifier = Modifier.width(10.dp))
        Text(
            text = "$title: ",
            color = TextPrimary,
            fontSize = 13.sp,
            fontWeight = FontWeight.SemiBold
        )
        Text(
            text = text,
            color = TextSecondary,
            fontSize = 12.sp,
            maxLines = 1,
            overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis
        )
    }
}
