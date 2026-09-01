import asyncio
import os
import time
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

from starlette.requests import Request

from .telemetry import (
    db_duration,
    http_active_requests,
    http_request_duration,
    http_requests,
    inventory_requests,
    log,
    tracer,
)

DATABASE_URL = os.getenv(
    "DATABASE_URL", "postgresql+asyncpg://inventory:inventory@postgres:5432/inventory"
)

CHAOS_ENABLED = os.getenv("CHAOS_ENABLED", "false").lower() == "true"
CHAOS_LATENCY_MS = int(os.getenv("CHAOS_LATENCY_MS", "0"))

engine = create_async_engine(
    DATABASE_URL,
    pool_size=int(os.getenv("DB_POOL_SIZE", "20")),
    max_overflow=int(os.getenv("DB_MAX_OVERFLOW", "40")),
)


@asynccontextmanager
async def lifespan(app):
    async with engine.begin() as conn:
        await conn.execute(
            text("CREATE TABLE IF NOT EXISTS products (id TEXT PRIMARY KEY, stock INT NOT NULL)")
        )
        seed = ", ".join([f"('p{i}', 1000000)" for i in range(1, 101)])
        await conn.execute(
            text(
                "INSERT INTO products (id, stock) VALUES "
                + seed
                + " ON CONFLICT (id) DO UPDATE SET stock = EXCLUDED.stock"
            )
        )
    yield


app = FastAPI(title="inventory-api", lifespan=lifespan)


@app.middleware("http")
async def sli_metrics(request: Request, call_next):
    path = request.url.path
    if path == "/health":
        return await call_next(request)
    active_labels = {"method": request.method}
    http_active_requests.add(1, active_labels)
    start = time.perf_counter()
    status_code = 500
    try:
        response = await call_next(request)
        status_code = response.status_code
        return response
    finally:
        route = request.scope.get("route")
        labels = {
            "method": request.method,
            "route": getattr(route, "path", path),
            "status": f"{status_code // 100}xx",
        }
        http_requests.add(1, labels)
        http_request_duration.record((time.perf_counter() - start) * 1000.0, labels)
        http_active_requests.add(-1, active_labels)


class ReserveIn(BaseModel):
    quantity: int = Field(..., ge=1, le=100)


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.get("/products/{product_id}/stock")
async def get_stock(product_id: str):
    with tracer.start_as_current_span("check_stock") as span:
        span.set_attribute("product.id", product_id)
        start = time.perf_counter()
        async with engine.begin() as conn:
            row = (
                await conn.execute(
                    text("SELECT stock FROM products WHERE id = :id"), {"id": product_id}
                )
            ).first()
        db_duration.record(
            (time.perf_counter() - start) * 1000.0, {"operation": "check_stock"}
        )
    if row is None:
        raise HTTPException(status_code=404, detail="product not found")
    return {"product_id": product_id, "stock": row[0]}


@app.post("/products/{product_id}/reserve")
async def reserve_stock(product_id: str, payload: ReserveIn):
    with tracer.start_as_current_span("reserve_stock") as span:
        span.set_attribute("product.id", product_id)
        span.set_attribute("reserve.quantity", payload.quantity)
        if CHAOS_ENABLED and CHAOS_LATENCY_MS > 0:
            span.set_attribute("chaos.enabled", True)
            span.set_attribute("chaos.latency_ms", CHAOS_LATENCY_MS)

            log.warning(
                "chaos.latency.injected",
                latency_ms=CHAOS_LATENCY_MS,
                product_id=product_id,
            )

            await asyncio.sleep(CHAOS_LATENCY_MS / 1000.0)
        start = time.perf_counter()
        async with engine.begin() as conn:
            result = await conn.execute(
                text(
                    "UPDATE products SET stock = stock - :qty "
                    "WHERE id = :id AND stock >= :qty RETURNING stock"
                ),
                {"qty": payload.quantity, "id": product_id},
            )
            row = result.first()
        db_duration.record(
            (time.perf_counter() - start) * 1000.0, {"operation": "reserve_stock"}
        )
    if row is None:
        inventory_requests.add(1, {"operation": "reserve", "result": "insufficient"})
        log.warning("insufficient.stock", product_id=product_id, quantity=payload.quantity)
        raise HTTPException(status_code=409, detail="insufficient stock")
    inventory_requests.add(1, {"operation": "reserve", "result": "ok"})
    return {"product_id": product_id, "remaining_stock": row[0]}
