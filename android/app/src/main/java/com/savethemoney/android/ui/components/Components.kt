package com.savethemoney.android.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsBottomHeight
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.ripple
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.zIndex
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType

// Componentes del diseño «Estilo Monarch · Android» (página Componentes de FigCraft).
// Las medidas salen del diseño; los nombres de capa del diseño van entre comillas en cada comentario.

@Composable
fun StmIcon(icon: ImageVector, tint: Color, modifier: Modifier = Modifier, size: Dp = 24.dp, contentDescription: String? = null) {
    Icon(icon, contentDescription, modifier.size(size), tint = tint)
}

/** Toque con onda que respeta la forma del elemento. */
fun Modifier.tap(shape: Shape? = null, enabled: Boolean = true, role: Role = Role.Button, onClick: (() -> Unit)?): Modifier =
    if (onClick == null) this else (if (shape != null) clip(shape) else this).clickable(enabled = enabled, role = role, onClick = onClick)

// ───────────────────────── Estructura de pantalla ─────────────────────────

/**
 * Pantalla completa: barra superior, contenido desplazable, barra de navegación, FAB y capas
 * (hojas, diálogos, snackbar). El fondo es `surface`.
 */
@Composable
fun StmScreen(
    topBar: @Composable ColumnScope.() -> Unit = {},
    bottomBar: (@Composable () -> Unit)? = null,
    fab: (@Composable () -> Unit)? = null,
    snackbar: (@Composable () -> Unit)? = null,
    scroll: Boolean = true,
    contentPadding: Dp = 16.dp,
    overlay: (@Composable BoxScope.() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Box(Modifier.fillMaxSize().background(Stm.colors.surface)) {
        Column(Modifier.fillMaxSize()) {
            Column(Modifier.statusBarsPadding(), content = topBar)
            Box(Modifier.weight(1f).fillMaxWidth()) {
                val body = Modifier.fillMaxSize().let { if (scroll) it.verticalScroll(rememberScrollState()) else it }
                Column(body.padding(horizontal = contentPadding)) {
                    Spacer(Modifier.height(4.dp))
                    content()
                    // Espacio para que el FAB no tape lo último.
                    Spacer(Modifier.height(if (fab != null) 88.dp else 24.dp))
                }
                Column(Modifier.align(Alignment.BottomEnd).padding(horizontal = 16.dp), horizontalAlignment = Alignment.End) {
                    fab?.invoke()
                    if (snackbar != null) {
                        Spacer(Modifier.height(12.dp))
                        snackbar()
                    }
                    if (fab != null || snackbar != null) Spacer(Modifier.height(if (bottomBar == null) 16.dp else 0.dp))
                }
            }
            if (bottomBar != null) bottomBar() else Spacer(Modifier.windowInsetsBottomHeight(WindowInsets.navigationBars))
        }
        overlay?.invoke(this)
    }
}

/** «Barra superior» pequeña: icono de navegación, título serif y acciones (64 dp). */
@Composable
fun TopBar(
    title: String?,
    navIcon: ImageVector? = StmIcons.arrowBack,
    onNav: (() -> Unit)? = null,
    actions: @Composable RowScope.() -> Unit = {},
) {
    Row(Modifier.fillMaxWidth().height(64.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        if (navIcon != null) IconBtn(navIcon, onNav, contentDescription = "Atrás") else Spacer(Modifier.width(4.dp))
        Text(
            title.orEmpty(), Modifier.weight(1f).padding(start = 8.dp, end = 8.dp), style = StmType.appBarTitle,
            color = Stm.colors.onSurface, maxLines = 1, overflow = TextOverflow.Ellipsis,
        )
        Row(verticalAlignment = Alignment.CenterVertically, content = actions)
    }
}

/** Título grande bajo la barra («Título» de la barra superior de 152 dp). */
@Composable
fun LargeTitle(title: String, subtitle: String? = null, style: TextStyle = StmType.headlineLarge) {
    Column(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 24.dp)) {
        Text(title, style = style, color = Stm.colors.onSurface)
        if (subtitle != null) Text(subtitle, style = StmType.bodyMedium, color = Stm.colors.onSurfaceVariant)
    }
}

// ───────────────────────── Botones ─────────────────────────

/** «Botón de icono» de 40 dp. */
@Composable
fun IconBtn(icon: ImageVector, onClick: (() -> Unit)?, tint: Color = Stm.colors.onSurfaceVariant, contentDescription: String? = null) {
    Box(Modifier.size(40.dp).tap(CircleShape, onClick = onClick ?: {}), contentAlignment = Alignment.Center) {
        StmIcon(icon, tint, contentDescription = contentDescription)
    }
}

enum class BtnKind { Filled, Tonal, Outlined, Text, Error }

/** «Botón»: relleno, tonal, con borde o de texto. Alto 40 (pequeño) o 56 (grande). */
@Composable
fun Btn(
    label: String,
    onClick: (() -> Unit)?,
    modifier: Modifier = Modifier,
    kind: BtnKind = BtnKind.Filled,
    icon: ImageVector? = null,
    large: Boolean = false,
    color: Color? = null,
    enabled: Boolean = true,
) {
    val c = Stm.colors
    val (bg, fg) = when (kind) {
        BtnKind.Filled -> c.primary to c.onPrimary
        BtnKind.Tonal -> c.secondaryContainer to c.onSecondaryContainer
        BtnKind.Outlined -> Color.Transparent to c.onSurfaceVariant
        BtnKind.Text -> Color.Transparent to c.primary
        BtnKind.Error -> Color.Transparent to c.error
    }
    // Desactivado según M3: fondo on-surface al 12 % y contenido al 38 %.
    val content = if (!enabled) c.onSurface.copy(alpha = 0.38f) else color ?: fg
    val bgColor = if (!enabled && bg != Color.Transparent) c.onSurface.copy(alpha = 0.12f) else bg
    val h = if (large) 56.dp else 40.dp
    val shape = RoundedCornerShape(h / 2)
    val pad = when {
        kind == BtnKind.Text || kind == BtnKind.Error -> 12.dp
        large -> 24.dp
        icon != null -> 16.dp
        else -> 24.dp
    }
    Row(
        modifier.height(h).clip(shape).background(bgColor)
            .let { if (kind == BtnKind.Outlined) it.border(1.dp, if (enabled) c.outline else c.onSurface.copy(alpha = 0.12f), shape) else it }
            .tap(enabled = enabled, onClick = onClick)
            .padding(start = pad, end = if (icon != null && kind != BtnKind.Text && kind != BtnKind.Error) 24.dp else pad),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            StmIcon(icon, content, size = 18.dp)
            Spacer(Modifier.width(8.dp))
        }
        Text(label, style = if (large) StmType.titleMedium else StmType.labelLarge, color = content, maxLines = 1)
    }
}

