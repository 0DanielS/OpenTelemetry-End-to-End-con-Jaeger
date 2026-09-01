# Fase 0 — La red base (✅ completada)

## El problema

Antes de esta fase, nuestros servicios de Cloud Run se hablaban entre sí "por internet": cada request salía del servicio, pasaba por el front-end público de Google y entraba al siguiente servicio. Funcionaba, pero para la red éramos ciegos: no existía ninguna VPC nuestra, así que no había dónde encender flow logs, ni forma de decir "este tráfico es interno y este viene de afuera". Y la base de datos se alcanzaba por un socket especial de Google, invisible para cualquier análisis de red.

Los Módulos A (mesh) y C (VPC Flow Logs, tráfico N-S/E-W) del laboratorio son imposibles sin una red propia. Esta fase la construyó.

## Qué construimos

1. **VPC `obs-vpc`** — nuestra red privada virtual en GCP, con tres subredes que separan responsabilidades:
   - `subnet-public` (10.10.0.0/24): Grafana, lo único pensado para exponerse.
   - `subnet-apis` (10.10.1.0/24): las APIs y el collector — el tráfico este-oeste.
   - `subnet-data` (10.10.2.0/24): reservada para la capa de datos.
2. **VPC Flow Logs en las tres subredes** — la red "toma notas": cada conexión (quién habló con quién, puerto, bytes) queda registrada en Cloud Logging. Es la materia prima del análisis de tráfico del Módulo C.
3. **Firewall** — reglas que expresan la política: las APIs pueden hablar con la base (5432), lo público no.
4. **Direct VPC egress** — cada servicio de Cloud Run recibió una "pata" dentro de la VPC: su tráfico hacia rangos privados ahora sale por la subred asignada, con una IP interna (10.10.1.x) que los flow logs pueden ver.
5. **Cloud SQL con IP privada (10.30.0.3)** — la base dejó de ser solo un socket mágico: ahora es un destino de red real dentro del rango peereado (Private Services Access), y la conversación app↔base aparece en los flow logs.

## Conceptos clave

- **VPC (Virtual Private Cloud):** tu propio segmento de red dentro de la nube; nada entra ni sale sin pasar por sus reglas.
- **Direct VPC egress:** el mecanismo de Cloud Run serverless para "meterse" a una VPC sin servidores propios. `private-ranges-only` significa: solo el tráfico a IPs privadas viaja por la VPC; el resto (llamadas a APIs de Google, URLs públicas) sigue su camino normal.
- **Private Services Access (PSA):** Cloud SQL es gestionado por Google, no vive en tu VPC; PSA crea un "puente" (peering) hacia un rango reservado (10.30.0.0/20) donde Google coloca la IP privada de tu instancia.
- **VPC Flow Logs:** muestreo de metadatos de conexiones (no del contenido). Con sampling 0.5 capturamos la mitad de los flujos — suficiente para detectar patrones sin pagar por todo.
- **Tráfico N-S vs E-W:** norte-sur = entra/sale de tu sistema (internet → orders-api); este-oeste = interno entre servicios (orders → inventory → base). Distinguirlos es la base de la observabilidad de seguridad: un servicio comprometido se delata por tráfico E-W anómalo.

## Cómo se ve funcionando

Tras un `POST /orders`, los flow logs muestran líneas como:

```
10.10.1.24 → 10.30.0.3:5432   (una API hablando con la base)
10.30.0.3  → 10.10.1.24       (la respuesta)
```

Eso antes no existía en ninguna parte. La prueba de fuego fue el k6 sostenido de 1 minuto: 4022 requests, 100% éxito, p95 359 ms — el sistema funciona igual que antes, pero ahora la red cuenta lo que pasa.

## Evidencia que deja

- IaC: `scripts/gcp-network-bootstrap.sh` (red completa) y `scripts/migrate-db-secrets-private-ip.sh` (secretos a IP privada).
- Flow logs con tráfico real app↔base en Cloud Logging.
- k6 sostenido validando que la migración de red no degradó el servicio.
