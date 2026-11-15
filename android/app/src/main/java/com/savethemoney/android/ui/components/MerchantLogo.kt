package com.savethemoney.android.ui.components

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.savethemoney.android.data.MerchantDirectory
import com.savethemoney.android.ui.theme.Stm
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

/**
 * Logo del comercio reconocido en la descripción; si no hay, el icono de la categoría.
 * Sólo el dominio del comercio (p. ej. apple.com) sale del móvil para pedir el logo.
 */
@Composable
fun MerchantLogo(
    description: String,
    fallback: ImageVector,
    container: Color = Stm.colors.secondaryContainer,
    tint: Color = Stm.colors.onSecondaryContainer,
    size: Dp = 40.dp,
) {
    val context = LocalContext.current
    val domain = MerchantDirectory.match(description)?.domain
    val logo by produceState<Bitmap?>(null, domain) { value = domain?.let { LogoCache.get(context, it) } }
    val bitmap = logo
    if (bitmap == null) {
        LeadIcon(fallback, container, tint, size)
    } else {
        Box(Modifier.size(size).clip(CircleShape).background(Stm.colors.surfaceContainerHighest), contentAlignment = Alignment.Center) {
            Image(bitmap.asImageBitmap(), null, Modifier.size(size).padding(size * 0.2f))
        }
    }
}

/** Cada dominio se descarga una vez y se guarda en la caché de la app. Si falla, se reintenta al reabrir. */
object LogoCache {
    private val memory = HashMap<String, Bitmap>()
    private val failed = HashSet<String>()
    private val lock = Mutex()

    suspend fun get(context: Context, domain: String): Bitmap? = lock.withLock {
        memory[domain]?.let { return it }
        if (domain in failed) return null
        val bitmap = withContext(Dispatchers.IO) { load(File(context.cacheDir, "logos"), domain) }
        if (bitmap == null) failed += domain else memory[domain] = bitmap
        bitmap
    }

    private fun load(folder: File, domain: String): Bitmap? {
        val file = File(folder, "$domain.png")
        if (file.exists()) BitmapFactory.decodeFile(file.path)?.let { return it }
        val url = MerchantDirectory.all.firstOrNull { it.domain == domain }?.logoUrl ?: return null
        return runCatching {
            val conn = URL(url).openConnection() as HttpURLConnection
            conn.connectTimeout = 5000
            conn.readTimeout = 5000
            conn.useCaches = false
            try {
                if (conn.responseCode != 200) return null
                val bytes = conn.inputStream.use { it.readBytes() }
                val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return null
                folder.mkdirs()
                file.writeBytes(bytes)
                bmp
            } finally {
                conn.disconnect()
            }
        }.getOrNull()
    }
}
