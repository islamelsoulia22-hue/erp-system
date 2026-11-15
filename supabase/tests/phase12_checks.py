"""Phase 12 verification: RLS + RPC auth + stock rules + concurrency.
Stdlib only. Prints PASS/FAIL per check. Exit 1 on any failure.
"""
import json
import sys
import urllib.request
import urllib.parse
from concurrent.futures import ThreadPoolExecutor

URL = "https://hcoxmczrnuzatfolytkg.supabase.co"
PUB = "sb_publishable_d7HW0wHV4FpWJzCtb7YJKg_2grggJ1w"
MANAGER = ("hossam@yad.tech", "hossam1258@")
SALES = ("sales_test@yad.tech", "Test1234!@#")
PURCH = ("purchase_test@yad.tech", "Test1234!@#")

results = []


def check(name, ok, detail=""):
    results.append((name, ok))
    print(f"{'PASS' if ok else 'FAIL'}  {name}" + (f"  ({detail})" if detail and not ok else ""))


def login(email, pw):
    req = urllib.request.Request(
        f"{URL}/auth/v1/token?grant_type=password",
        data=json.dumps({"email": email, "password": pw}).encode(),
        headers={"apikey": PUB, "Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)["access_token"]


def api(method, path, jwt=None, body=None, prefer=None):
    headers = {"apikey": PUB, "Content-Type": "application/json"}
    if jwt:
        headers["Authorization"] = f"Bearer {jwt}"
    if prefer:
        headers["Prefer"] = prefer
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(URL + path, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read().decode()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"message": raw[:300]}


def msg(resp):
    _, b = resp
    return json.dumps(b)[:220] if b is not None else ""


OK = (200, 201, 204)  # void RPCs return 204; inserts 201


def one(path, jwt):
    s, b = api("GET", path, jwt)
    return b[0] if s == 200 and b else None


print("== login ==")
mgr = login(*MANAGER)
sal = login(*SALES)
pur = login(*PURCH)
print("tokens ok")

WH = one("/rest/v1/warehouses?code=eq.TEST-WH-12&select=id", mgr)["id"]
PROD = one("/rest/v1/products?sku=eq.TEST12-001&select=id,name,sku", mgr)
PID = PROD["id"]
CUST = one("/rest/v1/customers?customer_code=eq.TEST12-CUST&select=id,name", mgr)
SUP = one("/rest/v1/suppliers?supplier_code=eq.TEST12-SUP&select=id,name", mgr)
CREDIT = one("/rest/v1/payment_methods?code=eq.CREDIT&select=id", mgr)["id"]
CASH = one("/rest/v1/payment_methods?code=eq.CASH&select=id", mgr)["id"]

# A. anon gets no profiles
s, b = api("GET", "/rest/v1/profiles?select=id&limit=1", None)
check("A anon cannot read profiles", (s == 401) or (s == 200 and b == []), f"{s} {msg((s,b))}")

# B. sales cannot read audit
s, b = api("GET", "/rest/v1/audit_logs?select=id&limit=1", sal)
check("B sales blocked from audit_logs", s == 200 and b == [], f"{s} {msg((s,b))}")

# C. sales cannot update audit (0 rows affected expected)
s, b = api("PATCH", "/rest/v1/audit_logs?action=eq.LOGIN", sal, {"action": "X"},
           prefer="return=representation")
check("C audit not updatable by sales", b == [], f"{s} {msg((s,b))}")

# D/E. direct stock writes denied (0 rows affected expected)
s, b = api("PATCH", f"/rest/v1/warehouse_stock?warehouse_id=eq.{WH}", sal,
           {"quantity": 999}, prefer="return=representation")
check("D direct stock UPDATE denied", b == [], f"{s} {msg((s,b))}")
s, _ = api("POST", "/rest/v1/warehouse_stock", sal,
           {"warehouse_id": WH, "product_id": PID, "quantity": 1},
           prefer="return=representation")
check("E direct stock INSERT denied", s not in (200, 201, 204), f"{s}")

# S. audit delete denied (manager too - no delete policy)
s, b = api("GET", "/rest/v1/audit_logs?select=id&limit=1", mgr)
aid = b[0]["id"] if s == 200 and b else None
if aid:
    s2, b2 = api("DELETE", f"/rest/v1/audit_logs?id=eq.{aid}", mgr,
                 prefer="return=representation")
    check("S audit not deletable even by manager", b2 == [], f"{s2} {msg((s2,b2))}")
else:
    check("S audit rows exist for delete test", False, "no rows")

# F. sales draft -> submit
s, b = api("POST", "/rest/v1/sales_invoices", sal,
           {"customer_id": CUST["id"], "warehouse_id": WH, "payment_method_id": CASH},
           prefer="return=representation")
inv1 = b[0]["id"] if s in (200, 201) else None
check("F1 sales creates draft", inv1 is not None, f"{s} {msg((s,b))}")
api("POST", "/rest/v1/sales_invoice_items", sal,
    {"sales_invoice_id": inv1, "product_id": PID, "item_name": "صنف اختبار 12",
     "sku": "TEST12-001", "quantity": 2, "unit_price": 15, "tax_rate": 0})
s, b = api("POST", "/rest/v1/rpc/submit_sales_invoice", sal, {"p_invoice": inv1})
check("F2 sales submits to PENDING", s in OK, f"{s} {msg((s,b))}")
num1 = one(f"/rest/v1/sales_invoices?id=eq.{inv1}&select=invoice_number,customer_name_snapshot", sal)
check("F3 snapshot filled + number format",
      num1 and num1["invoice_number"].startswith("SAL-") and num1["customer_name_snapshot"] == "عميل اختبار 12",
      f"{num1}")

# self-approve blocked
s, b = api("POST", "/rest/v1/rpc/approve_sales_invoice", sal, {"p_invoice": inv1})
check("F4 self-approval blocked", s != 200 and ("CANNOT_APPROVE" in msg((s, b)) or "NO_PERMISSION" in msg((s, b))),
      f"{s} {msg((s,b))}")

# manager approves -> reserve +2
r0 = float(one(f"/rest/v1/warehouse_stock?warehouse_id=eq.{WH}&product_id=eq.{PID}&select=reserved_quantity", sal)["reserved_quantity"])
s, b = api("POST", "/rest/v1/rpc/approve_sales_invoice", mgr, {"p_invoice": inv1})
check("G manager approves", s in OK, f"{s} {msg((s,b))}")
st = one(f"/rest/v1/warehouse_stock?warehouse_id=eq.{WH}&product_id=eq.{PID}&select=reserved_quantity", sal)
check("G2 stock reserved +2", st and abs(float(st["reserved_quantity"]) - r0 - 2.0) < 0.001, f"{st} (was {r0})")

# H. insufficient stock approval fails
s, b = api("POST", "/rest/v1/sales_invoices", sal,
           {"customer_id": CUST["id"], "warehouse_id": WH, "payment_method_id": CASH},
           prefer="return=representation")
invH = b[0]["id"]
api("POST", "/rest/v1/sales_invoice_items", sal,
    {"sales_invoice_id": invH, "product_id": PID, "item_name": "x", "quantity": 10000,
     "unit_price": 15, "tax_rate": 0})
api("POST", "/rest/v1/rpc/submit_sales_invoice", sal, {"p_invoice": invH})
s, b = api("POST", "/rest/v1/rpc/approve_sales_invoice", mgr, {"p_invoice": invH})
check("H insufficient stock blocked", s != 200 and "INSUFFICIENT" in msg((s, b)), f"{s} {msg((s,b))}")
numH = one(f"/rest/v1/sales_invoices?id=eq.{invH}&select=invoice_number", sal)["invoice_number"]

# I/J. duplicate number rejected + numbers unique
s, b = api("POST", "/rest/v1/sales_invoices", mgr,
           {"customer_id": CUST["id"], "warehouse_id": WH,
            "invoice_number": num1["invoice_number"]},
           prefer="return=representation")
check("I duplicate invoice_number rejected", s not in (200, 201, 204), f"{s}")
check("J numbers unique + sequenced", num1["invoice_number"] != numH, f"{num1['invoice_number']} vs {numH}")

# K. duplicate barcode rejected (manager has perm; unique must fire)
s, b = api("POST", "/rest/v1/product_barcodes", mgr,
           {"product_id": PID, "barcode": "TEST12-BC-001"},
           prefer="return=representation")
check("K duplicate barcode rejected", s not in (200, 201, 204), f"{s}")

# L. unknown barcode -> []
s, b = api("GET", "/rest/v1/product_barcodes?barcode=eq.NO-SUCH-BC-999&select=barcode", sal)
check("L unknown barcode empty", s == 200 and b == [], f"{s} {msg((s,b))}")

# M. snapshot preserved after customer rename
api("PATCH", f"/rest/v1/customers?id=eq.{CUST['id']}", sal, {"name": "عميل معدل 12"})
snap = one(f"/rest/v1/sales_invoices?id=eq.{inv1}&select=customer_name_snapshot", sal)
api("PATCH", f"/rest/v1/customers?id=eq.{CUST['id']}", sal, {"name": "عميل اختبار 12"})
check("M snapshot preserved", snap and snap["customer_name_snapshot"] == "عميل اختبار 12", f"{snap}")

# N. credit without reason rejected
s, b = api("POST", "/rest/v1/sales_invoices", sal,
           {"customer_id": CUST["id"], "warehouse_id": WH, "payment_method_id": CREDIT},
           prefer="return=representation")
invN = b[0]["id"]
api("POST", "/rest/v1/sales_invoice_items", sal,
    {"sales_invoice_id": invN, "product_id": PID, "item_name": "x", "quantity": 1,
     "unit_price": 15, "tax_rate": 0})
s, b = api("POST", "/rest/v1/rpc/submit_sales_invoice", sal, {"p_invoice": invN})
check("N credit needs reason", s != 200 and "CREDIT_REASON" in msg((s, b)), f"{s} {msg((s,b))}")

# O. reject then resubmit
s, b = api("POST", "/rest/v1/sales_invoices", sal,
           {"customer_id": CUST["id"], "warehouse_id": WH, "payment_method_id": CASH},
           prefer="return=representation")
invO = b[0]["id"]
api("POST", "/rest/v1/sales_invoice_items", sal,
    {"sales_invoice_id": invO, "product_id": PID, "item_name": "x", "quantity": 1,
     "unit_price": 15, "tax_rate": 0})
api("POST", "/rest/v1/rpc/submit_sales_invoice", sal, {"p_invoice": invO})
s, _ = api("POST", "/rest/v1/rpc/reject_sales_invoice", mgr,
           {"p_invoice": invO, "p_reason": "test reject 12"})
s2, _ = api("POST", "/rest/v1/rpc/submit_sales_invoice", sal, {"p_invoice": invO})
st2 = one(f"/rest/v1/sales_invoices?id=eq.{invO}&select=status", sal)
check("O reject + resubmit", s in OK and s2 in OK and st2["status"] == "PENDING_APPROVAL", f"{s}/{s2} {st2}")

# P/Q. PO + over-receive blocked + partial works
s, b = api("POST", "/rest/v1/purchase_orders", mgr,
           {"supplier_id": SUP["id"], "warehouse_id": WH},
           prefer="return=representation")
po = b[0]["id"]
s, b = api("POST", "/rest/v1/purchase_order_items", mgr,
           {"purchase_order_id": po, "product_id": PID, "product_name": "صنف اختبار 12",
            "quantity": 10, "unit_cost": 10}, prefer="return=representation")
poi = b[0]["id"]
api("POST", "/rest/v1/rpc/submit_purchase_order", mgr, {"p_order": po})
before = float(one(f"/rest/v1/warehouse_stock?warehouse_id=eq.{WH}&product_id=eq.{PID}&select=quantity", mgr)["quantity"])
s, b = api("POST", "/rest/v1/rpc/receive_purchase_order", mgr,
           {"p_order": po, "p_lines": [{"item_id": poi, "qty": 99}]})
check("P over-receive blocked", s != 200 and "OVER_RECEIVE" in msg((s, b)), f"{s} {msg((s,b))}")
s, b = api("POST", "/rest/v1/rpc/receive_purchase_order", mgr,
           {"p_order": po, "p_lines": [{"item_id": poi, "qty": 4}]})
after = float(one(f"/rest/v1/warehouse_stock?warehouse_id=eq.{WH}&product_id=eq.{PID}&select=quantity", mgr)["quantity"])
post = one(f"/rest/v1/purchase_orders?id=eq.{po}&select=status", mgr)
check("Q partial receive +4 & PARTIALLY",
      s in OK and after - before == 4.0 and post["status"] == "PARTIALLY_RECEIVED",
      f"{s} {before}->{after} {post}")

# R. purchase invoice approval does NOT move stock
s, b = api("POST", "/rest/v1/purchase_invoices", pur,
           {"supplier_id": SUP["id"], "warehouse_id": WH},
           prefer="return=representation")
piv = b[0]["id"]
api("POST", "/rest/v1/purchase_invoice_items", pur,
    {"purchase_invoice_id": piv, "product_id": PID, "product_name_snapshot": "x",
     "quantity": 5, "unit_cost": 10})
api("POST", "/rest/v1/rpc/submit_purchase_invoice", pur, {"p_invoice": piv})
q0 = float(one(f"/rest/v1/warehouse_stock?warehouse_id=eq.{WH}&product_id=eq.{PID}&select=quantity", mgr)["quantity"])
s, _ = api("POST", "/rest/v1/rpc/approve_purchase_invoice", mgr, {"p_invoice": piv})
q1 = float(one(f"/rest/v1/warehouse_stock?warehouse_id=eq.{WH}&product_id=eq.{PID}&select=quantity", mgr)["quantity"])
check("R invoice approval moves no stock", s in OK and q0 == q1, f"{s} {q0}->{q1}")

# T. negative adjustment beyond stock blocked
s, b = api("POST", "/rest/v1/rpc/create_stock_adjustment", mgr,
           {"p_warehouse_id": WH, "p_product_id": PID, "p_qty_change": -100000})
check("T negative stock blocked", s != 200 and "INSUFFICIENT" in msg((s, b)), f"{s} {msg((s,b))}")

# U. unauthenticated RPC blocked
s, b = api("POST", "/rest/v1/rpc/approve_sales_invoice", None, {"p_invoice": inv1})
check("U anon RPC blocked", s in (401, 403, 404) or (s == 400 and "NOT_AUTHENTICATED" in msg((s, b))), f"{s} {msg((s,b))}")

print("\n== concurrency (numbers + stock) ==")


def make_draft(_):
    s, b = api("POST", "/rest/v1/sales_invoices", mgr,
               {"customer_id": CUST["id"], "warehouse_id": WH, "payment_method_id": CASH},
               prefer="return=representation")
    return b[0]["invoice_number"] if s in (200, 201) else f"ERR{s}"


with ThreadPoolExecutor(max_workers=5) as ex:
    nums = list(ex.map(make_draft, range(5)))
check("V concurrent drafts unique numbers", len(set(nums)) == 5 and all(n.startswith("SAL-") for n in nums), f"{nums}")


def adj(_):
    s, _ = api("POST", "/rest/v1/rpc/create_stock_adjustment", mgr,
               {"p_warehouse_id": WH, "p_product_id": PID, "p_qty_change": 1})
    return s


q0 = float(one(f"/rest/v1/warehouse_stock?warehouse_id=eq.{WH}&product_id=eq.{PID}&select=quantity", mgr)["quantity"])
with ThreadPoolExecutor(max_workers=10) as ex:
    codes = list(ex.map(adj, range(10)))
q1 = float(one(f"/rest/v1/warehouse_stock?warehouse_id=eq.{WH}&product_id=eq.{PID}&select=quantity", mgr)["quantity"])
check("W 10 parallel +1 adjustments consistent",
      all(c == 200 for c in codes) and abs((q1 - q0) - 10.0) < 0.001,
      f"{codes} {q0}->{q1}")

fails = [n for n, ok in results if not ok]
print(f"\n{len(results) - len(fails)}/{len(results)} passed")
sys.exit(1 if fails else 0)
