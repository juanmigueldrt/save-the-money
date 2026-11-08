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
import android.content.Intent
import androidx.compose.foundation.layout.RowScope
import androidx.compose.runtime.produceState
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.AnnotatedString
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.savethemoney.android.data.HouseholdInvite
import com.savethemoney.android.data.HouseholdMember
import com.savethemoney.android.data.InviteCode
import com.savethemoney.android.data.MemberRole
import com.savethemoney.android.data.SignUpForm
import com.savethemoney.android.data.Username
import com.savethemoney.android.ui.LocalSession
import com.savethemoney.android.ui.rememberAction
import java.time.Duration
import java.time.Instant

/** 01 Iniciar sesión: marca, usuario y contraseña, entrar o crear cuenta. */
@Composable
fun Pantalla01(nav: Nav) {
    val c = Stm.colors
    val session = LocalSession.current
    val action = rememberAction()
    var user by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var hidden by remember { mutableStateOf(true) }
    val canSubmit = user.isNotBlank() && password.isNotEmpty() && !action.busy
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
                password = hidden,
                error = action.error != null, supporting = action.error,
            )
            Spacer(Modifier.height(24.dp))
            Btn("Entrar", { action.run { session.signIn(user, password) } }, Modifier.fillMaxWidth(), large = true, enabled = canSubmit)
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
    val session = LocalSession.current
    val action = rememberAction()
    var name by remember { mutableStateOf("") }
    var user by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var repeat by remember { mutableStateOf("") }
    val form = SignUpForm(user, name, password, repeat)
    // Los avisos salen en cuanto se escribe en el campo, como en el diseño.
    val userIssue = if (user.isEmpty()) null else Username.parse(user).exceptionOrNull()?.message
    val tooShort = password.isNotEmpty() && password.length < SignUpForm.MIN_PASSWORD
    val mismatch = repeat.isNotEmpty() && repeat != password
    StmScreen(
        topBar = { TopBar("Crear cuenta", onNav = nav::back) },
        bottomBar = {
            Box(Modifier.fillMaxWidth().background(c.surface).navigationBarsPadding().padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 8.dp)) {
                Btn(
                    "Crear cuenta", { action.run { session.signUp(form) } }, Modifier.fillMaxWidth(), large = true,
                    enabled = form.firstIssue == null && !action.busy,
                )
            }
        },
    ) {
        Spacer(Modifier.height(8.dp))
        Text("Solo te pedimos un usuario y una contraseña. No usamos tu correo.", style = StmType.bodyLarge, color = c.onSurfaceVariant)
        Spacer(Modifier.height(16.dp))
        OutlinedField("Nombre", name, { name = it }, supporting = "Así te verá tu pareja en el hogar")
        Spacer(Modifier.height(16.dp))
        OutlinedField(
            "Usuario", user, { user = it }, error = userIssue != null,
            supporting = userIssue ?: "Letras y números, sin espacios",
        )
        Spacer(Modifier.height(16.dp))
        OutlinedField(
            "Contraseña", password, { password = it }, password = true, error = tooShort,
            trailing = if (tooShort) StmIcons.error else null,
            supporting = if (tooShort) "Usa al menos ${SignUpForm.MIN_PASSWORD} caracteres" else null,
        )
        Spacer(Modifier.height(16.dp))
        OutlinedField(
            "Repite la contraseña", repeat, { repeat = it }, password = true, placeholder = "Contraseña",
            error = mismatch || action.error != null,
            supporting = action.error ?: if (mismatch) "Las contraseñas no coinciden." else null,
        )
    }
}

