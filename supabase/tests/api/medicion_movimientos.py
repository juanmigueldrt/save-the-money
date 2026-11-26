#!/usr/bin/env python3
"""ORC-70: mide cuánto tardan, contra el Supabase local, las peticiones con las que las apps montan hoy los resúmenes.

Para cada tamaño N (por defecto 10000 y 50000) el hogar de prueba llega a N movimientos repartidos en seis años y cuatro
cuentas, y a N/10 precios y N/10 operaciones de inversión en cinco activos. Después cronometra, tres veces cada una, las
mismas peticiones que hacen las apps, página a página (offset/limit de 1000, el `max_rows` de supabase/config.toml):

  - movimientos, iOS: `allMovements` (STMData/SupabaseFinance.swift), orden booked_on.asc,id.asc;
  - movimientos, Android: `movements(householdId, from, through)` (data/SupabaseFinance.kt) que llama TrackingModel,
    con booked_on entre 1900-01-01 y 2999-12-31 y orden booked_on.desc,id.asc;
  - precios: `holdingPrices` (iguales en las dos apps), orden priced_on.asc,id.asc;
  - operaciones: `trades` (iguales en las dos apps), orden traded_on.asc,id.asc;
  - saldos: la vista `account_balances`, orden account_id.asc.

Por cada medición escribe filas, peticiones, tiempo total, tiempo por página y bytes de respuesta. El tiempo es el de las
peticiones (enviar, esperar y leer el cuerpo entero); no cuenta el JSON que decodifica Python. Los bytes son los del
cuerpo sin comprimir: urllib no pide gzip. Son tiempos de una máquina con el Supabase local, no de un móvil.

Los datos se cargan por la API, en lotes de 1000 filas por petición, con la sesión de un usuario normal: pasan por el RLS
y por las mismas restricciones que los de la app, y se leen igual que se leerían los de un hogar real. La carga no se
cronometra. Comprueba además que llegan todas las filas y que la suma de los movimientos y los saldos coinciden con lo
cargado; si algo no cuadra sale con código 1 (después de escribir la tabla).

Uso, con el Supabase local arrancado (`supabase start`):
  python3 supabase/tests/api/medicion_movimientos.py [tamaños separados por comas, p. ej. 10000,50000]
Sólo usa la URL y la clave anónima que imprime `supabase status`. Datos inventados, en un hogar nuevo en cada ejecución.
Si existe la variable GITHUB_STEP_SUMMARY, añade la tabla al resumen del job.
"""

import datetime
import json
import os
import pathlib
import random
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[3]
PAGE = 1000  # max_rows de supabase/config.toml, el mismo tamaño de página que usan las apps
BATCH = 1000  # filas por petición al cargar los datos de prueba
RUNS = 3
ACCOUNTS = 4
HOLDINGS = 5
FIRST_DAY = datetime.date(2020, 1, 1)
SPAN_DAYS = 6 * 365  # seis años de movimientos

# Las columnas de SupabaseFinance.swift / SupabaseInvestments.swift (iguales en data/SupabaseFinance.kt).
MOVEMENT = ("id,household_id,account_id,category_id,booked_on,amount_minor,description,notes,import_hash,excluded,"
            "reviewed_at,payee,tags,updated_at,transfer_id")
PRICE = "id,household_id,holding_id,priced_on,price"
TRADE = "id,household_id,holding_id,traded_on,side,quantity,price,fee_minor,note"
DESCRIPTIONS = ["Supermercado", "Gasolina", "Farmacia", "Restaurante", "Luz", "Agua", "Internet", "Ropa", "Cine",
                "Panadería", "Transporte", "Seguro", "Regalo", "Libros", "Peluquería"]

failures = []


def sizes_from(text):
    try:
        sizes = sorted({int(part) for part in text.split(",") if part.strip()})
    except ValueError:
        sys.exit(f"Tamaños no válidos: «{text}». Se esperan enteros separados por comas, p. ej. 10000,50000")
    if not sizes or sizes[0] <= 0:
        sys.exit(f"Tamaños no válidos: «{text}». Tienen que ser mayores que cero")
    return sizes


SIZES = sizes_from(sys.argv[1] if len(sys.argv) > 1 else "10000,50000")


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


