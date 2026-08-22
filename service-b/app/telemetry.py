import structlog
from opentelemetry import metrics, trace
from opentelemetry.trace import get_current_span


def inject_trace_context(logger, method_name, event_dict):
    ctx = get_current_span().get_span_context()
    if ctx.is_valid:
        event_dict["trace_id"] = format(ctx.trace_id, "032x")
        event_dict["span_id"] = format(ctx.span_id, "016x")
    return event_dict


def configure_logging():
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            inject_trace_context,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso"),
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(20),
        logger_factory=structlog.PrintLoggerFactory(),
        cache_logger_on_first_use=True,
    )


configure_logging()

log = structlog.get_logger()
tracer = trace.get_tracer("app")
meter = metrics.get_meter("app")

db_duration = meter.create_histogram(
    "db.operation.duration", unit="ms", description="Duración de operaciones de base de datos"
)

http_requests = meter.create_counter(
    "http.requests", unit="1", description="Total de requests HTTP recibidos"
)
http_request_duration = meter.create_histogram(
    "http.request.duration", unit="ms", description="Distribución de latencia HTTP (p50/p95/p99)"
)
http_active_requests = meter.create_up_down_counter(
    "http.active_requests", unit="1", description="Requests activos en vuelo (saturación)"
)
inventory_requests = meter.create_counter(
    "inventory.requests", unit="1", description="Total de consultas de inventario procesadas"
)
