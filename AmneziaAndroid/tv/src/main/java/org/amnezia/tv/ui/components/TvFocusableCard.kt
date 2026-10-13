package org.amnezia.tv.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import org.amnezia.tv.ui.theme.CyberGreen
import org.amnezia.tv.ui.theme.FocusBorderColor
import org.amnezia.tv.ui.theme.SurfaceBorder
import org.amnezia.tv.ui.theme.SurfaceCard

@Composable
fun TvFocusableCard(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    shape: Shape = RoundedCornerShape(16.dp),
    backgroundColor: Color = SurfaceCard,
    defaultBorderColor: Color = SurfaceBorder,
    borderWidth: Dp = 1.dp,
    content: @Composable BoxScope.(isFocused: Boolean) -> Unit
) {
    var isFocused by remember { mutableStateOf(false) }

    val scale by animateFloatAsState(
        targetValue = if (isFocused) 1.05f else 1.0f,
        animationSpec = tween(durationMillis = 150),
        label = "tvCardScale"
    )

    val borderColor by animateColorAsState(
        targetValue = if (isFocused) CyberGreen else defaultBorderColor,
        animationSpec = tween(durationMillis = 150),
        label = "tvCardBorder"
    )

    val currentBorderWidth = if (isFocused) 2.5.dp else borderWidth

    Surface(
        onClick = onClick,
        modifier = modifier
            .scale(scale)
            .onFocusChanged { isFocused = it.isFocused },
        shape = shape,
        color = if (isFocused) Color(0xFF223048) else backgroundColor,
        border = BorderStroke(currentBorderWidth, if (isFocused) Color.White else borderColor)
    ) {
        Box {
            content(isFocused)
        }
    }
}
