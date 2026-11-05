package com.savethemoney.android.ui.screens

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.savethemoney.android.ui.Nav
import com.savethemoney.android.ui.components.Avatar
import com.savethemoney.android.ui.components.Btn
import com.savethemoney.android.ui.components.BtnKind
import com.savethemoney.android.ui.components.Divider
import com.savethemoney.android.ui.components.IconBtn
import com.savethemoney.android.ui.components.LargeTitle
import com.savethemoney.android.ui.components.LeadIcon
import com.savethemoney.android.ui.components.ListCard
import com.savethemoney.android.ui.components.ListHeader
import com.savethemoney.android.ui.components.ListItem
import com.savethemoney.android.ui.components.NavBar
import com.savethemoney.android.ui.components.OutlinedField
import com.savethemoney.android.ui.components.StmCard
import com.savethemoney.android.ui.components.StmIcon
import com.savethemoney.android.ui.components.StmScreen
import com.savethemoney.android.ui.components.Tab
import com.savethemoney.android.ui.components.TopBar
import com.savethemoney.android.ui.icons.StmIcons
import com.savethemoney.android.ui.theme.Brand
import com.savethemoney.android.ui.theme.Stm
import com.savethemoney.android.ui.theme.StmType
import kotlin.random.Random

/** 01 Iniciar sesión: marca, usuario y contraseña, entrar o crear cuenta. */
@Composable
fun Pantalla01(nav: Nav) {
    val c = Stm.colors
    var user by remember { mutableStateOf("ana") }
    var password by remember { mutableStateOf("contraseña") }
    var hidden by remember { mutableStateOf(true) }
    StmScreen {
        Column(Modifier.padding(start = 8.dp, end = 8.dp, top = 48.dp)) {
            Text("Save the Money", style = StmType.labelLarge, color = c.primary)
            Spacer(Modifier.height(8.dp))
            Text("Tu dinero, claro", style = StmType.displayMedium, color = c.onSurface)
            Spacer(Modifier.height(8.dp))
            Text("Entra con tu usuario y contraseña para ver las cuentas de tu hogar.", style = StmType.bodyLarge, color = c.onSurfaceVariant)
            Spacer(Modifier.height(24.dp))
            OutlinedField("Usuario", user, { user = it }, leading = StmIcons.person)
            Spacer(Modifier.height(16.dp))
            OutlinedField(
                "Contraseña", password, { password = it }, leading = StmIcons.lock,
                trailing = if (hidden) StmIcons.visibility else StmIcons.visibilityOff, onTrailing = { hidden = !hidden },
                password = hidden, autoFocus = true,
            )
            Spacer(Modifier.height(24.dp))
            Btn("Entrar", { nav.reset(4) }, Modifier.fillMaxWidth(), large = true)
            Spacer(Modifier.height(24.dp))
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                Btn("Crear cuenta", { nav.go(2) }, kind = BtnKind.Text)
            }
        }
    }
}

/** 02 Crear cuenta: nombre, usuario y contraseña repetida, sin correo. */
@Composable
fun Pantalla02(nav: Nav) {
    val c = Stm.colors
    var name by remember { mutableStateOf("Ana") }
    var user by remember { mutableStateOf("ana") }
    var password by remember { mutableStateOf("abcde") }
    var repeat by remember { mutableStateOf("") }
    val tooShort = password.length < 10
    StmScreen(
        topBar = { TopBar("Crear cuenta", onNav = nav::back) },
        bottomBar = {
            Box(Modifier.fillMaxWidth().background(c.surface).navigationBarsPadding().padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 8.dp)) {
                Btn("Crear cuenta", { nav.go(3) }, Modifier.fillMaxWidth(), large = true)
            }
        },
    ) {
        Spacer(Modifier.height(8.dp))
        Text("Solo te pedimos un usuario y una contraseña. No usamos tu correo.", style = StmType.bodyLarge, color = c.onSurfaceVariant)
        Spacer(Modifier.height(16.dp))
        OutlinedField("Nombre", name, { name = it }, supporting = "Así te verá tu pareja en el hogar")
        Spacer(Modifier.height(16.dp))
        OutlinedField("Usuario", user, { user = it }, supporting = "Letras y números, sin espacios")
        Spacer(Modifier.height(16.dp))
        OutlinedField(
            "Contraseña", password, { password = it }, password = true, error = tooShort,
            trailing = if (tooShort) StmIcons.error else null,
            supporting = if (tooShort) "Usa al menos 10 caracteres" else null,
        )
        Spacer(Modifier.height(16.dp))
        OutlinedField("Repite la contraseña", repeat, { repeat = it }, password = true, placeholder = "Contraseña")
    }
}

