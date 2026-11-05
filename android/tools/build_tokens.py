#!/usr/bin/env python3
"""Genera el código Kotlin de los tokens del diseño: los 6 temas de color y los iconos.

Uso: python3 -I android/tools/build_tokens.py <variables.json> <screens.json> <carpeta java del paquete ui>
Lee la colección Color (6 modos) del JSON de variables y los iconos (vectores) de screens.json,
que sale de build_screens.py. No se edita a mano: se vuelve a generar.
"""
import json
import re
import sys
from pathlib import Path

MODES = {
    "Claro": "claro",
    "Oscuro": "oscuro",
    "Claro · contraste medio": "claroMedio",
    "Oscuro · contraste medio": "oscuroMedio",
    "Claro · contraste alto": "claroAlto",
    "Oscuro · contraste alto": "oscuroAlto",
}
HEADER = "// Generado por android/tools/build_tokens.py desde el diseño de FigCraft. No editar a mano.\n"


def hexa(c):
    a = round(c.get("a", 1) * 255)
    r, g, b = (round(c[k] * 255) for k in "rgb")
    return f"0x{a:02X}{r:02X}{g:02X}{b:02X}"


def camel(name):
    parts = re.split(r"[-/ ]", name.split("/")[-1])
    return parts[0] + "".join(p[:1].upper() + p[1:] for p in parts[1:])


def palette(variables_path, out_dir):
    meta = json.load(open(variables_path)).get("meta")
    vars_, cols = meta["variables"], meta["variableCollections"]
    col = next(c for c in cols.values() if c["name"] == "Color")
    modes = {m["name"]: m["modeId"] for m in col["modes"]}

    def resolve(vid, mode):
        v = vars_[vid]
        val = v["valuesByMode"].get(mode) or next(iter(v["valuesByMode"].values()))
        if isinstance(val, dict) and val.get("type") == "VARIABLE_ALIAS":
            t = vars_[val["id"]]
            tmode = mode if t["variableCollectionId"] == v["variableCollectionId"] else next(iter(t["valuesByMode"]))
            return resolve(val["id"], tmode)
        return hexa(val)

    roles = [(vid, camel(v["name"])) for vid, v in vars_.items()
             if v["resolvedType"] == "COLOR" and v["variableCollectionId"] == col["id"] and v["name"].startswith("rol/")]
    props = "\n".join(f"    val {name}: Color," for _, name in roles)
    schemes = []
    for mname, kname in MODES.items():
        args = "\n".join(f"        {name} = Color({resolve(vid, modes[mname])})," for vid, name in roles)
        schemes.append(f"    val {kname} = StmColors(\n{args}\n    )")
    code = (HEADER + "package com.savethemoney.android.ui.theme\n\nimport androidx.compose.ui.graphics.Color\n\n"
            "/** Roles de color del diseño (colección Color, grupo «rol»). */\n"
            f"data class StmColors(\n{props}\n)\n\n"
            "/** Los 6 modos del diseño: claro y oscuro, con contraste normal, medio y alto. */\n"
            "object Palettes {\n" + "\n\n".join(schemes) + "\n}\n")
    (out_dir / "theme" / "Palette.kt").write_text(code)
    return len(roles)


def icons(screens_path, out_dir):
    d = json.load(open(screens_path))
    seen = {}  # nombre -> {trazado: [vector, usos]}

    def walk(n, parent):
        if n.get("t") == "V" and parent and re.fullmatch(r"[a-z_0-9]+", parent["n"]) and n.get("p"):
            v = seen.setdefault(parent["n"], {}).setdefault((n["w"], json.dumps(n["p"])), [n, 0])
            v[1] += 1
        for c in n.get("k", []):
            walk(c, n)

    for s in d["screens"]:
        walk(s, None)
    found = {}
    for name, variants in seen.items():
        w = max(k[0] for k in variants)  # el de 24 dp antes que el de 18
        big = sorted((v for k, v in variants.items() if k[0] == w), key=lambda v: -v[1])
        found[name] = big[0][0]
        if len(big) > 1:  # p. ej. «home» relleno solo en la pestaña seleccionada
            found[name + "_filled"] = big[1][0]
    entries = []
    for name, n in sorted(found.items()):
        paths = ", ".join(json.dumps(p) for p in n["p"])
        entries.append(f"    val {camel(name.replace('_', '-'))} by lazy {{ icon(\"{name}\", {n['w']}f, {n['h']}f, {paths}) }}")
    code = (HEADER + "package com.savethemoney.android.ui.icons\n\n"
            "import androidx.compose.ui.graphics.SolidColor\n"
            "import androidx.compose.ui.graphics.vector.ImageVector\n"
            "import androidx.compose.ui.graphics.vector.addPathNodes\n"
            "import androidx.compose.ui.unit.dp\n"
            "import androidx.compose.ui.graphics.Color\n\n"
            "/** Iconos Material Symbols Rounded tal como están en el diseño (trazados en su caja). */\n"
            "object StmIcons {\n" + "\n".join(entries) + "\n}\n\n"
            "private fun icon(name: String, w: Float, h: Float, vararg paths: String): ImageVector =\n"
            "    ImageVector.Builder(name, 24.dp, 24.dp, w, h).apply {\n"
            "        paths.forEach { addPath(addPathNodes(it), fill = SolidColor(Color.Black)) }\n"
            "    }.build()\n")
    (out_dir / "icons" / "StmIcons.kt").write_text(code)
    return len(found)


if __name__ == "__main__":
    out = Path(sys.argv[3])
    (out / "theme").mkdir(parents=True, exist_ok=True)
    (out / "icons").mkdir(parents=True, exist_ok=True)
    print(f"{palette(sys.argv[1], out)} roles × 6 modos, {icons(sys.argv[2], out)} iconos -> {out}")