/** 03 Tu hogar: crear un hogar nuevo o unirse con código o QR. */
@Composable
fun Pantalla03(nav: Nav) {
    val c = Stm.colors
    val session = LocalSession.current
    val create = rememberAction()
    val join = rememberAction()
    var code by remember { mutableStateOf(session.pendingInvite?.value ?: "") }
    val parsed = InviteCode.parse(code)
    StmScreen(
        topBar = {
            TopBar(null, navIcon = null)
            LargeTitle("Tu hogar", "Un hogar reúne las cuentas que compartís")
        },
    ) {
        OptionCard(StmIcons.homeWork, c.secondaryContainer, c.onSecondaryContainer, "Crear un hogar nuevo",
            "Empieza de cero y después invita a tu pareja con un código o un QR.") {
            create.error?.let { Text(it, Modifier.weight(1f), style = StmType.bodySmall, color = c.error) }
            Btn("Crear hogar", { create.run { session.createHousehold("Casa de ${session.profile?.name ?: "todos"}") } }, enabled = !create.busy)
        }
        Spacer(Modifier.height(16.dp))
        OptionCard(StmIcons.qrCodeScanner, c.tertiaryContainer, c.onTertiaryContainer, "Unirme a un hogar",
            "Escanea el QR de tu pareja o escribe su código de 6 letras.",
            field = {
                OutlinedField(
                    "Código", code, { code = it }, labelBackground = c.surfaceContainerLowest,
                    error = join.error != null, supporting = join.error,
                )
            },
        ) {
            Btn("Escanear QR", null, kind = BtnKind.Outlined, icon = StmIcons.qrCodeScanner)
            Btn("Unirme", { parsed?.let { join.run { session.join(it) } } }, kind = BtnKind.Tonal, enabled = parsed != null && !join.busy)
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
    actions: @Composable RowScope.() -> Unit,
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
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End), verticalAlignment = Alignment.CenterVertically) { actions() }
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
        val session = LocalSession.current
        val me = session.profile?.id
        val members by produceState(emptyList<HouseholdMember>(), session.household) {
            value = session.household?.let { h -> runCatching { session.backend.members(h.id) }.getOrDefault(emptyList()) }.orEmpty()
                .sortedBy { it.profile.id != me }
        }
        ListCard {
            ListHeader("Miembros")
            members.forEachIndexed { i, m ->
                if (i > 0) Divider()
                val role = if (m.role == MemberRole.Owner) "creó el hogar" else "miembro"
                ListItem(
                    m.profile.name, if (m.profile.id == me) "Tú · $role" else role.replaceFirstChar { it.uppercase() },
                    leading = { Avatar(m.profile.name.take(1).uppercase()) },
                    // El diseño deja 24 dp a la derecha del icono final.
                    trailing = if (m.profile.id == me) null else ({ StmIcon(StmIcons.moreVert, c.onSurfaceVariant, Modifier.padding(end = 8.dp)) }),
                )
            }
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

/** 29 Invitar a tu pareja: QR, código de 6 caracteres y botones para copiar o compartir. */
@Composable
fun Pantalla29(nav: Nav) {
    val c = Stm.colors
    val session = LocalSession.current
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    // Reutiliza la invitación pendiente si la hay; si no, pide una nueva al servidor.
    val invite by produceState<HouseholdInvite?>(null, session.household) {
        value = session.household?.let { h ->
            runCatching { session.backend.pendingInvites(h.id).firstOrNull() ?: session.backend.createInvite(h.id) }.getOrNull()
        }
    }
    val code = invite?.code?.let(InviteCode::parse)
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
            if (code != null) QrCode(code.link)
        }
        Spacer(Modifier.height(24.dp))
        Text("O escribe el código", Modifier.fillMaxWidth(), style = StmType.labelMedium, color = c.onSurfaceVariant, textAlign = TextAlign.Center)
        Spacer(Modifier.height(8.dp))
        Row(Modifier.align(Alignment.CenterHorizontally), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            (code?.value ?: "······").forEach { ch ->
                Box(
                    Modifier.size(44.dp, 56.dp).clip(RoundedCornerShape(8.dp)).background(c.surfaceContainerHighest),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(ch.toString(), style = StmType.headlineMediumWide, color = c.onSurface)
                }
            }
        }
        Spacer(Modifier.height(8.dp))
        val hours = invite?.let { Duration.between(Instant.now(), Instant.parse(it.expiresAt)).toHours().coerceAtLeast(1) }
        Text(if (hours == null) "" else "Caduca en $hours ${if (hours == 1L) "hora" else "horas"}", Modifier.fillMaxWidth(), style = StmType.bodySmall, color = c.onSurfaceVariant, textAlign = TextAlign.Center)
        Spacer(Modifier.height(24.dp))
        Row(Modifier.align(Alignment.CenterHorizontally), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Btn("Copiar código", code?.let { { clipboard.setText(AnnotatedString(it.value)) } }, kind = BtnKind.Tonal, icon = StmIcons.contentCopy)
            Btn("Compartir enlace", code?.let {
                {
                    val send = Intent(Intent.ACTION_SEND).setType("text/plain")
                        .putExtra(Intent.EXTRA_TEXT, "Únete a nuestro hogar en Save the Money: ${it.link} (código ${it.value})")
                    context.startActivity(Intent.createChooser(send, "Compartir enlace"))
                }
            }, kind = BtnKind.Outlined, icon = StmIcons.share)
        }
    }
}

/**
 * QR real del enlace de invitación (zxing), en tinta sobre papel. Los tres buscadores se pintan
 * redondeados como en el diseño; su geometría no cambia, así que se sigue leyendo.
 */
@Composable
private fun QrCode(text: String) {
    val matrix = remember(text) {
        QRCodeWriter().encode(text, BarcodeFormat.QR_CODE, 0, 0, mapOf(EncodeHintType.MARGIN to 0))
    }
    Canvas(Modifier.size(184.dp)) {
        val n = matrix.width
        val m = size.width / n
        for (y in 0 until n) for (x in 0 until n) {
            if (inFinder(x, y, n) || !matrix[x, y]) continue
            drawRect(Brand.ink, Offset(x * m, y * m), Size(m, m))
        }
        val far = (n - 7) * m
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
private fun inFinder(x: Int, y: Int, n: Int): Boolean {
    val far = n - 8
    return (x < 8 && y < 8) || (x >= far && y < 8) || (x < 8 && y >= far)
}