def raw_call(method, path, query=(), body=None, token=None, prefer=None, timeout=60):
    """Devuelve (código HTTP, cuerpo en bytes). `query` es una lista de pares: se pueden repetir nombres."""
    url = API + path + ("?" + urllib.parse.urlencode(list(query), quote_via=urllib.parse.quote, safe="") if query else "")
    headers = {"apikey": APIKEY, "Content-Type": "application/json", "Authorization": f"Bearer {token or APIKEY}"}
    if prefer:
        headers["Prefer"] = prefer
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as error:
        return error.code, error.read()


def call(method, path, query=(), body=None, token=None, prefer=None):
    """Como `raw_call`, pero devuelve el JSON."""
    code, raw = raw_call(method, path, query, body, token, prefer, timeout=120)
    text = raw.decode()
    try:
        return code, json.loads(text) if text else None
    except ValueError:
        return code, text


def must(what, code, body, ok=(200, 201, 204)):
    if code not in ok:
        sys.exit(f"No se pudo {what}: HTTP {code} {body}")
    return body


# Un usuario normal, como el de la app (el email es sintético y no se confirma en local).
tag = secrets.token_hex(4)
_, session = call("POST", "/auth/v1/signup", body={
    "email": f"medicion-{tag}@savethemoney.invalid",
    "password": secrets.token_urlsafe(18),
    "data": {"username": f"medicion-{tag}"},
})
token = (session or {}).get("access_token") if isinstance(session, dict) else None
if not token:
    sys.exit(f"El alta del usuario de prueba no devolvió sesión: {session}")

household = must("crear el hogar", *call("POST", "/rest/v1/rpc/create_household", body={"household_name": "Hogar de medición"},
                                          token=token))
household_id = (household[0] if isinstance(household, list) else household)["id"]
HOUSEHOLD = ("household_id", f"eq.{household_id}")

openings = [100000 * (k + 1) for k in range(ACCOUNTS)]
accounts = [must("crear la cuenta", *call("POST", "/rest/v1/accounts", token=token, prefer="return=representation", body={
    "household_id": household_id, "name": f"Cuenta {k + 1}", "opening_balance_minor": openings[k]}))[0]["id"]
    for k in range(ACCOUNTS)]
holdings = [must("crear el activo", *call("POST", "/rest/v1/holdings", token=token, prefer="return=representation", body={
    "household_id": household_id, "name": f"Fondo {k + 1}"}))[0]["id"]
    for k in range(HOLDINGS)]
# Las categorías que crea create_household, para que los movimientos lleven categoría como los de verdad.
categories = [c["id"] for c in must("leer las categorías", *call("GET", "/rest/v1/categories", [("select", "id"), HOUSEHOLD],
                                                                  token=token))]

rng = random.Random(70)  # datos inventados, pero los mismos en cada ejecución
loaded = {"transactions": 0, "holding_prices": 0, "investment_trades": 0}
sum_by_account = {account: 0 for account in accounts}


def movement(i):
    account = accounts[i % ACCOUNTS]
    # Casi todo gastos; uno de cada veinte es un ingreso. Nunca cero (amount_minor <> 0).
    amount = rng.randint(150000, 300000) if i % 20 == 0 else -rng.randint(100, 25000)
    sum_by_account[account] += amount
    return {"household_id": household_id, "account_id": account, "category_id": rng.choice(categories) if categories else None,
            "booked_on": (FIRST_DAY + datetime.timedelta(days=rng.randrange(SPAN_DAYS))).isoformat(),
            "amount_minor": amount, "description": rng.choice(DESCRIPTIONS)}


