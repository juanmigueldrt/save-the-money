#!/usr/bin/env python3
"""ORC-70: mide cuánto tardan, contra el Supabase local, las peticiones con las que las apps montan hoy los resúmenes.

Para cada tamaño N (por defecto 10000 y 50000) el hogar de prueba llega a N movimientos repartidos en seis años y cuatro
cuentas, y a N/10 precios y N/10 operaciones de inversión en cinco activos. Después cronometra, tres veces cada una, las
mismas peticiones que hacen las apps, página a página (de 1000 filas, el `max_rows` de supabase/config.toml). Los
movimientos se piden por cursor (cada página, detrás de la última fila de la anterior) y lo demás con offset/limit:

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

Después de medir cada tamaño lanza `medicion_planes.psql` con psql contra la base de datos local (la URL de
`supabase status`) e imprime los EXPLAIN (ANALYZE, BUFFERS) de las mismas peticiones, con el RLS del usuario y sin él.

Uso, con el Supabase local arrancado (`supabase start`):
  python3 supabase/tests/api/medicion_movimientos.py [tamaños separados por comas, p. ej. 10000,50000]
Sólo usa las URL y la clave anónima que imprime `supabase status`. Datos inventados, en un hogar nuevo en cada ejecución.
Si existe la variable GITHUB_STEP_SUMMARY, añade la tabla al resumen del job.
"""

import datetime
import json
import os
import pathlib
import random
import secrets
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[3]
# Extensión .psql y no .sql: `supabase test db` ejecuta como prueba pgTAP todo .sql que haya bajo supabase/tests.
PLANS_SQL = pathlib.Path(__file__).with_name("medicion_planes.psql")
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
    return status["API_URL"].rstrip("/"), key, status.get("DB_URL")


API, APIKEY, DB_URL = local_status()


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
user_id = session["user"]["id"]

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


def measure(table, query, cursor=None):
    """Pide todas las páginas como allRows / allPages o, con `cursor`, como allPagesByCursor: `cursor` recibe la última
    fila leída (None en la primera página) y devuelve los filtros de la página siguiente.
    Devuelve (filas, peticiones, segundos, bytes, filas leídas)."""
    rows, pages, seconds, size = [], 0, 0.0, 0
    while True:
        page_query = query + (cursor(rows[-1] if rows else None) if cursor else [("offset", str(len(rows)))])
        page_query += [("limit", str(PAGE))]
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


def plans(n):
    """Lanza medicion_planes.psql con psql y devuelve lo que imprime: los EXPLAIN (ANALYZE, BUFFERS) de las peticiones."""
    variables = {"hogar": household_id, "claims": json.dumps({"sub": user_id, "role": "authenticated"}),
                 "mitad": n // 2 // PAGE * PAGE, "mitad_inv": n // 10 // 2 // PAGE * PAGE}
    if shutil.which("psql") and DB_URL:
        command = ["psql", DB_URL]
    else:
        # Sin psql en la máquina: el del contenedor de la base de datos del Supabase local.
        names = subprocess.run(["docker", "ps", "--filter", "name=supabase_db_", "--format", "{{.Names}}"],
                               capture_output=True, text=True).stdout.split()
        if not names:
            return 1, "No hay psql ni contenedor supabase_db_*: no se pueden sacar los planes"
        command = ["docker", "exec", "-i", "-e", "PGPASSWORD=postgres", names[0], "psql", "-h", "127.0.0.1", "-U", "postgres",
                   "-d", "postgres"]
    command += ["-X"] + [part for name, value in variables.items() for part in ("-v", f"{name}={value}")]
    result = subprocess.run(command, input=PLANS_SQL.read_text(encoding="utf-8"), capture_output=True, text=True)
    return result.returncode, result.stdout + result.stderr


def check(name, expected, received):
    if expected != received:
        failures.append(f"{name}: esperado {expected}, recibido {received}")


REQUESTS = [
    # Los cursores son los de downloadAfterFilter (iOS) y movementDownloadAfterFilter (Android).
    ("movimientos (iOS, allMovements)", "transactions",
     [("select", MOVEMENT), HOUSEHOLD, ("order", "booked_on.asc,id.asc")],
     lambda last: [("booked_on", f"gte.{last['booked_on']}"),
                   ("or", f"(booked_on.gt.{last['booked_on']},id.gt.{last['id']})")] if last else []),
    ("movimientos (Android, TrackingModel)", "transactions",
     [("select", MOVEMENT), HOUSEHOLD, ("booked_on", "gte.1900-01-01"), ("order", "booked_on.desc,id.asc")],
     lambda last: [("booked_on", f"lte.{last['booked_on']}"),
                   ("or", f"(booked_on.lt.{last['booked_on']},id.gt.{last['id']})")] if last
     else [("booked_on", "lte.2999-12-31")]),
    ("precios (holdingPrices)", "holding_prices", [("select", PRICE), HOUSEHOLD, ("order", "priced_on.asc,id.asc")], None),
    ("operaciones (trades)", "investment_trades", [("select", TRADE), HOUSEHOLD, ("order", "traded_on.asc,id.asc")], None),
    ("saldos (account_balances)", "account_balances",
     [("select", "account_id,balance_minor"), HOUSEHOLD, ("order", "account_id.asc")], None),
]
EXPECTED_ROWS = {"transactions": lambda: loaded["transactions"], "holding_prices": lambda: loaded["holding_prices"],
                 "investment_trades": lambda: loaded["investment_trades"], "account_balances": lambda: ACCOUNTS}

plan_texts = []
lines = ["| N | Petición | Ejecución | Filas | Peticiones | Tiempo total (ms) | ms por página | Bytes de respuesta |",
         "|---:|---|---:|---:|---:|---:|---:|---:|"]
for n in SIZES:
    print(f"Cargando hasta {n} movimientos y {n // 10} precios y operaciones…", flush=True)
    fill("transactions", n, movement)
    fill("holding_prices", n // 10, price)
    fill("investment_trades", n // 10, trade)
    for name, table, query, cursor in REQUESTS:
        for run in range(1, RUNS + 1):
            count, pages, seconds, size, rows = measure(table, query, cursor)
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
    # Los planes de las mismas peticiones, con los datos de este tamaño ya cargados. No se cronometran.
    code, text = plans(n)
    print(f"\nPlanes con {n} movimientos\n{text}", flush=True)
    plan_texts.append(f"<details><summary>Planes con {n} movimientos</summary>\n\n```\n{text}\n```\n\n</details>\n")
    check(f"N={n}, planes: código de salida de psql", 0, code)

markdown = "\n".join(lines)
summary = os.environ.get("GITHUB_STEP_SUMMARY")
if summary:
    with open(summary, "a", encoding="utf-8") as out:
        out.write("### ORC-70: carga de los resúmenes contra el Supabase local\n\n"
                  "Tiempos de las peticiones en el runner, sin red móvil. Bytes del cuerpo sin comprimir.\n\n"
                  f"{markdown}\n\n" + "\n".join(plan_texts))
print("\n" + markdown, flush=True)

for failure in failures:
    print(f"FALLO {failure}", flush=True)
print(f"\n{len(failures)} comprobaciones fallidas" if failures else "\nTodas las comprobaciones pasan", flush=True)
sys.exit(1 if failures else 0)
