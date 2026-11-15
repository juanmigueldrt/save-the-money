#!/usr/bin/env python3
"""Imprime el árbol de una pantalla del diseño en texto legible, para maquetarla en Compose.

Uso: python3 -I android/tools/dump_screen.py <número 1-34> [screens.json] [variables.json]
Cada línea: nombre, tipo, x,y relativos a la madre, ancho×alto, rellenos y trazos (rol de color),
radios, texto y su estilo (fuente peso tamaño/alto-de-línea).
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
screens = sys.argv[2] if len(sys.argv) > 2 else HERE.parent / "design/screens.json"
variables = sys.argv[3] if len(sys.argv) > 3 else HERE.parents[2] / "figcraft/android/estilo-monarch-android.variables.json"

names = {k: v["name"].split("/")[-1] for k, v in json.load(open(variables))["meta"]["variables"].items()}
d = json.load(open(screens))


def paint(lst, opacity_key=True):
    out = []
    for p in lst:
        s = names.get(p.get("v"), "#" + p["c"])
        if p.get("o", 1) != 1:
            s += f"@{p['o']}"
        out.append(s)
    return ",".join(out)


def walk(n, dep):
    bits = [f"{n['n']} [{n['t']}] {n.get('x', 0):g},{n.get('y', 0):g} {n['w']:g}×{n['h']:g}"]
    if n.get("f"):
        bits.append("fill=" + paint(n["f"]))
    if n.get("s"):
        bits.append(f"stroke={paint(n['s'])}/{n.get('sw')}")
    if n.get("r"):
        bits.append(f"r={n['r']}")
    if n.get("fx"):
        bits.append("shadow")
    if n.get("op", 1) != 1:
        bits.append(f"op={n['op']}")
    if "tx" in n:
        t = n["ts"]
        bits.append(f"«{n['tx']}» {t['f']} {t['w']} {t['s']}/{t.get('lh')} ls={t.get('ls', 0)} {t['a']}")
    if n["t"] == "V":
        bits.append("(vector)")
    print("  " * dep + " ".join(bits))
    if n["t"] == "V":
        return
    for c in n.get("k", []):
        walk(c, dep + 1)


walk(d["screens"][int(sys.argv[1]) - 1], 0)
