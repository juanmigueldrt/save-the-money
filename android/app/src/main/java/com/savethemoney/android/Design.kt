package com.savethemoney.android

import org.json.JSONArray
import org.json.JSONObject

/** Pintura sólida: color fijo o enlazado a una variable de la colección Color. */
class DPaint(val argb: Long, val variable: String?, val opacity: Float)

class DShadow(val argb: Long, val x: Float, val y: Float, val blur: Float, val spread: Float)

class DText(
    val text: String,
    val serif: Boolean,
    val weight: Int,
    val size: Float,
    val lineHeight: Float?,
    val letterSpacing: Float,
    val align: Char, // L, C, R
    val autoResize: Char, // W = ancho y alto, H = alto, N = fijo
)

/** Una capa del diseño. Coordenadas en dp relativas a la capa madre. */
class DNode(
    val type: Char, // F marco, I instancia, T texto, V vector, C componente
    val name: String,
    val x: Float,
    val y: Float,
    val w: Float,
    val h: Float,
    val fills: List<DPaint>,
    val strokes: List<DPaint>,
    val strokeWeight: Float,
    val strokeAlign: Char, // I, O, C
    val sideWeights: FloatArray?, // arriba, derecha, abajo, izquierda
    val radii: FloatArray?, // sup-izq, sup-der, inf-der, inf-izq
    val clip: Boolean,
    val opacity: Float,
    val shadows: List<DShadow>,
    val paths: List<String>,
    val text: DText?,
    val children: List<DNode>,
) {
    var parent: DNode? = null
    var action: Action? = null

    fun descendants(): Sequence<DNode> = sequence {
        yield(this@DNode)
        children.forEach { yieldAll(it.descendants()) }
    }

    fun ancestors(): Sequence<DNode> = generateSequence(parent) { it.parent }

    /** Alto real del contenido (para hacer desplazable un marco que recorta). */
    val contentHeight: Float get() = children.maxOfOrNull { it.y + it.h } ?: h
}

class Design(val screens: List<DNode>, val light: Map<String, Long>, val dark: Map<String, Long>) {
    fun screen(number: Int): DNode = screens[number - 1]

    companion object {
        fun parse(json: String): Design {
            val root = JSONObject(json)
            val screens = root.getJSONArray("screens").let { a -> List(a.length()) { node(a.getJSONObject(it), null) } }
            val colors = root.getJSONObject("colors")
            return Design(screens, colorMap(colors.getJSONObject("light")), colorMap(colors.getJSONObject("dark")))
        }

        private fun colorMap(o: JSONObject): Map<String, Long> =
            o.keys().asSequence().associateWith { o.getString(it).toLong(16) }

        private fun paints(a: JSONArray?): List<DPaint> =
            if (a == null) emptyList() else List(a.length()) {
                val p = a.getJSONObject(it)
                DPaint(p.getString("c").toLong(16), p.optString("v").ifEmpty { null }, p.optDouble("o", 1.0).toFloat())
            }

        private fun floats(a: JSONArray?): FloatArray? =
            a?.let { arr -> FloatArray(arr.length()) { arr.getDouble(it).toFloat() } }

        private fun node(o: JSONObject, parent: DNode?): DNode {
            val ts = o.optJSONObject("ts")
            val text = ts?.let {
                DText(
                    text = o.getString("tx"),
                    serif = it.getString("f") == "serif",
                    weight = it.getInt("w"),
                    size = it.getDouble("s").toFloat(),
                    lineHeight = if (it.isNull("lh")) null else it.getDouble("lh").toFloat(),
                    letterSpacing = it.optDouble("ls", 0.0).toFloat(),
                    align = it.getString("a")[0],
                    autoResize = it.getString("ar")[0],
                )
            }
            val fx = o.optJSONArray("fx")
            val shadows = if (fx == null) emptyList() else List(fx.length()) {
                val e = fx.getJSONObject(it)
                DShadow(
                    e.getString("c").toLong(16), e.getDouble("x").toFloat(), e.getDouble("y").toFloat(),
                    e.getDouble("b").toFloat(), e.optDouble("sp", 0.0).toFloat(),
                )
            }
            val p = o.optJSONArray("p")
            val kidsJson = o.optJSONArray("k")
            val kids = mutableListOf<DNode>()
            val n = DNode(
                type = o.getString("t")[0],
                name = o.getString("n"),
                x = o.getDouble("x").toFloat(),
                y = o.getDouble("y").toFloat(),
                w = o.getDouble("w").toFloat(),
                h = o.getDouble("h").toFloat(),
                fills = paints(o.optJSONArray("f")),
                strokes = paints(o.optJSONArray("s")),
                strokeWeight = o.optDouble("sw", 0.0).toFloat(),
                strokeAlign = o.optString("sa", "I")[0],
                sideWeights = floats(o.optJSONArray("isw")),
                radii = floats(o.optJSONArray("r")),
                clip = o.optInt("clip", 0) == 1,
                opacity = o.optDouble("op", 1.0).toFloat(),
                shadows = shadows,
                paths = if (p == null) emptyList() else List(p.length()) { p.getString(it) },
                text = text,
                children = kids,
            )
            n.parent = parent
            if (kidsJson != null) for (i in 0 until kidsJson.length()) kids += node(kidsJson.getJSONObject(i), n)
            return n
        }
    }
}
