# Fase 6 — Madurez, reporte y entrega

## El problema

Un sistema técnico excelente que no se puede explicar, evaluar ni continuar vale la mitad. Esta fase responde dos preguntas: **¿qué tan maduro quedó nuestro sistema de observabilidad?** (con un marco formal, no con intuición) y **¿cómo lo demostramos?** (reporte, video, repositorio etiquetado).

## Qué vamos a construir

1. **Autoevaluación contra el Observability Foundation Blueprint** — los 8 dominios del curso (Tres Pilares, OpenTelemetry, AIOps, Network Observability, Security, DataOps, SRE, Chaos), cada uno calificado 1–5 **con justificación basada en evidencia de las fases anteriores**, no en optimismo. La honestidad puntúa: reconocer que el mesh quedó en nivel 2 con un plan para llegar a 3 vale más que inflar todo a 4.
2. **Roadmap a 3 meses** para subir de nivel: accionable significa con iniciativas concretas, orden y criterio de éxito (ej.: "mes 1: tail-based sampling al 15% — cierra la brecha de overhead detectada en el benchmark").
3. **Reporte ejecutivo (PDF, 10 páginas):** arquitectura completa, evidencias de los 3 pilares + AIOps + seguridad + chaos, y el análisis de madurez. Hereda el estilo del reporte U2: decisiones de diseño y números, no capturas sueltas.
4. **Video de demostración en vivo:** el guion natural es seguir un request — `POST /orders` → traza en Cloud Trace → métricas en Grafana → log correlacionado por `trace_id` → encender el caos → ver llegar la alerta con su `trace_id` → rollback. Quince minutos que cuentan toda la historia.
5. **Cierre del repositorio:** README final con la arquitectura de 3 servicios, merge del PR a `main` y **tag `v1.0`**.

## Conceptos clave

- **Modelo de madurez:** una escala 1–5 por dominio convierte "vamos bien" en un mapa: dónde estamos fuertes (pilares, chaos), dónde flojos (¿mesh?, ¿security?), y hacia dónde ir primero. Es la herramienta con la que un líder técnico prioriza inversión en observabilidad.
- **Evidencia trazable:** cada afirmación del reporte apunta a algo verificable del repo (un script, una captura, una medición). El mismo principio de "no ocultar" del Game Day 3.2 aplicado al documento final.
- **Roadmap accionable:** la diferencia entre "mejorar las alertas" (deseo) y "migrar las 4 alert policies a MQL con ventanas de 60 s y burn-rate multiventana (mes 2)" (plan).

## Checklist de cierre operativo

Además de los entregables, esta fase cierra los cabos sueltos de seguridad e higiene acumulados:

- [ ] Rotar la contraseña del usuario `orders` (quedó expuesta en un chat durante el desarrollo) y regenerar el secreto.
- [ ] Revisar que ningún secreto/credencial haya quedado en código, docs o capturas.
- [ ] Decidir el estado final de los guardrails de coste (DB apagada, escala a cero, sampling de flow logs).
- [ ] Verificar que el repo es público y que el tag `v1.0` apunta al commit final.

## Evidencia que deja

Es la fase que **empaqueta** la evidencia de todas las demás: el PDF, el video, el tag. La rúbrica la premia como "autoevaluación completa, roadmap accionable y demostración técnica en vivo".