def price(j):
    # Un precio por activo y día: (holding_id, priced_on) es único.
    return {"household_id": household_id, "holding_id": holdings[j % HOLDINGS],
            "priced_on": (FIRST_DAY + datetime.timedelta(days=j // HOLDINGS)).isoformat(),
            "price": f"{100 + j % 50}.{j % 1000000:06d}"}


def trade(j):
    # Sólo compras: una venta pasa por la comprobación de participaciones y no es lo que se mide aquí.
    return {"household_id": household_id, "holding_id": holdings[j % HOLDINGS],
            "traded_on": (FIRST_DAY + datetime.timedelta(days=rng.randrange(SPAN_DAYS))).isoformat(),
            "side": "buy", "quantity": f"{1 + j % 9}.{j % 100000000:08d}", "price": f"{10 + j % 90}.{j % 1000000:06d}",
            "fee_minor": j % 300}


def fill(table, target, row):
    """Carga filas en `table` hasta llegar a `target`, en lotes de BATCH."""
    while loaded[table] < target:
        count = min(BATCH, target - loaded[table])
        must(f"cargar {table}", *call("POST", f"/rest/v1/{table}", token=token, prefer="return=minimal",
                                      body=[row(loaded[table] + k) for k in range(count)]))
        loaded[table] += count


def measure(table, query):
    """Pide todas las páginas como allRows / allPages. Devuelve (filas, peticiones, segundos, bytes, filas leídas)."""
    rows, pages, seconds, size = [], 0, 0.0, 0
    while True:
        page_query = query + [("offset", str(len(rows))), ("limit", str(PAGE))]
        start = time.perf_counter()
        code, raw = raw_call("GET", f"/rest/v1/{table}", page_query, token=token)
        seconds += time.perf_counter() - start
        if code != 200:
            sys.exit(f"HTTP {code} al leer {table}: {raw[:500].decode(errors='replace')}")
        page = json.loads(raw)
        rows += page
        pages += 1
        size += len(raw)
        if len(page) < PAGE:
            return len(rows), pages, seconds, size, rows


def check(name, expected, received):
    if expected != received:
        failures.append(f"{name}: esperado {expected}, recibido {received}")


REQUESTS = [
    ("movimientos (iOS, allMovements)", "transactions",
     [("select", MOVEMENT), HOUSEHOLD, ("order", "booked_on.asc,id.asc")]),
    ("movimientos (Android, TrackingModel)", "transactions",
     [("select", MOVEMENT), HOUSEHOLD, ("booked_on", "gte.1900-01-01"), ("booked_on", "lte.2999-12-31"),
      ("order", "booked_on.desc,id.asc")]),
    ("precios (holdingPrices)", "holding_prices", [("select", PRICE), HOUSEHOLD, ("order", "priced_on.asc,id.asc")]),
    ("operaciones (trades)", "investment_trades", [("select", TRADE), HOUSEHOLD, ("order", "traded_on.asc,id.asc")]),
    ("saldos (account_balances)", "account_balances",
     [("select", "account_id,balance_minor"), HOUSEHOLD, ("order", "account_id.asc")]),
]
EXPECTED_ROWS = {"transactions": lambda: loaded["transactions"], "holding_prices": lambda: loaded["holding_prices"],
                 "investment_trades": lambda: loaded["investment_trades"], "account_balances": lambda: ACCOUNTS}

lines = ["| N | Petición | Ejecución | Filas | Peticiones | Tiempo total (ms) | ms por página | Bytes de respuesta |",
         "|---:|---|---:|---:|---:|---:|---:|---:|"]
for n in SIZES:
    print(f"Cargando hasta {n} movimientos y {n // 10} precios y operaciones…", flush=True)
    fill("transactions", n, movement)
    fill("holding_prices", n // 10, price)
    fill("investment_trades", n // 10, trade)
    for name, table, query in REQUESTS:
        for run in range(1, RUNS + 1):
            count, pages, seconds, size, rows = measure(table, query)
            ms = seconds * 1000
            line = f"| {n} | {name} | {run} | {count} | {pages} | {ms:.1f} | {ms / pages:.1f} | {size} |"
            print(line, flush=True)
            lines.append(line)
            check(f"N={n}, {name}, ejecución {run}: filas", EXPECTED_ROWS[table](), count)
            if table == "transactions":
                check(f"N={n}, {name}, ejecución {run}: ids distintos", count, len({r["id"] for r in rows}))
                check(f"N={n}, {name}, ejecución {run}: suma de amount_minor", sum(sum_by_account.values()),
                      sum(r["amount_minor"] for r in rows))
            elif table == "account_balances":
                check(f"N={n}, {name}, ejecución {run}: saldos",
                      {a: openings[k] + sum_by_account[a] for k, a in enumerate(accounts)},
                      {r["account_id"]: r["balance_minor"] for r in rows})

markdown = "\n".join(lines)
summary = os.environ.get("GITHUB_STEP_SUMMARY")
if summary:
    with open(summary, "a", encoding="utf-8") as out:
        out.write("### ORC-70: carga de los resúmenes contra el Supabase local\n\n"
                  "Tiempos de las peticiones en el runner, sin red móvil. Bytes del cuerpo sin comprimir.\n\n"
                  f"{markdown}\n")
print("\n" + markdown, flush=True)

for failure in failures:
    print(f"FALLO {failure}", flush=True)
print(f"\n{len(failures)} comprobaciones fallidas" if failures else "\nTodas las comprobaciones pasan", flush=True)
sys.exit(1 if failures else 0)