/** «FAB» extendido: 56 dp, `primary-container`, sombra. */
@Composable
fun Fab(label: String, icon: ImageVector = StmIcons.add, onClick: (() -> Unit)?) {
    val shape = RoundedCornerShape(16.dp)
    Row(
        Modifier.height(56.dp).shadow(6.dp, shape).clip(shape).background(Stm.colors.primaryContainer)
            .tap(onClick = onClick).padding(start = 16.dp, end = 20.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StmIcon(icon, Stm.colors.onPrimaryContainer)
        Spacer(Modifier.width(12.dp))
        Text(label, style = StmType.titleMedium, color = Stm.colors.onPrimaryContainer)
    }
}

// ───────────────────────── Selección ─────────────────────────

/** «Chip» de filtro o de acción (32 dp, esquinas de 8). */
@Composable
fun Chip(
    label: String,
    selected: Boolean = false,
    onClick: (() -> Unit)? = null,
    icon: ImageVector? = null,
    labelColor: Color = Stm.colors.onSurfaceVariant,
) {
    val c = Stm.colors
    val shape = RoundedCornerShape(8.dp)
    val lead = if (selected) StmIcons.check else icon
    Row(
        Modifier.height(32.dp).clip(shape)
            .let { if (selected) it.background(c.secondaryContainer) else it.border(1.dp, c.outline, shape) }
            .tap(role = Role.Checkbox, onClick = onClick)
            .padding(start = if (lead != null) 8.dp else 16.dp, end = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (lead != null) {
            StmIcon(lead, if (selected) c.onSecondaryContainer else c.primary, size = 18.dp)
            Spacer(Modifier.width(8.dp))
        }
        Text(label, style = StmType.labelLarge, color = if (selected) c.onSecondaryContainer else labelColor, maxLines = 1)
    }
}

/** Fila de chips que salta de línea («Fila» con huecos de 8). */
@Composable
fun ChipRow(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    FlowRow(modifier, horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) { content() }
}

/** «Botón segmentado» (40 dp, borde `outline`, el elegido en `secondary-container` con ✓). */
@Composable
fun Segmented(options: List<String>, selected: Int, onSelect: ((Int) -> Unit)? = null, modifier: Modifier = Modifier.fillMaxWidth()) {
    val c = Stm.colors
    val shape = RoundedCornerShape(20.dp)
    Row(modifier.height(40.dp).clip(shape).border(1.dp, c.outline, shape)) {
        options.forEachIndexed { i, label ->
            if (i > 0) Box(Modifier.width(1.dp).fillMaxHeight().background(c.outline))
            val on = i == selected
            // El diseño da 4 dp más a los segmentos de los extremos (128/124/128).
            val outer = options.size > 2 && (i == 0 || i == options.lastIndex)
            Row(
                Modifier.weight(if (outer) 1f + 4f / 124f else 1f).fillMaxHeight().let { if (on) it.background(c.secondaryContainer) else it }
                    .tap(role = Role.RadioButton, onClick = onSelect?.let { { it(i) } }),
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


/** «Interruptor» de 52 × 32. */
@Composable
fun StmSwitch(checked: Boolean, onChange: ((Boolean) -> Unit)? = null) {
    val c = Stm.colors
    val track = RoundedCornerShape(16.dp)
    Box(
        Modifier.size(52.dp, 48.dp).tap(role = Role.Switch, onClick = onChange?.let { { it(!checked) } }),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier.size(52.dp, 32.dp).clip(track)
                .background(if (checked) c.primary else c.surfaceContainerHighest)
                .let { if (checked) it else it.border(2.dp, c.outline, track) },
        ) {
            val knob = if (checked) 24.dp else 16.dp
            Box(
                Modifier.align(Alignment.CenterStart).offset(x = if (checked) 24.dp else 8.dp).size(knob).clip(CircleShape)
                    .background(if (checked) c.onPrimary else c.outline),
                contentAlignment = Alignment.Center,
            ) {
                if (checked) StmIcon(StmIcons.check, c.primary, size = 16.dp)
            }
        }
    }
}

// ───────────────────────── Campos ─────────────────────────

/**
 * «Campo de texto» relleno (56 dp, `surface-container-highest`, línea inferior).
 * Con [onValueChange] nulo se pinta como solo lectura (selector que abre otra pantalla).
 */
@Composable
fun FilledField(
    label: String,
    value: String,
    onValueChange: ((String) -> Unit)? = null,
    modifier: Modifier = Modifier.fillMaxWidth(),
    leading: ImageVector? = null,
    trailing: ImageVector? = null,
    suffix: String? = null,
    supporting: String? = null,
    error: Boolean = false,
    keyboard: KeyboardType = KeyboardType.Text,
    onClick: (() -> Unit)? = null,
    autoFocus: Boolean = false,
) {
    val c = Stm.colors
    var focused by remember { mutableStateOf(false) }
    val focus = remember { FocusRequester() }
    if (autoFocus && onValueChange != null) LaunchedEffect(Unit) { focus.requestFocus() }
    val accent = if (error) c.error else if (focused) c.primary else c.onSurfaceVariant
    Column(modifier) {
        Row(
            Modifier.fillMaxWidth().height(56.dp).clip(RoundedCornerShape(4.dp, 4.dp, 0.dp, 0.dp))
                .background(c.surfaceContainerHighest)
                .drawBehind {
                    val w = (if (focused) 3.dp else if (error) 2.dp else 1.dp).toPx()
                    drawRect(accent, Offset(0f, size.height - w), androidx.compose.ui.geometry.Size(size.width, w))
                }
                .tap(onClick = onClick)
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (leading != null) {
                StmIcon(leading, c.onSurfaceVariant)
                Spacer(Modifier.width(12.dp))
            }
            Column(Modifier.weight(1f)) {
                Text(label, style = StmType.bodySmall, color = if (error || focused) accent else c.onSurfaceVariant)
                FieldText(value, onValueChange, keyboard, false, Modifier.focusRequester(focus).onFocusChanged { focused = it.isFocused })
            }
            if (suffix != null) Text(suffix, style = StmType.bodyLarge, color = c.onSurfaceVariant, modifier = Modifier.padding(top = 16.dp))
            if (trailing != null) {
                Spacer(Modifier.width(12.dp))
                StmIcon(trailing, if (error) c.error else c.onSurfaceVariant)
            }
        }
        if (supporting != null) Supporting(supporting, error)
    }
}

/** «Campo de texto» con borde y etiqueta flotante sobre el borde. */
@Composable
fun OutlinedField(
    label: String,
    value: String,
    onValueChange: ((String) -> Unit)? = null,
    modifier: Modifier = Modifier.fillMaxWidth(),
    leading: ImageVector? = null,
    trailing: ImageVector? = null,
    onTrailing: (() -> Unit)? = null,
    supporting: String? = null,
    error: Boolean = false,
    password: Boolean = false,
    placeholder: String? = null,
    labelBackground: Color = Stm.colors.surface,
    keyboard: KeyboardType = KeyboardType.Text,
    autoFocus: Boolean = false,
) {
    val c = Stm.colors
    var focused by remember { mutableStateOf(false) }
    val focus = remember { FocusRequester() }
    if (autoFocus && onValueChange != null) LaunchedEffect(Unit) { focus.requestFocus() }
    val accent = if (error) c.error else if (focused) c.primary else c.outline
    val shape = RoundedCornerShape(4.dp)
    Column(modifier) {
        Box(Modifier.fillMaxWidth().height(56.dp)) {
            Row(
                Modifier.fillMaxSize().border(BorderStroke(if (focused || error) 2.dp else 1.dp, accent), shape)
                    .padding(start = 16.dp, end = if (trailing != null) 8.dp else 16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (leading != null) {
                    StmIcon(leading, c.onSurfaceVariant)
                    Spacer(Modifier.width(12.dp))
                }
                Box(Modifier.weight(1f)) {
                    if (value.isEmpty() && placeholder != null) Text(placeholder, style = StmType.bodyLarge, color = c.onSurfaceVariant)
                    FieldText(value, onValueChange, keyboard, password, Modifier.focusRequester(focus).onFocusChanged { focused = it.isFocused })
                }
                if (trailing != null) {
                    Box(Modifier.size(40.dp).tap(CircleShape, onClick = onTrailing), contentAlignment = Alignment.Center) {
                        StmIcon(trailing, if (error) c.error else c.onSurfaceVariant)
                    }
                }
            }
            run {
                Text(
                    label, style = StmType.bodySmall,
                    color = if (error) c.error else if (focused) c.primary else c.onSurfaceVariant,
                    modifier = Modifier.offset(x = if (leading != null) 48.dp else 12.dp, y = (-8).dp)
                        .background(labelBackground).padding(horizontal = 4.dp),
                )
            }
        }
        if (supporting != null) Supporting(supporting, error)
    }
}

@Composable
private fun FieldText(value: String, onValueChange: ((String) -> Unit)?, keyboard: KeyboardType, password: Boolean, modifier: Modifier) {
    val c = Stm.colors
    if (onValueChange == null) {
        Text(value, style = StmType.bodyLarge, color = c.onSurface, maxLines = 1, overflow = TextOverflow.Ellipsis)
    } else {
        // TextFieldValue para que el cursor empiece al final del texto, como en el diseño
        var field by remember { mutableStateOf(TextFieldValue(value, TextRange(value.length))) }
        if (field.text != value) field = TextFieldValue(value, TextRange(value.length))
        BasicTextField(
            field, { field = it; if (it.text != value) onValueChange(it.text) }, modifier.fillMaxWidth(), singleLine = true,
            textStyle = StmType.bodyLarge.copy(color = c.onSurface),
            cursorBrush = SolidColor(c.primary),
            keyboardOptions = KeyboardOptions(keyboardType = if (password) KeyboardType.Password else keyboard),
            visualTransformation = if (password) PasswordVisualTransformation('•') else VisualTransformation.None,
        )
    }
}

@Composable
private fun Supporting(text: String, error: Boolean) {
    Text(
        text, style = StmType.bodySmall, color = if (error) Stm.colors.error else Stm.colors.onSurfaceVariant,
        modifier = Modifier.padding(start = 16.dp, top = 4.dp),
    )
}

// ───────────────────────── Contenedores y listas ─────────────────────────

/** «Tarjeta»: `surface-container-lowest`, esquinas de 12. */
@Composable
fun StmCard(
    modifier: Modifier = Modifier.fillMaxWidth(),
    color: Color = Stm.colors.surfaceContainerLowest,
    padding: Dp = 16.dp,
    onClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val shape = RoundedCornerShape(12.dp)
    Column(modifier.clip(shape).background(color).tap(onClick = onClick).padding(padding), content = content)
}

/** «Lista» agrupada en tarjeta, con 8 dp arriba y abajo. */
@Composable
fun ListCard(modifier: Modifier = Modifier.fillMaxWidth(), content: @Composable ColumnScope.() -> Unit) {
    StmCard(modifier, padding = 0.dp) {
        Spacer(Modifier.height(8.dp))
        content()
        Spacer(Modifier.height(8.dp))
    }
}

/** «Cabecera de lista» (32 dp). */
@Composable
fun ListHeader(text: String) {
    Text(
        text, style = StmType.labelLarge, color = Stm.colors.onSurfaceVariant,
        modifier = Modifier.fillMaxWidth().height(32.dp).padding(start = 16.dp, top = 8.dp),
    )
}

/** «Cabecera de sección» fuera de tarjeta: título y botón de texto opcional (40 dp). */
@Composable
fun SectionHeader(title: String, action: String? = null, onAction: (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().height(40.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.weight(1f), style = StmType.titleMedium, color = Stm.colors.onSurface)
        if (action != null) Btn(action, onAction, kind = BtnKind.Text)
    }
}

/** Círculo de 40 dp con icono («Inicio» de un elemento de lista). */
@Composable
fun LeadIcon(icon: ImageVector, container: Color = Stm.colors.secondaryContainer, tint: Color = Stm.colors.onSecondaryContainer, size: Dp = 40.dp) {
    Box(Modifier.size(size).clip(CircleShape).background(container), contentAlignment = Alignment.Center) {
        StmIcon(icon, tint)
    }
}

/** Avatar de iniciales. */
@Composable
fun Avatar(initial: String, container: Color = Stm.colors.tertiaryContainer, tint: Color = Stm.colors.onTertiaryContainer, size: Dp = 40.dp) {
    Box(Modifier.size(size).clip(CircleShape).background(container), contentAlignment = Alignment.Center) {
        Text(initial, style = StmType.titleMedium, color = tint)
    }
}

/**
 * «Elemento de lista» de 1, 2 o 3 líneas: inicio (icono/avatar), titular, texto secundario y final.
 * El alto mínimo es 56 (una línea) o 72 (dos líneas).
 */
@Composable
fun ListItem(
    headline: String,
    supporting: String? = null,
    modifier: Modifier = Modifier,
    leading: (@Composable () -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null,
    trailingText: String? = null,
    supportingColor: Color = Stm.colors.onSurfaceVariant,
    supportingLines: Int = 1,
    onClick: (() -> Unit)? = null,
) {
    val minH = if (supporting == null) 56.dp else 72.dp
    Row(
        modifier.fillMaxWidth().heightIn(min = minH).tap(onClick = onClick).padding(start = 16.dp, end = 24.dp, top = if (supporting == null) 8.dp else 12.dp, bottom = if (supporting == null) 8.dp else 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (leading != null) {
            leading()
            Spacer(Modifier.width(16.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(headline, style = StmType.bodyLarge, color = Stm.colors.onSurface, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (supporting != null) {
                Text(supporting, style = StmType.bodyMedium, color = supportingColor, maxLines = supportingLines, overflow = TextOverflow.Ellipsis)
            }
        }
        if (trailingText != null) {
            Spacer(Modifier.width(16.dp))
            Text(trailingText, style = StmType.labelLarge, color = Stm.colors.onSurface, textAlign = TextAlign.End)
        }
        if (trailing != null) {
            Spacer(Modifier.width(16.dp))
            trailing()
        }
    }
}


/** «Divisor» con sangría de 72 dp (alineado con el texto tras el icono). */
@Composable
fun Divider(inset: Dp = 72.dp, endInset: Dp = 16.dp) {
    Box(Modifier.fillMaxWidth().padding(start = inset, end = endInset).height(1.dp).background(Stm.colors.outlineVariant))
}

/** «Variación»: píldora de 24 dp con flecha, en `success-container` o `error-container`. */
@Composable
fun Pill(text: String, positive: Boolean = true, icon: ImageVector? = StmIcons.arrowUpward) {
    val c = Stm.colors
    val bg = if (positive) c.successContainer else c.errorContainer
    val fg = if (positive) c.onSuccessContainer else c.onErrorContainer
    Row(
        Modifier.height(24.dp).clip(RoundedCornerShape(8.dp)).background(bg).padding(start = if (icon != null) 4.dp else 8.dp, end = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            StmIcon(icon, fg, size = 18.dp)
            Spacer(Modifier.width(2.dp))
        }
        Text(text, style = StmType.labelMedium, color = fg)
    }
}

/** «Progreso» lineal de 4 dp: barra, hueco de 4, pista e indicador de parada. */
@Composable
fun Progress(fraction: Float, modifier: Modifier = Modifier.fillMaxWidth(), color: Color = Stm.colors.primary, track: Color = Stm.colors.secondaryContainer) {
    val f = fraction.coerceIn(0f, 1f)
    Box(modifier.height(4.dp).drawBehind {
        val gap = 4.dp.toPx()
        val r = androidx.compose.ui.geometry.CornerRadius(2.dp.toPx())
        val barW = (size.width * f).coerceAtLeast(0f)
        if (barW > 0f) drawRoundRect(color, size = androidx.compose.ui.geometry.Size(barW, size.height), cornerRadius = r)
        val start = if (barW > 0f) barW + gap else 0f
        if (start < size.width) {
            drawRoundRect(track, Offset(start, 0f), androidx.compose.ui.geometry.Size(size.width - start, size.height), r)
            drawRoundRect(color, Offset(size.width - size.height, 0f), androidx.compose.ui.geometry.Size(size.height, size.height), r)
        }
    })
}

// ───────────────────────── Navegación ─────────────────────────

enum class Tab(val label: String, val screen: Int) { Inicio("Inicio", 4), Presupuesto("Presupuesto", 14), Flujo("Flujo", 16), Metas("Metas", 22), Mas("Más", 30) }

private val Tab.icon: ImageVector
    get() = when (this) {
        Tab.Inicio -> StmIcons.home
        Tab.Presupuesto -> StmIcons.donutLarge
        Tab.Flujo -> StmIcons.syncAlt
        Tab.Metas -> StmIcons.flag
        Tab.Mas -> StmIcons.moreHoriz
    }

/** «Barra de navegación» (80 dp + barra de gestos), `surface-container`. */
@Composable
fun NavBar(selected: Tab?, onSelect: (Tab) -> Unit, badgeOnMore: Boolean = false) {
    val c = Stm.colors
    Column(Modifier.fillMaxWidth().background(c.surfaceContainer).navigationBarsPadding()) {
        Row(Modifier.fillMaxWidth().height(80.dp).padding(horizontal = 8.dp, vertical = 12.dp)) {
            Tab.entries.forEach { tab ->
                val on = tab == selected
                Column(
                    Modifier.weight(1f).height(56.dp).tap(role = Role.Tab, onClick = { onSelect(tab) }),
                    horizontalAlignment = Alignment.CenterHorizontally,
                ) {
                    Box(
                        Modifier.size(56.dp, 32.dp).clip(RoundedCornerShape(16.dp)).let { if (on) it.background(c.secondaryContainer) else it },
                        contentAlignment = Alignment.Center,
                    ) {
                        StmIcon(if (on && tab == Tab.Inicio) StmIcons.homeFilled else tab.icon, if (on) c.onSecondaryContainer else c.onSurfaceVariant)
                        if (tab == Tab.Mas && badgeOnMore) {
                            Box(Modifier.align(Alignment.TopStart).offset(36.dp, 4.dp).size(6.dp).clip(CircleShape).background(c.error))
                        }
                    }
                    Spacer(Modifier.height(4.dp))
                    // «Presupuesto» mide 74,75 dp en una celda de 79: sin límite para que no se recorte por redondeo
                    Text(tab.label, Modifier.wrapContentWidth(unbounded = true), style = StmType.labelMedium, color = if (on) c.secondary else c.onSurfaceVariant, maxLines = 1, softWrap = false)
                }
            }
        }
    }
}

// ───────────────────────── Capas ─────────────────────────

/** «Velo» (`scrim` al 32 %) que cierra la capa al tocarlo. */
@Composable
fun BoxScope.Scrim(onDismiss: () -> Unit) {
    Box(
        Modifier.matchParentSize().zIndex(1f).background(Stm.colors.scrim.copy(alpha = 0.32f))
            .clickable(remember { MutableInteractionSource() }, indication = null, onClick = onDismiss),
    )
}

/** «Hoja inferior» modal con asa, título y subtítulo. */
@Composable
fun BoxScope.BottomSheet(title: String?, subtitle: String? = null, onDismiss: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    Scrim(onDismiss)
    val shape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)
    Column(
        Modifier.align(Alignment.BottomCenter).zIndex(2f).fillMaxWidth().shadow(8.dp, shape).clip(shape)
            .background(Stm.colors.surfaceContainerLow)
            .clickable(remember { MutableInteractionSource() }, indication = null) {}
            .navigationBarsPadding().padding(bottom = 24.dp),
    ) {
        Box(Modifier.fillMaxWidth().height(36.dp), contentAlignment = Alignment.Center) {
            Box(Modifier.size(32.dp, 4.dp).clip(CircleShape).background(Stm.colors.onSurfaceVariant))
        }
        if (title != null) {
            Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 16.dp)) {
                Text(title, style = StmType.headlineSmall, color = Stm.colors.onSurface)
                if (subtitle != null) {
                    Spacer(Modifier.height(2.dp))
                    Text(subtitle, style = StmType.bodyMedium, color = Stm.colors.onSurfaceVariant)
                }
            }
        }
        content()
    }
}

/** Hoja para elegir una opción; la lista se desplaza si no cabe. */
@Composable
fun BoxScope.SelectorSheet(title: String, options: List<Pair<String, () -> Unit>>, onDismiss: () -> Unit) {
    BottomSheet(title, onDismiss = onDismiss) {
        Column(Modifier.heightIn(max = 440.dp).verticalScroll(rememberScrollState())) {
            options.forEach { (label, pick) ->
                ListItem(label, onClick = {
                    pick()
                    onDismiss()
                })
            }
        }
    }
}

/** Elemento de una hoja o menú: icono de 24 y texto (56 dp). */
@Composable
fun SheetItem(icon: ImageVector, label: String, color: Color = Stm.colors.onSurface, iconTint: Color = Stm.colors.onSurfaceVariant, onClick: (() -> Unit)?) {
    Row(Modifier.fillMaxWidth().height(56.dp).tap(onClick = onClick).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        StmIcon(icon, iconTint)
        Spacer(Modifier.width(16.dp))
        Text(label, style = StmType.bodyLarge, color = color)
    }
}

/** «Diálogo» de 312 dp: icono, título centrado, texto, contenido y acciones a la derecha. */
@Composable
fun BoxScope.StmDialog(
    title: String,
    text: String? = null,
    icon: ImageVector? = null,
    onDismiss: () -> Unit,
    actions: @Composable RowScope.() -> Unit,
    content: @Composable ColumnScope.() -> Unit = {},
) {
    Scrim(onDismiss)
    val shape = RoundedCornerShape(28.dp)
    Column(
        Modifier.align(Alignment.Center).zIndex(2f).width(312.dp).shadow(6.dp, shape).clip(shape)
            .background(Stm.colors.surfaceContainerHigh)
            .clickable(remember { MutableInteractionSource() }, indication = null) {}
            .padding(24.dp),
        horizontalAlignment = if (icon != null) Alignment.CenterHorizontally else Alignment.Start,
    ) {
        if (icon != null) {
            StmIcon(icon, Stm.colors.error)
            Spacer(Modifier.height(16.dp))
        }
        Text(title, style = StmType.headlineSmall, color = Stm.colors.onSurface, textAlign = if (icon != null) TextAlign.Center else TextAlign.Start)
        if (text != null) {
            Spacer(Modifier.height(16.dp))
            Text(text, Modifier.fillMaxWidth(), style = StmType.bodyMedium, color = Stm.colors.onSurfaceVariant)
        }
        Column(Modifier.fillMaxWidth(), content = content)
        Spacer(Modifier.height(24.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End), content = actions)
    }
}

/** «Snackbar» de 48 dp en `inverse-surface`. */
@Composable
fun Snackbar(message: String, action: String? = null, onAction: (() -> Unit)? = null) {
    val shape = RoundedCornerShape(4.dp)
    Row(
        Modifier.fillMaxWidth().height(48.dp).shadow(4.dp, shape).clip(shape).background(Stm.colors.inverseSurface)
            .padding(start = 16.dp, end = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(message, Modifier.weight(1f), style = StmType.bodyMedium, color = Stm.colors.inverseOnSurface)
        if (action != null) Btn(action, onAction, kind = BtnKind.Text, color = Stm.colors.inversePrimary)
    }
}
