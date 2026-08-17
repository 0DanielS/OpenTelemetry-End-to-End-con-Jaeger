import os
import time
import uuid
from contextlib import asynccontextmanager

import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

from .telemetry import db_duration, log, tracer

DATABASE_URL = os.getenv(
    "DATABASE_URL", "postgresql+asyncpg://orders:orders@postgres:5432/orders"
)
INVENTORY_URL = os.getenv("INVENTORY_URL", "http://inventory-api:8081")

engine = create_async_engine(DATABASE_URL, pool_size=20, max_overflow=40)
client = httpx.AsyncClient(timeout=10.0)


@asynccontextmanager
async def lifespan(app):
    async with engine.begin() as conn:
        await conn.execute(
            text(
                "CREATE TABLE IF NOT EXISTS orders ("
                "id UUID PRIMARY KEY DEFAULT gen_random_uuid(), "
                "product_id TEXT NOT NULL, "
                "quantity INT NOT NULL, "
                "customer_id TEXT NOT NULL, "
                "created_at TIMESTAMPTZ DEFAULT now())"
            )
        )
    yield


app = FastAPI(title="orders-api", lifespan=lifespan)


class OrderIn(BaseModel):
    product_id: str = Field(..., min_length=1)
    quantity: int = Field(..., ge=1, le=100)
    customer_id: str = Field(..., min_length=1)


@app.get("/health")
async def health():
    return {"status": "ok"}


@app.post("/orders", status_code=201)
async def create_order(payload: OrderIn):
    log.info(
        "create_order.request",
        product_id=payload.product_id,
        quantity=payload.quantity,
    )

    resp = await client.post(
        f"{INVENTORY_URL}/products/{payload.product_id}/reserve",
        json={"quantity": payload.quantity},
    )
    if resp.status_code != 200:
        log.error("inventory.reserve.failed", status_code=resp.status_code)
        raise HTTPException(status_code=resp.status_code, detail=resp.text)

    reserved = resp.json()

    with tracer.start_as_current_span("persist_order") as span:
        span.set_attribute("order.product_id", payload.product_id)
        span.set_attribute("order.quantity", payload.quantity)
        start = time.perf_counter()
        async with engine.begin() as conn:
            result = await conn.execute(
                text(
                    "INSERT INTO orders (product_id, quantity, customer_id) "
                    "VALUES (:product_id, :quantity, :customer_id) RETURNING id"
                ),
                {
                    "product_id": payload.product_id,
                    "quantity": payload.quantity,
                    "customer_id": payload.customer_id,
                },
            )
            order_id = str(result.scalar_one())
        db_duration.record(
            (time.perf_counter() - start) * 1000.0, {"operation": "insert_order"}
        )

    log.info("order.created", order_id=order_id)
    return {"order_id": order_id, "reserved": reserved, "status": "created"}


@app.get("/orders/{order_id}")
async def get_order(order_id: uuid.UUID):
    async with engine.begin() as conn:
        row = (
            await conn.execute(
                text(
                    "SELECT id, product_id, quantity, customer_id, created_at "
                    "FROM orders WHERE id = :id"
                ),
                {"id": order_id},
            )
        ).first()
    if row is None:
        raise HTTPException(status_code=404, detail="order not found")
    return {
        "id": str(row[0]),
        "product_id": row[1],
        "quantity": row[2],
        "customer_id": row[3],
        "created_at": str(row[4]),
    }
