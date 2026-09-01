import os
import random
import time

from fastapi import FastAPI, HTTPException, Query
from sqlalchemy import text
from sqlalchemy.engine import make_url
from sqlalchemy.ext.asyncio import create_async_engine

from opentelemetry.trace import SpanKind, get_current_span
from starlette.requests import Request

from .telemetry import (
    db_duration,
    http_active_requests,
    http_request_duration,
    http_requests,
    log,
    stats_requests,
    tracer,
)

DATABASE_URL = os.getenv(
    "DATABASE_URL", "postgresql+asyncpg://dataservice:dataservice@postgres:5432/orders"
)

CHAOS_ENABLED = os.getenv("CHAOS_ENABLED", "false").lower() == "true"
CHAOS_ERROR_RATE = int(os.getenv("CHAOS_ERROR_RATE", "0"))

engine = create_async_engine(
    DATABASE_URL,
    pool_size=int(os.getenv("DB_POOL_SIZE", "20")),
    max_overflow=int(os.getenv("DB_MAX_OVERFLOW", "40")),
)

_url = make_url(DATABASE_URL)
DB_NAME = _url.database or "orders"
DB_HOST = _url.host or "localhost"
DB_PORT = _url.port or 5432

DB_BASE_ATTRIBUTES = {
    "db.system.name": "postgresql",
    "db.namespace": DB_NAME,
    "server.address": DB_HOST,
    "server.port": DB_PORT,
}

app = FastAPI(title="data-service")


@app.middleware("http")
async def sli_metrics(request: Request, call_next):
    path = request.url.path
    if path == "/health":
        return await call_next(request)
    route = request.scope.get("route")
    labels = {"method": request.method, "route": getattr(route, "path", path)}
    http_active_requests.add(1, labels)
    start = time.perf_counter()
    status_code = 500
    try:
        response = await call_next(request)
        status_code = response.status_code
        return response
    finally:
        route = request.scope.get("route")
        labels["route"] = getattr(route, "path", path)
        status_class = f"{status_code // 100}xx"
        http_requests.add(1, {**labels, "status": status_class})
        http_request_duration.record(
            (time.perf_counter() - start) * 1000.0, {**labels, "status": status_class}
        )
        http_active_requests.add(-1, labels)


def maybe_inject_chaos():
    if not (CHAOS_ENABLED and CHAOS_ERROR_RATE > 0):
        return
    span = get_current_span()
    span.set_attribute("chaos.enabled", True)
    span.set_attribute("chaos.error_rate", CHAOS_ERROR_RATE)
    if random.random() * 100 < CHAOS_ERROR_RATE:
        span.set_attribute("chaos.error.injected", True)
        log.warning("chaos.error.injected", error_rate=CHAOS_ERROR_RATE)
        raise HTTPException(status_code=500, detail="chaos error injected")


async def run_query(operation, table, sql, params=None):
    attributes = {
        **DB_BASE_ATTRIBUTES,
        "db.operation.name": operation,
        "db.collection.name": table,
        "db.query.text": sql,
    }
    with tracer.start_as_current_span(
        f"{operation} {DB_NAME}.{table}", kind=SpanKind.CLIENT, attributes=attributes
    ):
        start = time.perf_counter()
        async with engine.connect() as conn:
            result = await conn.execute(text(sql), params or {})
            rows = result.mappings().all()
        db_duration.record(
            (time.perf_counter() - start) * 1000.0,
            {"operation": operation, "table": table},
        )
        return rows


@app.get("/health")
async def health():
    return {"status": "ok", "service": "data-service"}


@app.get("/stats/orders")
async def stats_orders():
    maybe_inject_chaos()
    rows = await run_query(
        "SELECT",
        "orders",
        "SELECT COUNT(*) AS total_orders, "
        "COUNT(*) FILTER (WHERE created_at > now() - interval '1 hour') AS orders_last_hour, "
        "COALESCE(AVG(quantity), 0) AS avg_quantity, "
        "MAX(created_at) AS last_order_at "
        "FROM orders",
    )
    row = rows[0]
    stats_requests.add(1, {"endpoint": "orders"})
    log.info("stats.orders.served", total_orders=row["total_orders"])
    return {
        "total_orders": row["total_orders"],
        "orders_last_hour": row["orders_last_hour"],
        "avg_quantity": float(row["avg_quantity"]),
        "last_order_at": row["last_order_at"].isoformat() if row["last_order_at"] else None,
    }


@app.get("/stats/top-products")
async def stats_top_products(limit: int = Query(5, ge=1, le=50)):
    maybe_inject_chaos()
    rows = await run_query(
        "SELECT",
        "orders",
        "SELECT product_id, COUNT(*) AS orders_count, SUM(quantity) AS units "
        "FROM orders GROUP BY product_id ORDER BY orders_count DESC LIMIT :limit",
        {"limit": limit},
    )
    stats_requests.add(1, {"endpoint": "top-products"})
    log.info("stats.top_products.served", products=len(rows))
    return {
        "products": [
            {
                "product_id": r["product_id"],
                "orders_count": r["orders_count"],
                "units": int(r["units"]),
            }
            for r in rows
        ]
    }