/** 03 Tu hogar: crear un hogar nuevo o unirse con código o QR. */
@Composable
fun Pantalla03(nav: Nav) {
    val c = Stm.colors
    var code by remember { mutableStateOf("4K9Q2X") }
    StmScreen(
        topBar = {
            TopBar(null, navIcon = null)
            LargeTitle("Tu hogar", "Un hogar reúne las cuentas que compartís")
        },
    ) {
        OptionCard(StmIcons.homeWork, c.secondaryContainer, c.onSecondaryContainer, "Crear un hogar nuevo",
            "Empieza de cero y después invita a tu pareja con un código o un QR.") {
            Btn("Crear hogar", { nav.reset(4) })
        }
        Spacer(Modifier.height(16.dp))
        OptionCard(StmIcons.qrCodeScanner, c.tertiaryContainer, c.onTertiaryContainer, "Unirme a un hogar",
            "Escanea el QR de tu pareja o escribe su código de 6 letras.",
            field = { OutlinedField("Código", code, { code = it }, labelBackground = c.surfaceContainerLowest) },
        ) {
            Btn("Escanear QR", null, kind = BtnKind.Outlined, icon = StmIcons.qrCodeScanner)
            Btn("Unirme", { nav.reset(4) }, kind = BtnKind.Tonal)
        }
    }
}

/** Tarjeta de opción de la pantalla 03: icono, título, texto, campo opcional y botones a la derecha. */
@Composable
private fun OptionCard(
    icon: ImageVector,
    container: Color,
    tint: Color,
    title: String,
    text: String,
    field: (@Composable () -> Unit)? = null,
    actions: @Composable () -> Unit,
) {
    val c = Stm.colors
    StmCard {
        LeadIcon(icon, container, tint)
        Spacer(Modifier.height(12.dp))
        Text(title, style = StmType.titleMedium, color = c.onSurface)
        Spacer(Modifier.height(16.dp))
        Text(text, style = StmType.bodyMedium, color = c.onSurfaceVariant)
        if (field != null) {
            Spacer(Modifier.height(12.dp))
            field()
        }
        Spacer(Modifier.height(16.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End)) { actions() }
    }
}

/** 28 Hogar: miembros, qué se comparte e invitar a alguien. */
@Composable
fun Pantalla28(nav: Nav) {
    val c = Stm.colors
    StmScreen(
        topBar = {
            // Barra de 60 dp con título mediano debajo (no coincide con TopBar + LargeTitle).
            Row(Modifier.fillMaxWidth().height(60.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                IconBtn(StmIcons.arrowBack, nav::back, contentDescription = "Atrás")
                Spacer(Modifier.weight(1f))
                IconBtn(StmIcons.edit, null, contentDescription = "Editar")
            }
            Text("Hogar", Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp), style = StmType.headlineMedium, color = c.onSurface)
        },
        bottomBar = { NavBar(Tab.Mas, nav::tab) },
    ) {
        ListCard {
            ListHeader("Miembros")
            ListItem("Ana", "Tú · creó el hogar", leading = { Avatar("A") })
            Divider()
            ListItem(
                "Leo", "Se unió el 2 nov", leading = { Avatar("L") },
                // El diseño deja 24 dp a la derecha del icono final.
                trailing = { StmIcon(StmIcons.moreVert, c.onSurfaceVariant, Modifier.padding(end = 8.dp)) },
            )
        }
        Spacer(Modifier.height(16.dp))
        val shape = RoundedCornerShape(12.dp)
        StmCard(Modifier.fillMaxWidth().border(1.dp, c.outlineVariant, shape), color = c.surface) {
            Text("Qué compartís", style = StmType.titleMedium, color = c.onSurface)
            Spacer(Modifier.height(8.dp))
            Text(
                "Metas, pagos fijos y gastos esenciales. Las cuentas, los presupuestos y el score son de cada uno salvo que los compartas.",
                style = StmType.bodyMedium, color = c.onSurfaceVariant,
            )
        }
        Spacer(Modifier.height(16.dp))
        Btn("Invitar a alguien", { nav.go(29) }, Modifier.fillMaxWidth(), icon = StmIcons.personAdd, large = true)
    }
}

