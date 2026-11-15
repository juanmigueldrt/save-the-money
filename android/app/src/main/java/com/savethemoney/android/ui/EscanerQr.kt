package com.savethemoney.android.ui

import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.zxing.BinaryBitmap
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.ReaderException
import com.google.zxing.common.HybridBinarizer
import com.google.zxing.qrcode.QRCodeReader
import java.util.concurrent.Executors

/** Lee un QR de una imagen en luminancia; null si en ese fotograma no se distingue ninguno. */
fun leerQr(luma: ByteArray, ancho: Int, alto: Int): String? = try {
    val fuente = PlanarYUVLuminanceSource(luma, ancho, alto, 0, 0, ancho, alto, false)
    QRCodeReader().decode(BinaryBitmap(HybridBinarizer(fuente))).text
} catch (_: ReaderException) {
    null
}

private fun ImageProxy.luminancia(): ByteArray {
    val plano = planes[0]
    val salida = ByteArray(width * height)
    // La fila de la cámara puede ser más larga que el ancho de la imagen.
    for (fila in 0 until height) {
        plano.buffer.position(fila * plano.rowStride)
        plano.buffer.get(salida, fila * width, width)
    }
    return salida
}

/** Vista previa de la cámara trasera que avisa con el texto de cada QR que lee. */
@Composable
fun CamaraQr(modifier: Modifier, onTexto: (String) -> Unit, onError: () -> Unit) {
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    val texto by rememberUpdatedState(onTexto)
    val fallo by rememberUpdatedState(onError)
    val hilo = remember { Executors.newSingleThreadExecutor() }
    val proveedor = remember { ProcessCameraProvider.getInstance(context) }
    DisposableEffect(Unit) {
        onDispose {
            if (proveedor.isDone) proveedor.get().unbindAll()
            hilo.shutdown()
        }
    }
    AndroidView(
        modifier = modifier,
        factory = { ctx ->
            val vista = PreviewView(ctx)
            val principal = ContextCompat.getMainExecutor(ctx)
            proveedor.addListener({
                val preview = Preview.Builder().build().also { it.surfaceProvider = vista.surfaceProvider }
                val analisis = ImageAnalysis.Builder().setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
                analisis.setAnalyzer(hilo) { imagen ->
                    imagen.use {
                        leerQr(it.luminancia(), it.width, it.height)?.let { leido -> principal.execute { texto(leido) } }
                    }
                }
                try {
                    proveedor.get().bindToLifecycle(owner, CameraSelector.DEFAULT_BACK_CAMERA, preview, analisis)
                } catch (_: IllegalArgumentException) {
                    fallo() // Sin cámara trasera.
                }
            }, principal)
            vista
        },
    )
}
