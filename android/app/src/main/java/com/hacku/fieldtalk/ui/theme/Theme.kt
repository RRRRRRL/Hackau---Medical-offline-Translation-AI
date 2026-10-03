package com.hacku.fieldtalk.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val FieldTalkColors = lightColorScheme(
    primary = Color(0xFF175C4C),
    onPrimary = Color.White,
    primaryContainer = Color(0xFFD3EDE4),
    onPrimaryContainer = Color(0xFF073B31),
    secondary = Color(0xFF52636D),
    background = Color(0xFFF7F9FA),
    surface = Color.White,
    onSurface = Color(0xFF17202A),
    error = Color(0xFFA82424),
)

@Composable
fun FieldTalkTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = FieldTalkColors, content = content)
}
