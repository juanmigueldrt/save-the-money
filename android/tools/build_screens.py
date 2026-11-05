#!/usr/bin/env python3
"""Convierte el JSON REST del diseño (FigCraft/Figma) en el asset compacto que pinta la app.

Uso: python3 -I android/tools/build_screens.py <diseño.json> <variables.json> <salida screens.json>
Solo exporta la página «Pantallas · Claro»; el tema oscuro sale de los modos de la colección Color.
"""
import json
import sys


def hexa(c, opacity=1.0):
    a = round(c.get("a", 1) * opacity * 255)
    r, g, b = (round(c[k] * 255) for k in "rgb")
    return f"{a:02X}{r:02X}{g:02X}{b:02X}"


def paints(lst):
    out = []
    for p in lst or []:
        if not p.get("visible", True) or p["type"] != "SOLID":
            continue
        o = {"c": hexa(p["color"], p.get("opacity", 1.0))}
        var = (p.get("boundVariables") or {}).get("color")
        if var:
            o["v"] = var["id"]
            if p.get("opacity", 1.0) < 1:
                o["o"] = round(p["opacity"], 4)
        out.append(o)
    return out


# Rellenos de instancias que perdieron el vínculo a su variable en el diseño:
# se vuelven a enlazar por (nombre de capa, color claro) para que el tema oscuro los cambie.
UNBOUND = {
    ("Barra superior", "FFEFECEA"): "VariableID:1:38",  # superficie
    ("Indicador", "FFFF9D7A"): "VariableID:1:24",  # contenedor secundario
    ("Pista", "FFAA3700"): "VariableID:1:18",  # interruptor encendido: primario
    ("Tirador", "FFFFFFFF"): "VariableID:1:19",  # sobre primario
    ("Pista", "FFDED9D5"): "VariableID:1:47",  # interruptor apagado: contenedor más alto
    ("Tirador", "FF7B7672"): "VariableID:1:48",  # contorno
}


def r2(v):
    return round(v, 2)


def node(n, parent_abs):
    if not n.get("visible", True):
        return None
    ab = n["absoluteBoundingBox"]
    o = {
        "t": n["type"][0] if n["type"] != "INSTANCE" else "I",
        "n": n["name"],
        "x": r2(ab["x"] - parent_abs["x"]),
        "y": r2(ab["y"] - parent_abs["y"]),
        "w": r2(ab["width"]),
        "h": r2(ab["height"]),
    }
    f = paints(n.get("fills"))
    for p in f:
        p.setdefault("v", UNBOUND.get((n["name"], p["c"])))
        if p["v"] is None:
            del p["v"]
    if f:
        o["f"] = f
    s = paints(n.get("strokes"))
    if s and n.get("strokeWeight", 0) > 0:
        o["s"] = s
        o["sw"] = n["strokeWeight"]
        o["sa"] = n.get("strokeAlign", "INSIDE")[0]
        isw = n.get("individualStrokeWeights")
        if isw:
            o["isw"] = [isw["top"], isw["right"], isw["bottom"], isw["left"]]
    radii = n.get("rectangleCornerRadii")
    if radii and any(radii):
        o["r"] = radii
    elif n.get("cornerRadius"):
        o["r"] = [n["cornerRadius"]] * 4
    if n.get("clipsContent"):
        o["clip"] = 1
    if n.get("opacity", 1) < 1:
        o["op"] = round(n["opacity"], 4)
    fx = []
    for e in n.get("effects") or []:
        if e.get("visible", True) and e["type"] == "DROP_SHADOW":
            fx.append({"c": hexa(e["color"]), "x": e["offset"]["x"], "y": e["offset"]["y"],
                       "b": e["radius"], "sp": e.get("spread", 0)})
    if fx:
        o["fx"] = fx
    if n["type"] == "VECTOR":
        o["p"] = [g["path"] for g in n.get("fillGeometry", [])]
    if n["type"] == "TEXT":
        st = n["style"]
        o["tx"] = n["characters"]
        o["ts"] = {
            "f": "serif" if st["fontFamily"].startswith("Source Serif") else "sans",
            "w": st.get("fontWeight", 400),
            "s": st["fontSize"],
            "lh": st.get("lineHeightPx"),
            "ls": st.get("letterSpacing", 0),
            "a": st.get("textAlignHorizontal", "LEFT")[0],
            "ar": st.get("textAutoResize", "NONE")[0],
        }
    kids = [k for k in (node(c, ab) for c in n.get("children", [])) if k]
    if kids:
        o["k"] = kids
    return o


def colors(variables_path):
    data = json.load(open(variables_path))
    meta = data.get("meta", data)
    vars_ = meta["variables"]
    cols = meta["variableCollections"]
    color_col = next(c for c in cols.values() if c["name"] == "Color")
    modes = {m["name"]: m["modeId"] for m in color_col["modes"]}

    def resolve(vid, mode, depth=0):
        v = vars_[vid]
        val = v["valuesByMode"].get(mode) or next(iter(v["valuesByMode"].values()))
        if isinstance(val, dict) and val.get("type") == "VARIABLE_ALIAS":
            target = vars_[val["id"]]
            tmode = mode if target["variableCollectionId"] == v["variableCollectionId"] else next(iter(target["valuesByMode"]))
            return resolve(val["id"], tmode, depth + 1)
        return hexa(val)

    out = {"light": {}, "dark": {}}
    for vid, v in vars_.items():
        if v["resolvedType"] != "COLOR" or v["variableCollectionId"] != color_col["id"]:
            continue
        out["light"][vid] = resolve(vid, modes["Claro"])
        out["dark"][vid] = resolve(vid, modes["Oscuro"])
    return out


def main(design, variables, dest):
    d = json.load(open(design))
    page = next(p for p in d["document"]["children"] if p["name"] == "Pantallas · Claro")
    screens = []
    for fr in page["children"]:
        ab = fr["absoluteBoundingBox"]
        screens.append(node(fr, ab) | {"x": 0, "y": 0})
    out = {"screens": screens, "colors": colors(variables)}
    json.dump(out, open(dest, "w"), ensure_ascii=False, separators=(",", ":"))
    print(f"{len(screens)} pantallas, {len(out['colors']['light'])} colores -> {dest}")


if __name__ == "__main__":
    main(*sys.argv[1:4])
