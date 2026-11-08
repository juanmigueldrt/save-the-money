package com.savethemoney.android.ui

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.pdf.PdfDocument
import android.text.TextPaint
import android.text.TextUtils
import androidx.core.content.FileProvider
import com.savethemoney.android.data.Money
import com.savethemoney.android.data.MonthlyBills
import com.savethemoney.android.data.RecurringKind
import java.io.File
import java.time.LocalDate

/** Fichero nuevo en la caché de exportar; cada exportación borra la anterior para no dejar datos atrás. */
fun ficheroExportar(context: Context, nombre: String): File {
    val carpeta = File(context.cacheDir, "exportar")
    carpeta.deleteRecursively()
    carpeta.mkdirs()
    return File(carpeta, nombre)
}

/** Abre el menú de compartir del sistema con el fichero. */
fun compartir(context: Context, fichero: File, tipo: String) {
    val uri = FileProvider.getUriForFile(context, "${context.packageName}.archivos", fichero)
    val envio = Intent(Intent.ACTION_SEND).setType(tipo).putExtra(Intent.EXTRA_STREAM, uri).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    context.startActivity(Intent.createChooser(envio, fichero.name))
}

/** Hoja A4 de los pagos del mes, siempre en claro, para imprimir; sigue en otra página si no cabe. */
fun escribirPdfPagos(bills: MonthlyBills, hogar: String, hoy: LocalDate, destino: File) {
    val ancho = 595
    val alto = 842
    val margen = 40f
    val tinta = Color.rgb(0x22, 0x20, 0x1D)
    val gris = Color.rgb(0x6F, 0x6A, 0x63)
    val texto = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { color = tinta; textSize = 11f }
    val nota = TextPaint(texto).apply { color = gris; textSize = 10f }
    val titulo = TextPaint(texto).apply { typeface = Typeface.SERIF; textSize = 24f }
    val linea = Paint().apply { color = Color.rgb(0xDD, 0xD8, 0xD2); strokeWidth = 0.5f }
    val caja = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = gris; style = Paint.Style.STROKE; strokeWidth = 1f }
    val columnas = floatArrayOf(margen, 150f, 345f)
    val derecha = 505f
    val pagado = ancho - margen
    fun corta(s: String, max: Float) = TextUtils.ellipsize(s, texto, max, TextUtils.TruncateAt.END).toString()

    val doc = PdfDocument()
    try {
        var numero = 1
        var pagina = doc.startPage(PdfDocument.PageInfo.Builder(ancho, alto, numero).create())
        var y = margen + 12f
        pagina.canvas.drawText(hogar, margen, y, nota)
        y += 30f
        pagina.canvas.drawText("Pagos de ${Fechas.mes(bills.month.atDay(1))} de ${bills.month.year}", margen, y, titulo)
        y += 24f
        pagina.canvas.drawText("Total: ${Money.format(bills.total)}", margen, y, texto)
        y += 32f

        fun cabecera() {
            pagina.canvas.run {
                drawText("Día", columnas[0], y, nota)
                drawText("Concepto", columnas[1], y, nota)
                drawText("Cuenta", columnas[2], y, nota)
                val p = TextPaint(nota).apply { textAlign = Paint.Align.RIGHT }
                drawText("Importe", derecha, y, p)
                drawText("Pagado", pagado, y, p)
            }
            y += 8f
        }
        cabecera()
        val derechaTexto = TextPaint(texto).apply { textAlign = Paint.Align.RIGHT }
        for (l in bills.lines) {
            if (y > alto - margen - 90) {
                doc.finishPage(pagina)
                numero++
                pagina = doc.startPage(PdfDocument.PageInfo.Builder(ancho, alto, numero).create())
                y = margen + 12f
                cabecera()
            }
            pagina.canvas.drawLine(margen, y, pagado, y, linea)
            y += 18f
            pagina.canvas.run {
                drawText("${l.due.dayOfMonth} de ${Fechas.mes(l.due)}", columnas[0], y, texto)
                drawText(corta(l.name, columnas[2] - columnas[1] - 8), columnas[1], y, texto)
                drawText(corta(l.accountName ?: "", derecha - columnas[2] - 76), columnas[2], y, texto)
                drawText(Money.format(l.amount), derecha, y, derechaTexto)
                drawRect(pagado - 22, y - 10, pagado - 10, y + 2, caja)
            }
            y += 10f
        }
        y += 24f
        pagina.canvas.drawText("Suscripciones", margen, y, nota)
        pagina.canvas.drawText("Esenciales", 300f, y, nota)
        y += 16f
        pagina.canvas.drawText(Money.format(bills.total(RecurringKind.Subscription)), margen, y, texto)
        pagina.canvas.drawText(Money.format(bills.total(RecurringKind.Essential)), 300f, y, texto)
        pagina.canvas.drawText("Creado con Save the Money el ${hoy.dayOfMonth} de ${Fechas.mes(hoy)} de ${hoy.year}.", margen, alto - margen, nota)
        doc.finishPage(pagina)
        destino.outputStream().use(doc::writeTo)
    } finally {
        doc.close()
    }
}
