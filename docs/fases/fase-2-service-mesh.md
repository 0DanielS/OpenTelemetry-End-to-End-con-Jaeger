# Fase 2 — Service mesh: observar la capa 7 sin tocar el código

## El problema

Nuestra telemetría actual la producen **las propias aplicaciones**: cada servicio se auto-reporta con el SDK de OTel. Eso tiene un punto ciego filosófico — si la app está rota, miente o no reporta, nos quedamos sin datos justo cuando más los necesitamos. Y hay cosas que la app no puede ver: ¿el request llegó siquiera al servicio? ¿cuánto tardó la red entre ambos? ¿quién está llamando a quién realmente?

Un **service mesh** resuelve esto observando el tráfico **desde la infraestructura**: la plataforma ve cada llamada servicio-a-servicio sin que las apps colaboren. Es una segunda fuente de verdad, independiente del código.

## Qué vamos a construir

**Cloud Service Mesh sobre Cloud Run — sin migrar a GKE** (decisión D2). La adhesión al mesh se declara sobre el propio servicio:

1. Crear el recurso **`Mesh`** — el objeto de GCP que representa "esta malla de servicios".
2. Adherir `orders-api`, `inventory-api` y `data-service` con la anotación de revisión o `gcloud beta run deploy --mesh=... --network --subnet=subnet-apis` (por eso la VPC de la Fase 0 era prerrequisito).
3. Definir el enrutamiento con **`HTTPRoute`** (gateway `external-mesh` para cargas fuera de GKE): el mesh sabe qué servicio es cada cosa y puede rutear/observar por nombre lógico.
4. Cerrar la seguridad de paso: autenticación servicio-a-servicio y quitar el `--allow-unauthenticated` del collector, que hoy es un endpoint OTLP público.

## Conceptos clave

- **Capa 7 (L7):** el mesh no ve solo paquetes (L3/L4, eso son los flow logs); entiende HTTP — método, ruta, código de estado. Por eso puede decir "el 2% de los POST de orders→inventory falla", no solo "hubo bytes entre dos IPs".
- **Telemetría de la plataforma vs. del SDK:** el SDK cuenta la historia *desde adentro* (spans de negocio, queries); el mesh la cuenta *desde afuera* (latencia real de red, éxito visto por el cliente). Cuando ambas coinciden, confías; cuando divergen, encontraste un problema de red o de instrumentación.
- **mTLS / auth servicio-a-servicio:** en un mesh, cada servicio prueba criptográficamente quién es. Nuestro collector público pasará a aceptar solo llamadas autenticadas de los servicios del proyecto.
- **Los tres planos de observabilidad de red** que quedan tras esta fase: flow logs (L3/L4, conexiones), mesh (L7, semántica HTTP), SDK/OTel (aplicación, negocio). Cada capa ve lo que la anterior no puede.

## Cómo se ve funcionando

En Cloud Monitoring aparecen métricas de tráfico por **par origen→destino**: `orders-api → inventory-api` con su latencia, volumen y tasa de éxito medidos por la plataforma. La comparación lado a lado con nuestras métricas SLI del SDK (que miden lo mismo desde la app) es la demostración del valor: dos testigos independientes del mismo tráfico.

## Evidencia que deja

- Recursos `Mesh` y `HTTPRoute` como IaC.
- Servicios adheridos al mesh (visible en la revisión de Cloud Run).
- Dashboard/capturas de telemetría L7 por par de servicios.
- Collector ya no público: evidencia de la llamada autenticada.

## Riesgo conocido

Cloud Service Mesh para Cloud Run es una integración reciente (preview en partes). Si algo no funciona como documenta, el plan B es documentar la telemetría L7 equivalente que ya dan Cloud Run + flow logs + las métricas de la plataforma, dejando el intento de mesh como hallazgo técnico honesto — el reporte final valora más el análisis que la casilla marcada.
