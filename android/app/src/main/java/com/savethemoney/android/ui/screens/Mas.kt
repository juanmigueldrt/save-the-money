package com.savethemoney.android.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.savethemoney.android.R
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.StmIcon
import com.savethemoney.android.ui.components.tap
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

@Composable internal fun tituloImportar(validas: Int) = pluralStringResource(R.plurals.mas_importar_movimientos, validas, validas)

// ───────────────────────── Piezas de estas pantallas ─────────────────────────

/** Cabecera de Más opciones: barra vacía de 64 y título grande (152 dp en total). */
@Composable
internal fun MasHeader() {
    Spacer(Modifier.height(88.dp))
    Text(stringResource(R.string.comun_mas_opciones), Modifier.padding(start = 16.dp), style = StmType.headlineLarge, color = Stm.colors.onSurface)
    Spacer(Modifier.height(24.dp))
}

/** Barra superior mediana (112 dp): fila de 60 con atrás y acciones, y título de 28 debajo. */
@Composable
internal fun MediumTopBar(title: String, onBack: () -> Unit, actions: @Composable RowScope.() -> Unit) {
    Row(Modifier.fillMaxWidth().height(60.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        IconBtn(StmIcons.arrowBack, onBack, contentDescription = stringResource(R.string.comun_atras))
        Spacer(Modifier.weight(1f))
        actions()
    }
    Text(title, Modifier.padding(start = 16.dp, bottom = 16.dp), style = StmType.headlineMedium, color = Stm.colors.onSurface)
}

/**
 * Botón segmentado que se ajusta al texto: 12 dp a cada lado, mínimo 48 y 4 dp más en los extremos
 * redondeados (el compartido reparte el ancho a partes iguales).
 */
@Composable
internal fun HugSegmented(options: List<String>, selected: Int, onSelect: (Int) -> Unit) {
    val c = Stm.colors
    val shape = RoundedCornerShape(20.dp)
    Row(Modifier.height(40.dp).clip(shape).border(1.dp, c.outline, shape)) {
        options.forEachIndexed { i, label ->
            val on = i == selected
            val outer = if (i == 0 || i == options.lastIndex) 4.dp else 0.dp
            Row(
                Modifier.fillMaxHeight().let { if (on) it.background(c.secondaryContainer) else it }
                    .drawBehind { if (i > 0) drawRect(c.outline, Offset.Zero, Size(1.dp.toPx(), size.height)) }
                    .tap(role = Role.RadioButton) { onSelect(i) }
                    .padding(start = if (i == 0) outer else 0.dp, end = if (i == options.lastIndex) outer else 0.dp)
                    .widthIn(min = 48.dp - outer).padding(horizontal = 12.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (on) {
                    StmIcon(StmIcons.check, c.onSecondaryContainer, size = 18.dp)
                    Spacer(Modifier.width(8.dp))
                }
                Text(label, style = StmType.labelLarge, color = if (on) c.onSecondaryContainer else c.onSurface, maxLines = 1)
            }
        }
    }
}

/** Elemento de leyenda: punto de 8 y texto. */
@Composable
internal fun Legend(color: Color, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(color))
        Spacer(Modifier.width(8.dp))
        Text(text, style = StmType.bodySmall, color = Stm.colors.onSurfaceVariant)
    }
}

/** Dato de la posición: etiqueta a la izquierda y valor a la derecha. */
@Composable
internal fun DataRow(label: String, value: String, valueColor: Color = Stm.colors.onSurface) {
    Row(Modifier.fillMaxWidth()) {
        Text(label, Modifier.weight(1f), style = StmType.bodyMedium, color = Stm.colors.onSurfaceVariant)
        Text(value, style = StmType.labelLarge, color = valueColor)
    }
}

/** Campo con borde y sufijo de unidad (€, %); etiqueta sobre el borde en el color de la tarjeta. */
@Composable
internal fun SuffixField(label: String, value: String, onValueChange: (String) -> Unit, suffix: String, modifier: Modifier) {
    val c = Stm.colors
    var focused by remember { mutableStateOf(false) }
    val shape = RoundedCornerShape(4.dp)
    Box(modifier.height(56.dp)) {
        Row(
            Modifier.fillMaxSize().border(if (focused) 2.dp else 1.dp, if (focused) c.primary else c.outline, shape)
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BasicTextField(
                value, onValueChange, Modifier.weight(1f).onFocusChanged { focused = it.isFocused }, singleLine = true,
                textStyle = StmType.bodyLarge.copy(color = c.onSurface), cursorBrush = SolidColor(c.primary),
                keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
            )
            Spacer(Modifier.width(12.dp))
            Text(suffix, style = StmType.bodyLarge, color = c.onSurfaceVariant)
        }
        Text(
            label, style = StmType.bodySmall, color = if (focused) c.primary else c.onSurfaceVariant,
            modifier = Modifier.offset(12.dp, (-8).dp).background(c.surfaceContainerLowest).padding(horizontal = 4.dp),
        )
    }
}

/** Fila del menú de Más: icono de 24, texto, contador opcional y chevron. */
@Composable
internal fun MenuRow(icon: ImageVector, label: String, count: String? = null, chevron: Boolean = true, onClick: (() -> Unit)?) {
    val c = Stm.colors
    ListItem(
        label,
        leading = { StmIcon(icon, c.onSurfaceVariant) },
        trailing = if (!chevron) null else {
            {
                Row {
                    if (count != null) {
                        Text(count, style = StmType.bodyMedium, color = c.onSurfaceVariant)
                        Spacer(Modifier.width(8.dp))
                    }
                    StmIcon(StmIcons.chevronRight, c.onSurfaceVariant)
                }
            }
        },
        onClick = onClick,
    )
}
