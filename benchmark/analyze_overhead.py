import json
import sys


def load(path):
    with open(path) as f:
        return json.load(f).get("metrics", {})


def pct(base, new):
    if base in (None, 0):
        return "n/a"
    return f"{((new - base) / base) * 100:+.1f}%"


def extract(metrics):
    dur = metrics.get("http_req_duration", {})
    reqs = metrics.get("http_reqs", {})
    failed = metrics.get("http_req_failed", {})
    return {
        "avg_ms": dur.get("avg"),
        "p95_ms": dur.get("p(95)"),
        "p99_ms": dur.get("p(99)"),
        "rps": reqs.get("rate"),
        "error_rate": failed.get("value"),
    }


def fmt(v, suffix=""):
    if v is None:
        return "n/a"
    return f"{v:.2f}{suffix}"


def main():
    if len(sys.argv) != 3:
        print("uso: python analyze_overhead.py <baseline.json> <otel.json>", file=sys.stderr)
        sys.exit(1)

    base = extract(load(sys.argv[1]))
    otel = extract(load(sys.argv[2]))

    rows = [
        ("Latencia promedio (ms)", "avg_ms", ""),
        ("Latencia p95 (ms)", "p95_ms", ""),
        ("Latencia p99 (ms)", "p99_ms", ""),
        ("Throughput (RPS)", "rps", ""),
        ("Error rate", "error_rate", ""),
    ]

    print("| Métrica | Sin OTel (baseline) | Con OTel SDK | Overhead |")
    print("|---|---|---|---|")
    for label, key, suffix in rows:
        b, o = base[key], otel[key]
        print(f"| {label} | {fmt(b, suffix)} | {fmt(o, suffix)} | {pct(b, o)} |")


if __name__ == "__main__":
    main()
