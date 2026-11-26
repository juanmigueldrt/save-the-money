package com.savethemoney.android.data

import android.util.Log
import io.github.jan.supabase.auth.exception.AuthRestException
import io.github.jan.supabase.exceptions.RestException
import io.github.jan.supabase.postgrest.exception.PostgrestRestException

/*
 * Registro de fallos en el dispositivo (ORC-72): docs/decisiones/informes-de-fallos.md. Sólo fallos, nunca lo que va
 * bien, y nada sale del dispositivo.
 */

/** Apunta un fallo. Es la única forma en que la app registra errores: la línea la decide [lineaDeError]. */
fun registrarError(operacion: String, error: Throwable) {
    Log.e("STM", lineaDeError(operacion, error))
}

/**
 * Lo que va en la línea: la operación (un texto fijo del código), el tipo del error, su código y el estado HTTP. Nunca
 * el mensaje ni el cuerpo de la respuesta: los del servidor pueden citar importes, nombres o notas de la fila. En la
 * versión de tienda R8 acorta los nombres de tipo y operación; se traducen con el mapping.txt de esa versión.
 */
fun lineaDeError(operacion: String, error: Throwable): String {
    var tipo = error.javaClass.simpleName
    var codigo: String? = null
    var http: Int? = null
    when (error) {
        is AppError -> {
            tipo = "AppError.$tipo"
            if (error is AppError.Unknown) codigo = error.code
        }
        // Su `error` es el mensaje de Postgres: sólo el código.
        is PostgrestRestException -> {
            codigo = error.code
            http = error.statusCode
        }
        is AuthRestException -> {
            codigo = error.errorCode?.value
            http = error.statusCode
        }
        is RestException -> http = error.statusCode
    }
    return listOfNotNull(
        "operacion=$operacion",
        "tipo=$tipo",
        codigo?.let { "codigo=${codigoSeguro(it)}" },
        http?.let { "http=$it" },
    ).joinToString(" ")
}

/** Un código es una palabra corta (`23505`, `PGRST301`, `invalid_credentials`). Si el servidor metiera ahí un texto, no sale nada de él. */
private fun codigoSeguro(codigo: String): String =
    if (codigo.length <= 40 && codigo.all { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it == '_' || it == '-' }) codigo else "no_valido"