private const val INVITE_CODE = "4K9Q2X"

/** 29 Invitar a tu pareja: QR, código de 6 caracteres y botones para copiar o compartir. */
@Composable
fun Pantalla29(nav: Nav) {
    val c = Stm.colors
    StmScreen(topBar = { TopBar("Invitar", navIcon = StmIcons.close, onNav = nav::back) }) {
        Spacer(Modifier.height(12.dp))
        Text(
            "Escanea este código desde su móvil", Modifier.fillMaxWidth(),
            style = StmType.headlineSmall, color = c.onSurface, textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(24.dp))
        // El QR va siempre en tinta sobre papel (igual en claro y oscuro) para que se pueda escanear.
        Box(
            Modifier.align(Alignment.CenterHorizontally).size(216.dp).clip(RoundedCornerShape(16.dp))
                .background(Brand.paper).padding(16.dp),
        ) {
            QrPlaceholder(INVITE_CODE)
        }
        Spacer(Modifier.height(24.dp))
        Text("O escribe el código", Modifier.fillMaxWidth(), style = StmType.labelMedium, color = c.onSurfaceVariant, textAlign = TextAlign.Center)
        Spacer(Modifier.height(8.dp))
        Row(Modifier.align(Alignment.CenterHorizontally), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            INVITE_CODE.forEach { ch ->
                Box(
                    Modifier.size(44.dp, 56.dp).clip(RoundedCornerShape(8.dp)).background(c.surfaceContainerHighest),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(ch.toString(), style = StmType.headlineMediumWide, color = c.onSurface)
                }
            }
        }
        Spacer(Modifier.height(8.dp))
        Text("Caduca en 24 horas", Modifier.fillMaxWidth(), style = StmType.bodySmall, color = c.onSurfaceVariant, textAlign = TextAlign.Center)
        Spacer(Modifier.height(24.dp))
        Row(Modifier.align(Alignment.CenterHorizontally), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Btn("Copiar código", null, kind = BtnKind.Tonal, icon = StmIcons.contentCopy)
            Btn("Compartir enlace", null, kind = BtnKind.Outlined, icon = StmIcons.share)
        }
    }
}

private const val QR_MODULES = 25

/**
 * QR de muestra (25 × 25 módulos de 7,36 dp): los tres buscadores redondeados y un patrón fijo
 * derivado de [code]. shortcut: no es un QR legible; se cambia por uno real al conectar las invitaciones.
 */
@Composable
private fun QrPlaceholder(code: String) {
    val cells = remember(code) {
        val rnd = Random(code.hashCode())
        List(QR_MODULES * QR_MODULES) { rnd.nextBoolean() }
    }
    Canvas(Modifier.size(184.dp)) {
        val m = size.width / QR_MODULES
        for (y in 0 until QR_MODULES) for (x in 0 until QR_MODULES) {
            if (inFinder(x, y) || !cells[y * QR_MODULES + x]) continue
            drawRect(Brand.ink, Offset(x * m, y * m), Size(m, m))
        }
        val far = (QR_MODULES - 7) * m
        listOf(Offset(0f, 0f), Offset(far, 0f), Offset(0f, far)).forEach { finder(it, m) }
    }
}

/** Buscador: anillo de 7 módulos y centro de 3, con esquinas redondeadas como en el diseño. */
private fun DrawScope.finder(at: Offset, m: Float) {
    drawRoundRect(Brand.ink, at, Size(7 * m, 7 * m), CornerRadius(2 * m))
    drawRoundRect(Brand.paper, at + Offset(m, m), Size(5 * m, 5 * m), CornerRadius(1.2f * m))
    drawRoundRect(Brand.ink, at + Offset(2 * m, 2 * m), Size(3 * m, 3 * m), CornerRadius(0.8f * m))
}

/** Zona de un buscador más su separador de un módulo. */
private fun inFinder(x: Int, y: Int): Boolean {
    val far = QR_MODULES - 8
    return (x < 8 && y < 8) || (x >= far && y < 8) || (x < 8 && y >= far)
}
