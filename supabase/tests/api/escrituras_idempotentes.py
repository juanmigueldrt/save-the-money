#!/usr/bin/env python3
"""ORC-142: llama por PostgREST a las 20 funciones de alta y de cambio, con las claves JSON que mandan las apps.

Los nombres de las funciones y de sus parámetros salen de testdata/vectors/rpc_escrituras.json, el mismo fichero con el
que las pruebas de STMData (RpcEscriturasTests) y de Android (RpcEscriturasTest) comparan lo que manda cada app. Aquí
cada cuerpo se comprueba contra ese fichero antes de mandarlo: si pasa, lo que mandan las apps llega a la función de
verdad (con una clave de más o de menos PostgREST contesta PGRST202 y no la encuentra).

Para cada tabla comprueba:
  1. un alta devuelve la fila guardada;
  2. la misma alta otra vez devuelve la misma fila y no añade otra;
  3. el mismo identificador con otro dinero u otra identidad falla con STM01;
  4. un cambio con la versión recién leída entra y devuelve una versión nueva;
  5. el mismo cambio con la versión antigua falla con STM05.
PostgREST devuelve el SQLSTATE en el campo `code` del error.

Los intereses de la tarjeta y del aplazado van como texto en las altas (así los manda iOS) y como número en los cambios
(así los manda Android).

Uso, con el Supabase local arrancado (`supabase start`): python3 supabase/tests/api/escrituras_idempotentes.py
Sólo usa la URL y la clave anónima que imprime `supabase status`. Crea un usuario normal con la API de auth local y hace
todas las llamadas con su sesión, así que el RLS se aplica como en la app. Datos inventados, con identificadores nuevos en
cada ejecución: no hace falta limpiar para repetirlo.

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
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[3]
KEYS = {f["name"]: sorted(f["keys"])
        for f in json.loads((ROOT / "testdata/vectors/rpc_escrituras.json").read_text(encoding="utf-8"))["functions"]}

failures = 0
called = set()


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
    """Devuelve (código HTTP, JSON o texto)."""
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


def must(what, code, body, ok=(200, 201, 204)):
    if code not in ok:
        sys.exit(f"No se pudo {what}: HTTP {code} {body}")
    return body


def new_id():
    return str(uuid.uuid4())


# Un usuario normal, como el de la app (el email es sintético y no se confirma en local).
tag = secrets.token_hex(4)
_, session = call("POST", "/auth/v1/signup", body={
    "email": f"escrituras-{tag}@savethemoney.invalid",
    "password": secrets.token_urlsafe(18),
    "data": {"username": f"escrituras-{tag}"},
})
token = (session or {}).get("access_token") if isinstance(session, dict) else None
if not token:
    sys.exit(f"El alta del usuario de prueba no devolvió sesión: {session}")

household = must("crear el hogar", *call("POST", "/rest/v1/rpc/create_household", body={"household_name": "Hogar de prueba"},
                                          token=token))
HOME = (household[0] if isinstance(household, list) else household)["id"]


def shown(function, body):
    """La petición como se lee."""
    return f"POST /rest/v1/rpc/{function} {json.dumps(body, ensure_ascii=False, sort_keys=True)}"


def rpc(function, body):
    """Llama a la función con la sesión del usuario. La primera vez comprueba que las claves son las de las apps."""
    if function not in called:
        called.add(function)
        check(f"{function}: las claves que se mandan son las de testdata/vectors/rpc_escrituras.json",
              f"claves del cuerpo de {function}", KEYS.get(function), sorted(body))
    return call("POST", f"/rest/v1/rpc/{function}", body=body, token=token)


def outcome(code, body):
    """Lo que se compara: el SQLSTATE si falla; si va bien, «HTTP 200, n filas»."""
    if code == 200 and isinstance(body, list):
        return f"HTTP 200, {len(body)} fila" + ("" if len(body) == 1 else "s")
    if isinstance(body, dict) and "code" in body:
        return f"{body['code']} (HTTP {code}: {body.get('message')})"
    return f"HTTP {code} {body}"


def sqlstate(code, body):
    return body.get("code") if isinstance(body, dict) else f"HTTP {code} {body}"


def count(table):
    code, rows = call("GET", f"/rest/v1/{table}", [("select", "*"), ("household_id", f"eq.{HOME}")], token=token)
    return len(rows) if code == 200 else f"HTTP {code} {rows}"


def creates(what, table, function, body, other):
    """Comprobaciones 1 a 3 de un alta. `other` son las claves que cambian para que ya no sean los mismos datos.
    Devuelve la fila guardada, o None si el alta no fue bien."""
    code, first = rpc(function, body)
    check(f"{what}: el alta devuelve la fila guardada", shown(function, body), "HTTP 200, 1 fila", outcome(code, first))
    if code != 200 or not isinstance(first, list) or len(first) != 1:
        return None
    row, before = first[0], count(table)
    code, again = rpc(function, body)
    check(f"{what}: repetir el alta devuelve la misma fila", shown(function, body), row,
          again[0] if code == 200 and isinstance(again, list) and len(again) == 1 else outcome(code, again))
    check(f"{what}: y no añade otra fila en {table}", f"GET /rest/v1/{table}?household_id=eq.{HOME} antes y después",
          before, count(table))
    changed = {**body, **other}
    code, rejected = rpc(function, changed)
    check(f"{what}: el mismo identificador con otros datos ({', '.join(other)}) falla con STM01", shown(function, changed),
          "STM01", sqlstate(code, rejected))
    return row


def updates(what, function, row, body):
    """Comprobaciones 4 y 5 de un cambio sobre `row`, que trae la versión (`updated_at`) recién leída."""
    if row is None:
        check(f"{what}: el cambio con la versión leída entra", f"{function} (sin fila de la que partir)", "una fila guardada", None)
        return
    seen = row["updated_at"]
    request = {**body, "seen": seen}
    code, saved = rpc(function, request)
    version = saved[0].get("updated_at") if code == 200 and isinstance(saved, list) and len(saved) == 1 else None
    check(f"{what}: el cambio con la versión leída entra y devuelve una versión nueva", shown(function, request),
          "HTTP 200, 1 fila, updated_at distinto del leído",
          "HTTP 200, 1 fila, updated_at distinto del leído" if version and version != seen
          else f"{outcome(code, saved)}, updated_at {version}")
    code, rejected = rpc(function, request)
    check(f"{what}: el mismo cambio con la versión antigua falla con STM05", shown(function, request),
          "STM05", sqlstate(code, rejected))


def without(body, *keys):
    return {k: v for k, v in body.items() if k not in keys}


# Cuentas ---------------------------------------------------------------------------------------------------------
account = {"account": new_id(), "household": HOME, "label": "Cuenta de prueba", "account_kind": "checking",
           "opening": 100000, "owner": None}
row = creates("cuenta", "accounts", "create_account", account, {"opening": 5})
updates("cuenta", "update_account", row, {
    **without(account, "household"), "label": "Cuenta cambiada", "archived": None, "make_default": False, "in_net_worth": True})

# Metas y aportaciones ----------------------------------------------------------------------------------------------
goal = {"goal": new_id(), "household": HOME, "label": "Vacaciones de prueba", "goal_kind": "savings", "target": 200000,
        "starting": 0, "monthly_plan": None, "due": None, "account": None, "icon_name": None, "completed": None,
        "archived": None}
row = creates("meta", "goals", "create_goal", goal, {"target": 5})
updates("meta", "update_goal", row, {**without(goal, "household"), "label": "Viaje de prueba", "monthly_plan": 10000})
creates("aportación", "goal_contributions", "create_goal_contribution",
        {"contribution": new_id(), "household": HOME, "goal": goal["goal"], "amount": 10000, "made": "2026-11-05",
         "remark": None},
        {"amount": 20000})

# Pagos fijos -----------------------------------------------------------------------------------------------------
series = {"series": new_id(), "household": HOME, "label": "Alquiler de prueba", "series_kind": "essential", "amount": 80000,
          "account": None, "category": None, "step": 1, "step_unit": "month", "starts": "2026-11-05", "ends": None,
          "remind_days": 1, "archived": None, "intro_amount": None, "intro_count": None, "pending": True,
          "pending_start": None}
row = creates("pago fijo", "recurring_series", "create_recurring_series", series, {"amount": 90000})
updates("pago fijo", "update_recurring_series", row, {**without(series, "household"), "label": "Alquiler del piso"})

# Tarjetas y compras aplazadas ----------------------------------------------------------------------------------------
# La tarjeta es una cuenta de tipo tarjeta; sus condiciones no tienen identificador propio (su clave es la cuenta).
card = new_id()
must("crear la cuenta de la tarjeta", *rpc("create_account", {
    "account": card, "household": HOME, "label": "Tarjeta de prueba", "account_kind": "credit_card", "opening": 0,
    "owner": None}))
terms = {"card": card, "household": HOME, "credit_limit": 300000, "statement": 1, "payment": 5, "delay_months": 1,
         "mode": "full", "fixed_payment": None, "min_percent": "3", "min_payment": 1500, "revolving": "20",
         "installments": "14", "pay_from": None, "remind_days": 2, "alert": 80}
row = creates("condiciones de tarjeta", "credit_cards", "create_credit_card", terms, {"credit_limit": 5})
updates("condiciones de tarjeta", "update_credit_card", row, {
    **without(terms, "household"), "statement": 10, "min_percent": 3.0, "revolving": 20.0, "installments": 14.0})

purchase = must("apuntar la compra", *call("POST", "/rest/v1/transactions", token=token, prefer="return=representation", body={
    "household_id": HOME, "account_id": card, "booked_on": "2026-11-05", "amount_minor": -60000,
    "description": "Portátil de prueba"}))[0]["id"]
# El aplazado lleva el identificador de su movimiento, como en las apps.
installment = {"installment": purchase, "household": HOME, "card": card, "movement": purchase, "plan_months": 6,
               "plan_rate": "14"}
row = creates("compra aplazada", "card_installments", "create_card_installment", installment, {"plan_months": 12})
updates("compra aplazada", "update_card_installment", row, {"installment": purchase, "plan_months": 9, "plan_rate": 14.0})

# Activos y planes de aportación ----------------------------------------------------------------------------------------
holding = {"holding": new_id(), "household": HOME, "label": "Fondo de prueba", "ticker": None, "holding_kind": "fund",
           "asset": "equity", "account": None, "owner": None, "unit_price": "10.5", "priced": "2026-11-05", "fee": "0.2",
           "remark": None, "archived": None}
row = creates("activo", "holdings", "create_holding", holding, {"holding_kind": "stock"})
updates("activo", "update_holding", row, {**without(holding, "household"), "label": "Fondo cambiado", "ticker": "FDP"})
plan = {"plan": new_id(), "household": HOME, "holding": holding["holding"], "account": None, "amount": 10000, "step": 1,
        "step_unit": "month", "starts": "2026-12-05", "ends": None, "annual_return": "5", "remind_days": 1, "paused": None,
        "archived": None}
row = creates("plan de aportación", "investment_plans", "create_investment_plan", plan, {"amount": 20000})
updates("plan de aportación", "update_investment_plan", row, {**without(plan, "household", "holding"), "amount": 15000})

# Categorías ------------------------------------------------------------------------------------------------------
category = {"category": new_id(), "household": HOME, "label": "Mascotas de prueba", "category_kind": "expense",
            "budget": "wants", "icon_name": "pawprint"}
row = creates("categoría", "categories", "create_category", category, {"label": "Otro nombre de prueba"})
updates("categoría", "update_category", row, {**without(category, "household", "category_kind"), "budget": "needs"})

# Presupuestos extra ------------------------------------------------------------------------------------------------
extra = {"budget": new_id(), "household": HOME, "label": "Vacaciones de prueba", "cap": 80000, "starts": "2026-12-01",
         "ends": None, "category_list": [], "account_list": [], "favorite": False}
row = creates("presupuesto extra", "extra_budgets", "create_extra_budget", extra, {"cap": 5})
updates("presupuesto extra", "update_extra_budget", row, {**without(extra, "household"), "ends": "2026-12-31"})

# Cargos de los pagos fijos -----------------------------------------------------------------------------------------
# No tienen alta por función: la app los crea en lote. Se crea uno como la app y se salta.
charge = must("crear el cargo", *call("POST", "/rest/v1/recurring_charges", token=token, prefer="return=representation", body={
    "household_id": HOME, "series_id": series["series"], "due_on": "2026-11-05", "amount_minor": -80000}))[0]
updates("cargo de un pago fijo", "update_recurring_charge", charge,
        {"charge": charge["id"], "new_status": "skipped", "movement": None})

check("se han llamado las 20 funciones", "funciones de testdata/vectors/rpc_escrituras.json", sorted(KEYS), sorted(called))

print(f"\n{failures} comprobaciones fallidas" if failures else "\nTodas las comprobaciones pasan", flush=True)
sys.exit(1 if failures else 0)
