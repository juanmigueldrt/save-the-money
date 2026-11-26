#!/usr/bin/env python3
"""ORC-146: manda al Supabase local los filtros de PostgREST que construyen las apps y mira qué filas vuelven.

Las cadenas salen de testdata/vectors/postgrest_filters.json, el mismo fichero que leen las pruebas de STMData
(BusquedaEnServidorTests) y de Android (BusquedaEnServidorTest): si aquí pasan, lo que mandan las apps funciona contra
un PostgREST de verdad.

Comprueba:
  - qué movimientos devuelve cada búsqueda (comodines, comillas, barras, comas, paréntesis, puntos, emoji);
  - que el cursor recorre la lista entera, página a página, sin repetir ni saltarse filas;
  - que dos or=(…) en la misma petición se juntan con AND (búsqueda y cursor);
  - que una lista de más de 1000 filas (aportaciones a una meta, ORC-65) se pide entera con order + offset/limit.

Uso, con el Supabase local arrancado (`supabase start`): python3 supabase/tests/api/filtros_postgrest.py
Sólo usa la URL y la clave anónima que imprime `supabase status`. Crea un usuario normal con la API de auth local y hace
todas las consultas con su sesión, así que el RLS se aplica como en la app. Datos inventados. Al final borra los
movimientos de prueba; si se corta a medias, `supabase db reset` deja la base limpia para repetirlo.

Escribe una línea por comprobación y, si alguna falla, sale con código 1 al final (no en el primer fallo).
"""

import json
import pathlib
import secrets
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[3]
VECTORS = json.loads((ROOT / "testdata/vectors/postgrest_filters.json").read_text(encoding="utf-8"))
PAGE = 5  # filas por página al recorrer la lista con el cursor: obliga a cortar dentro de un mismo día
CONTRIBUTIONS = 2001  # más de dos páginas de 1000 (max_rows de supabase/config.toml)

failures = 0


def check(name, request, expected, received):
    global failures
    ok = expected == received
    if not ok:
        failures += 1
    print(f"{'OK   ' if ok else 'FALLO'} {name}\n      petición: {request}\n      esperado: {expected}\n      recibido: {received}",
          flush=True)


def local_status():
    result = subprocess.run(["supabase", "status", "-o", "json"], cwd=ROOT, capture_output=True, text=True)
    if result.returncode != 0 or "{" not in result.stdout:
        sys.exit(f"`supabase status` falló (¿está arrancado el Supabase local?): {result.stderr.strip()}")
    status = json.loads(result.stdout[result.stdout.index("{"):])
    key = status.get("ANON_KEY") or status.get("PUBLISHABLE_KEY")
    if not status.get("API_URL") or not key:
        sys.exit(f"`supabase status` no trae API_URL y ANON_KEY/PUBLISHABLE_KEY; claves que trae: {sorted(status)}")
    return status["API_URL"].rstrip("/"), key


API, APIKEY = local_status()


def call(method, path, query=(), body=None, token=None, prefer=None):
    """Devuelve (código HTTP, JSON o texto). `query` es una lista de pares: se pueden repetir nombres, como `or`."""
    url = API + path + ("?" + urllib.parse.urlencode(list(query), quote_via=urllib.parse.quote, safe="") if query else "")
    headers = {"apikey": APIKEY, "Content-Type": "application/json", "Authorization": f"Bearer {token or APIKEY}"}
    if prefer:
        headers["Prefer"] = prefer
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            code, text = response.status, response.read().decode()
    except urllib.error.HTTPError as error:
        code, text = error.code, error.read().decode()
    try:
        return code, json.loads(text) if text else None
    except ValueError:
        return code, text


def shown(path, query):
    """La petición como se lee, sin codificar."""
    return path + "?" + "&".join(f"{k}={v}" for k, v in query)


def must(what, code, body, ok=(200, 201, 204)):
    if code not in ok:
        sys.exit(f"No se pudo {what}: HTTP {code} {body}")
    return body


# Un usuario normal, como el de la app (el email es sintético y no se confirma en local).
tag = secrets.token_hex(4)
_, session = call("POST", "/auth/v1/signup", body={
    "email": f"filtros-{tag}@savethemoney.invalid",
    "password": secrets.token_urlsafe(18),
    "data": {"username": f"filtros-{tag}"},
})
token = (session or {}).get("access_token") if isinstance(session, dict) else None
if not token:
    sys.exit(f"El alta del usuario de prueba no devolvió sesión: {session}")

household = must("crear el hogar", *call("POST", "/rest/v1/rpc/create_household", body={"household_name": "Hogar de prueba"},
                                          token=token))
household_id = (household[0] if isinstance(household, list) else household)["id"]
account = must("crear la cuenta", *call("POST", "/rest/v1/accounts", body={"household_id": household_id, "name": "Cuenta de prueba"},
                                         token=token, prefer="return=representation"))
account_id = account[0]["id"]

movements = VECTORS["movements"]
key_of = {m["id"].lower(): m["key"] for m in movements}
by_key = {m["key"]: m for m in movements}
order = VECTORS["cursorOrder"]
must("guardar los movimientos", *call("POST", "/rest/v1/transactions", token=token, prefer="return=minimal", body=[
    {"id": m["id"].lower(), "household_id": household_id, "account_id": account_id, "booked_on": m["bookedOn"],
     "amount_minor": m["amountMinor"], "description": m["description"], "notes": m["notes"], "payee": m["payee"],
     "tags": m["tags"]}
    for m in movements
]))

