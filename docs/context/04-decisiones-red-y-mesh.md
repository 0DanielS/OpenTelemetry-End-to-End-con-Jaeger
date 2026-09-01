# Decisiones técnicas del Laboratorio Integrador

Decisiones ya tomadas que condicionan el diseño. Complementan el plan de fases de `../../LAB-INTEGRADOR.md`.

## D1 — Solo GCP

La consigna original es multi-cloud (GCP + AWS); el alcance se refina a **GCP únicamente**. Cada componente AWS se resuelve con su equivalente GCP (Cloud SQL, Cloud Service Mesh, Cloud Monitoring Anomaly Detection, VPC Flow Logs, Security Command Center).

## D2 — Service mesh sobre Cloud Run, sin migrar a GKE

**Cloud Service Mesh se integra directamente con Cloud Run**; no hace falta mover las cargas a GKE. La adhesión de un servicio al mesh se declara sobre el propio servicio de Cloud Run:

- **API v1 (YAML/annotation):** anotación a nivel de revisión que referencia el recurso `Mesh` (por eso "se hizo con un tag": es una anotación/etiqueta en la revisión, no un cambio de plataforma).
- **gcloud (beta):** `gcloud beta run deploy SERVICE --mesh="projects/PROJECT_ID/locations/global/meshes/MESH_NAME" --network=... --subnet=...`
- **API v2:** campo `serviceMesh` del recurso Service.

Requisitos y piezas:

1. Crear el recurso **`Mesh`** (API `mesh.googleapis.com`).
2. Los servicios necesitan **Direct VPC egress** (`--network`/`--subnet`) para que su tráfico salga por la VPC y el mesh pueda gestionarlo.
3. El enrutamiento servicio-a-servicio del mesh se define con los recursos de service routing (`Mesh`, `HTTPRoute`/`GRPCRoute`); para aplicar rutas a cargas fuera de GKE se usa el gateway `external-mesh`.
4. La telemetría L7 (latencia, éxito, volumen por par origen→destino) queda en Cloud Monitoring; con esto se cubre el requisito de "observabilidad de red L7" del Módulo A.

Referencias: [Configure Cloud Service Mesh for Cloud Run](https://docs.cloud.google.com/service-mesh/docs/configure-cloud-service-mesh-for-cloud-run) · [Cloud Run API reference del mesh](https://docs.cloud.google.com/service-mesh/v1.26/docs/cloud-run-api-reference) · [Route to Cloud Run](https://docs.cloud.google.com/service-mesh/docs/route-to-cloud-run).

## D3 — Diseño de VPC y subnets

Se crea una VPC propia para dar soporte a Direct VPC egress, al mesh y a los VPC Flow Logs (hoy los servicios no pasan por ninguna VPC y los flow logs no verían nada). Diseño acordado:

| Subred | Tipo | Cargas | Propósito |
|---|---|---|---|
| `subnet-public` | Pública | Grafana | Único punto expuesto de visualización |
| `subnet-apis` | Privada | `orders-api`, `inventory-api`, `data-service`, `otel-collector` (Direct VPC egress) | Tráfico este-oeste de las APIs, visible en flow logs y gestionable por el mesh |
| `subnet-data` | Privada | Cloud SQL (IP privada / PSC) | Capa de datos aislada; solo accesible desde `subnet-apis` |

```
                    Internet
                       │
              ┌────────▼────────┐
              │  subnet-public  │   Grafana
              └────────┬────────┘
                       │
              ┌────────▼────────┐   orders-api · inventory-api
              │   subnet-apis   │   data-service · otel-collector
              │   (privada)     │   ← Cloud Service Mesh (L7) + Flow Logs
              └────────┬────────┘
                       │
              ┌────────▼────────┐
              │   subnet-data   │   Cloud SQL (IP privada)
              │   (privada)     │
              └─────────────────┘
```

Notas de implementación:

- **VPC Flow Logs habilitados en las tres subredes** (sampling alto durante los experimentos): base del Módulo C para la alerta de tráfico anómalo y el análisis N-S vs E-W.
- En Cloud Run "pública/privada" se materializa con ingress: Grafana con ingress `all`; las APIs con ingress `internal` + Direct VPC egress, y firewall entre subredes (apis→data permitido, público→data denegado).
- Migrar la conexión a Cloud SQL de socket Unix a **IP privada** dentro de `subnet-data` para que el tráfico de datos también sea observable en los flow logs.
- Esta VPC es también prerrequisito del mesh (D2): `--network`/`--subnet` apuntan a `subnet-apis`.
- De paso se cierra el `--allow-unauthenticated` del Collector (ingress interno + auth servicio-a-servicio).
