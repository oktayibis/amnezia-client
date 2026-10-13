package org.amnezia.tv.ui.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import org.amnezia.tv.ui.theme.CyberGreen
import org.amnezia.tv.ui.theme.DarkBackground
import org.amnezia.tv.ui.theme.SurfaceBorder
import org.amnezia.tv.ui.theme.SurfaceCard
import org.amnezia.tv.ui.theme.TextPrimary

/**
 * TV-specific D-pad focusable button with prominent hover effects (scale, luminous border, high-contrast glow).
 * Unfocused buttons remain calm so that only the currently hovered/focused item is highlighted.
 */
@Composable
fun TvFocusableButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    isPrimary: Boolean = true,
    shape: Shape = RoundedCornerShape(12.dp),
    contentPadding: PaddingValues = PaddingValues(horizontal = 20.dp, vertical = 12.dp)
) {
    var isFocused by remember { mutableStateOf(false) }

    val scale by animateFloatAsState(
        targetValue = if (isFocused) 1.06f else 1.0f,
        animationSpec = tween(150),
        label = "tvBtnScale"
    )

    val containerColor by animateColorAsState(
        targetValue = when {
            isFocused -> CyberGreen
            isPrimary -> Color(0xFF1C2535)
            else -> SurfaceCard
        },
        animationSpec = tween(150),
        label = "tvBtnContainer"
    )

    val contentColor by animateColorAsState(
        targetValue = when {
            isFocused -> DarkBackground
            isPrimary -> CyberGreen
            else -> TextPrimary
        },
        animationSpec = tween(150),
        label = "tvBtnContent"
    )

    val borderColor by animateColorAsState(
        targetValue = when {
            isFocused -> Color.White
            isPrimary -> CyberGreen.copy(alpha = 0.5f)
            else -> SurfaceBorder
        },
        animationSpec = tween(150),
        label = "tvBtnBorder"
    )

    val borderWidth = if (isFocused) 2.5.dp else 1.dp

    Button(
        onClick = onClick,
        modifier = modifier
            .scale(scale)
            .onFocusChanged { isFocused = it.isFocused },
        shape = shape,
        colors = ButtonDefaults.buttonColors(
            containerColor = containerColor,
            contentColor = contentColor
        ),
        border = BorderStroke(borderWidth, borderColor),
        contentPadding = contentPadding
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center
        ) {
            if (icon != null) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    modifier = Modifier.size(18.dp),
                    tint = contentColor
                )
                Spacer(modifier = Modifier.width(8.dp))
            }
            Text(
                text = text,
                color = contentColor,
                fontSize = 14.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = 0.5.sp
            )
        }
    }
}
