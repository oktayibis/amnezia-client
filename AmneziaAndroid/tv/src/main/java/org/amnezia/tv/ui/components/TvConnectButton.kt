package org.amnezia.tv.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PowerSettingsNew
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.amnezia.core.models.ConnectionState
import org.amnezia.tv.ui.theme.ConnectingOrange
import org.amnezia.tv.ui.theme.CyberGreen
import org.amnezia.tv.ui.theme.DarkBackground
import org.amnezia.tv.ui.theme.FocusBorderColor
import org.amnezia.tv.ui.theme.SurfaceCard
import org.amnezia.tv.ui.theme.TextPrimary
import org.amnezia.tv.ui.theme.TextSecondary

@Composable
fun TvConnectButton(
    connectionState: ConnectionState,
    onClick: () -> Unit,
    modifier: Modifier = Modifier
) {
    var isFocused by remember { mutableStateOf(false) }

    val isConnected = connectionState.isConnected
    val isBusy = connectionState.isBusy

    val infiniteTransition = rememberInfiniteTransition(label = "tvPulse")
    val pulseAlpha by infiniteTransition.animateFloat(
        initialValue = 0.2f,
        targetValue = 0.5f,
        animationSpec = infiniteRepeatable(
            animation = tween(1400, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse
        ),
        label = "tvPulseAlpha"
    )

    val scale by animateFloatAsState(
        targetValue = if (isFocused) 1.10f else 1.0f,
        animationSpec = tween(150),
        label = "tvBtnScale"
    )

    val buttonColor by animateColorAsState(
        targetValue = when {
            isConnected -> CyberGreen
            isBusy -> ConnectingOrange
            else -> SurfaceCard
        },
        label = "tvBtnColor"
    )

    val borderColor by animateColorAsState(
        targetValue = when {
            isFocused -> Color.White
            isConnected -> CyberGreen
            isBusy -> ConnectingOrange
            else -> Color(0x33FFFFFF)
        },
        label = "tvBtnBorder"
    )

    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = modifier
    ) {
        Box(
            modifier = Modifier
                .size(165.dp)
                .scale(scale)
                .onFocusChanged { isFocused = it.isFocused }
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClick = onClick
                ),
            contentAlignment = Alignment.Center
        ) {
            // Ambient glow
            if (isConnected || isBusy || isFocused) {
                Box(
                    modifier = Modifier
                        .size(165.dp)
                        .clip(CircleShape)
                        .background(
                            Brush.radialGradient(
                                colors = listOf(
                                    (if (isFocused) CyberGreen else buttonColor).copy(alpha = if (isFocused) 0.6f else pulseAlpha),
                                    Color.Transparent
                                )
                            )
                        )
                )
            }

            // Outer ring
            Box(
                modifier = Modifier
                    .size(145.dp)
                    .clip(CircleShape)
                    .border(
                        width = if (isFocused) 3.5.dp else 2.dp,
                        color = borderColor,
                        shape = CircleShape
                    )
            )

            // Inner circle
            Box(
                modifier = Modifier
                    .size(125.dp)
                    .clip(CircleShape)
                    .background(
                        if (isConnected || isBusy) {
                            Brush.verticalGradient(
                                listOf(buttonColor, buttonColor.copy(alpha = 0.85f))
                            )
                        } else {
                            Brush.verticalGradient(
                                listOf(
                                    if (isFocused) Color(0xFF2E3D58) else Color(0xFF1B2333),
                                    Color(0xFF131A26)
                                )
                            )
                        }
                    ),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = Icons.Default.PowerSettingsNew,
                    contentDescription = "Toggle Connection",
                    tint = if (isConnected || isBusy) DarkBackground else if (isFocused) CyberGreen else TextSecondary,
                    modifier = Modifier.size(50.dp)
                )
            }
        }

        Spacer(modifier = Modifier.height(10.dp))

        Text(
            text = when {
                isConnected -> "PRESS [SELECT] TO DISCONNECT"
                isBusy -> "CONNECTING..."
                else -> "PRESS [SELECT] TO CONNECT"
            },
            color = if (isFocused) Color.White else TextSecondary,
            fontSize = 12.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = 1.sp
        )
    }
}
