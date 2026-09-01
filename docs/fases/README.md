# Guía de fases del Laboratorio Integrador

Explicación de cada fase para entender **qué estamos construyendo y por qué**, más allá del checklist de `../../LAB-INTEGRADOR.md`. Cada documento cubre: el problema que resuelve la fase, los conceptos que introduce, cómo se ve el sistema cuando funciona y qué evidencia deja para el reporte final.

| Fase | Documento | En una frase |
|---|---|---|
| 0 | [fase-0-red-base.md](fase-0-red-base.md) | La red privada que hace visible el tráfico: VPC, subnets, flow logs e IP privada de la base |
| 1 | [fase-1-data-service.md](fase-1-data-service.md) | El tercer microservicio con spans de base de datos y caos por error rate |
| 2 | [fase-2-service-mesh.md](fase-2-service-mesh.md) | El mesh que observa la capa 7 sin tocar el código de las apps |
| 3 | [fase-3-aiops.md](fase-3-aiops.md) | Alertas que aprenden el comportamiento normal en vez de usar umbrales fijos |
| 4 | [fase-4-network-security.md](fase-4-network-security.md) | Observar la red y la seguridad como se observan las apps |
| 5 | [fase-5-chaos-mttd.md](fase-5-chaos-mttd.md) | Romper el sistema a propósito y cronometrar cuánto tarda en avisarnos |
| 6 | [fase-6-madurez-entrega.md](fase-6-madurez-entrega.md) | Medir qué tan maduro quedó el sistema y empaquetar la entrega |

## La idea que conecta todo

El laboratorio 2.2 dejó un sistema que **emite** telemetría (trazas, métricas, logs correlacionados). El Laboratorio Integrador lo convierte en un sistema que **reacciona** a esa telemetría: la red se vuelve observable (Fases 0, 2 y 4), las alertas dejan de ser umbrales tontos y pasan a detectar anomalías con contexto accionable (Fase 3), y lo validamos todo rompiendo el sistema a propósito y midiendo cuánto tarda en avisarnos (Fase 5). La Fase 1 agrega la pieza que faltaba del dominio de datos, y la Fase 6 convierte todo en evidencia calificable.

```
Fase 0 (red) ──┬── Fase 2 (mesh L7) ────┐
               ├── Fase 4 (seguridad) ──┤
Fase 1 (data-service) ──────────────────┼── Fase 5 (chaos + MTTD) ── Fase 6 (madurez + entrega)
Fase 3 (AIOps/alertas) ─────────────────┘
```
