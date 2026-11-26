package com.savethemoney.android.data

import io.github.jan.supabase.postgrest.exception.PostgrestRestException
import io.ktor.client.HttpClient
import io.ktor.client.call.HttpClientCall
import io.ktor.client.engine.okhttp.OkHttp
import io.ktor.client.request.HttpRequestData
import io.ktor.client.request.HttpResponseData
import io.ktor.client.statement.HttpResponse
import io.ktor.http.ContentType
import io.ktor.http.Headers
import io.ktor.http.HttpMethod
import io.ktor.http.HttpProtocolVersion
import io.ktor.http.HttpStatusCode
import io.ktor.http.Url
import io.ktor.http.content.TextContent
import io.ktor.util.Attributes
import io.ktor.util.date.GMTDate
import io.ktor.utils.io.ByteReadChannel
import io.ktor.utils.io.InternalAPI
import kotlinx.coroutines.Job
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import java.io.IOException
import kotlin.coroutines.EmptyCoroutineContext

/**
 * ORC-72: la línea del registro lleva la operación, el tipo, el código y el estado HTTP, y nada más. Los errores de
 * estas pruebas llevan datos personales inventados en el mensaje o el valor: ninguno puede salir.
 */
class RegistroDeErroresTest {
    private val personales = listOf("Carmen", "López", "1234,56", "regalo", "carmen@example.com", "K7Q2-9XPA")

    private fun sinDatosPersonales(linea: String) {
        for (dato in personales) assertFalse("«$dato» ha salido en: $linea", dato in linea)
    }

    /** Una respuesta de verdad, sin red: sólo su estado y la petición que RestException cita en su mensaje. */
    @OptIn(InternalAPI::class)
    private fun respuesta(estado: Int): HttpResponse {
        val cliente = HttpClient(OkHttp)
        val peticion = HttpRequestData(
            Url("https://example.invalid/rest/v1/rpc/create_movement"),
            HttpMethod.Post,
            Headers.Empty,
            TextContent("{\"p_note\":\"regalo para Carmen López\"}", ContentType.Application.Json),
            Job(),
            Attributes(),
        )
        val datos = HttpResponseData(HttpStatusCode.fromValue(estado), GMTDate(), Headers.Empty, HttpProtocolVersion.HTTP_1_1, ByteReadChannel.Empty, EmptyCoroutineContext)
        return HttpClientCall(cliente, peticion, datos).response
    }

    @Test
    fun postgresDesconocidoGuardaCodigoYTipoSinElMensaje() {
        val error = PostgrestRestException(
            message = "nota «regalo» de Carmen López por 1234,56",
            hint = "K7Q2-9XPA",
            details = JsonPrimitive("Failing row contains (Carmen López, 1234,56, carmen@example.com)."),
            code = "XX000",
            response = respuesta(400),
        )
        val linea = lineaDeError("createMovement", error)
        assertEquals("operacion=createMovement tipo=PostgrestRestException codigo=XX000 http=400", linea)
        sinDatosPersonales(linea)
    }

    @Test
    fun appErrorSoloElNombreDelCaso() {
        val validacion = lineaDeError("op", AppError.InvalidInput("Carmen López debe 1234,56"))
        assertEquals("operacion=op tipo=AppError.InvalidInput", validacion)
        sinDatosPersonales(validacion)
        assertEquals("operacion=op tipo=AppError.Network", lineaDeError("op", AppError.Network))
        assertEquals("operacion=op tipo=AppError.Unknown codigo=app", lineaDeError("op", AppError.Unknown("app")))
    }

    @Test
    fun errorCualquieraSoloElTipo() {
        val linea = lineaDeError("Action.run", IllegalStateException("regalo para Carmen López, 1234,56"))
        assertEquals("operacion=Action.run tipo=IllegalStateException", linea)
        assertEquals("operacion=op tipo=IOException", lineaDeError("op", IOException("carmen@example.com")))
    }

    @Test
    fun unCodigoConTextoNoPasaEntero() {
        val linea = lineaDeError("op", AppError.Unknown("XX000 Carmen López 1234,56 regalo carmen@example.com K7Q2-9XPA"))
        assertEquals("operacion=op tipo=AppError.Unknown codigo=no_valido", linea)
        sinDatosPersonales(linea)
    }
}