LIST = [("select", "id"), ("household_id", f"eq.{household_id}"), ("order", "booked_on.desc,id.desc")]


def movement_keys(query):
    code, body = call("GET", "/rest/v1/transactions", query, token=token)
    if code != 200:
        return f"HTTP {code} {body}"
    return [key_of.get(row["id"], row["id"]) for row in body]


def in_list_order(keys):
    return sorted(keys, key=order.index)


# 1. Búsquedas: lo que va en or=(…) es exactamente lo que construyen searchFilter / movementSearchFilter.
for vector in VECTORS["search"]:
    query = LIST + [("or", f"({vector['filter']})")]
    check(f"búsqueda «{vector['input']}»: {vector['name']}", shown("/rest/v1/transactions", query),
          in_list_order(vector["matches"]), movement_keys(query))

# 2. El cursor recorre la lista entera sin repetir ni saltar filas.
walked, after, pages = [], None, 0
while pages < len(order) + 2:
    query = LIST + [("limit", str(PAGE))] + ([("or", f"({by_key[after]['cursor']})")] if after else [])
    page = movement_keys(query)
    pages += 1
    if isinstance(page, str):
        check(f"cursor, página {pages}", shown("/rest/v1/transactions", query), "HTTP 200", page)
        break
    print(f"      página {pages}: {shown('/rest/v1/transactions', query)} -> {page}", flush=True)
    walked += page
    if len(page) < PAGE or page[-1] not in by_key:
        break
    after = page[-1]
check(f"el cursor recorre las {len(order)} filas en orden, de {PAGE} en {PAGE}, sin repetir ni saltar",
      f"order=booked_on.desc,id.desc&limit={PAGE}&or=(cursor de la última fila)", order, walked)

# 3. Búsqueda y cursor en dos or=(…): PostgREST los junta con AND.
filters = {v["input"]: v["filter"] for v in VECTORS["search"]}
for vector in VECTORS["combined"]:
    query = LIST + [("or", f"({filters[vector['input']]})"), ("or", f"({by_key[vector['after']]['cursor']})")]
    check(f"{vector['name']} («{vector['input']}» detrás de {vector['after']})", shown("/rest/v1/transactions", query),
          in_list_order(vector["matches"]), movement_keys(query))

# 4. ORC-65: una lista de más de 1000 filas, por páginas de 1000 con order + offset/limit, como allRows / allPages.
goal = must("crear la meta", *call("POST", "/rest/v1/goals", token=token, prefer="return=representation",
                                    body={"household_id": household_id, "name": "Meta de prueba", "target_minor": 100000}))
goal_id = goal[0]["id"]
must("guardar las aportaciones", *call("POST", "/rest/v1/goal_contributions", token=token, prefer="return=minimal", body=[
    {"household_id": household_id, "goal_id": goal_id, "amount_minor": 100, "made_on": f"2026-01-{1 + i % 28:02d}"}
    for i in range(CONTRIBUTIONS)
]))
GOAL_LIST = [("select", "id,made_on"), ("household_id", f"eq.{household_id}"), ("order", "made_on.desc,id.asc")]
code, unpaged = call("GET", "/rest/v1/goal_contributions", GOAL_LIST, token=token)
check("sin offset/limit el servidor corta en max_rows (por eso las apps piden por páginas)",
      shown("/rest/v1/goal_contributions", GOAL_LIST), 1000, len(unpaged) if code == 200 else f"HTTP {code} {unpaged}")
rows, sizes = [], []
while len(sizes) < 5:
    query = GOAL_LIST + [("offset", str(len(rows))), ("limit", "1000")]
    code, page = call("GET", "/rest/v1/goal_contributions", query, token=token)
    if code != 200:
        check(f"aportaciones, página {len(sizes) + 1}", shown("/rest/v1/goal_contributions", query), "HTTP 200", f"HTTP {code} {page}")
        break
    rows += page
    sizes.append(len(page))
    if len(page) < 1000:
        break
check("aportaciones: páginas de 1000 hasta una incompleta", "offset=0,1000,2000&limit=1000", [1000, 1000, 1], sizes)
check("aportaciones: todas, sin repetir", "ids distintos recibidos", CONTRIBUTIONS, len({r["id"] for r in rows}))
expected = sorted(rows, key=lambda r: r["id"])
expected = sorted(expected, key=lambda r: r["made_on"], reverse=True)  # estable: dentro de un día, id ascendente
check("aportaciones: en el orden pedido (día descendente, id ascendente), también entre páginas", "order=made_on.desc,id.asc",
      True, [r["id"] for r in rows] == [r["id"] for r in expected])

# Limpieza: los ids de los movimientos son fijos y chocarían si se vuelve a correr sobre la misma base.
call("DELETE", "/rest/v1/transactions", [("household_id", f"eq.{household_id}")], token=token)

print(f"\n{failures} comprobaciones fallidas" if failures else "\nTodas las comprobaciones pasan", flush=True)
sys.exit(1 if failures else 0)
