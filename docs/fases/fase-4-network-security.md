# Fase 4 — Network & Security Observability

## El problema

Observamos las aplicaciones (3 pilares) y pronto la comunicación L7 (mesh), pero hay dos preguntas que ninguna de esas capas responde:

1. **¿Quién habla con quién en la red, y es eso lo esperado?** Un servicio comprometido no avisa por sus logs de aplicación; se delata por conexiones que no deberían existir (exfiltración, escaneo lateral, un puerto raro).
2. **¿Qué tan expuestos estamos?** Configuraciones inseguras, imágenes con vulnerabilidades conocidas (CVEs), intentos de autenticación fallidos — la postura de seguridad también se observa, con los mismos principios que un SLI.

La tesis del módulo: **la seguridad es un dominio más de la observabilidad**, con sus propias golden signals.

## Qué vamos a construir

La materia prima ya existe desde la Fase 0 (flow logs capturando todo). Esta fase la convierte en análisis:

1. **Validación del tráfico E-W en flow logs** y una **log-based metric + alerta de tráfico anómalo**: por ejemplo, cualquier conexión hacia `subnet-data` o el rango PSA que no venga de `subnet-apis`, o volúmenes fuera de patrón entre servicios.
2. **Security Command Center (tier Standard):** el agregador de postura de GCP — revisa el proyecto y reporta hallazgos (buckets públicos, permisos excesivos, servicios expuestos). Es el "escáner de salud" de la configuración.
3. **Escaneo de CVEs en Artifact Registry:** cada imagen que subimos se analiza contra la base de vulnerabilidades conocidas. Nuestras imágenes de FastAPI tienen decenas de paquetes del sistema — saber cuáles tienen CVEs activos es observabilidad de la cadena de suministro.
4. **Dashboard "Golden Signals de Seguridad":** el entregable estrella del módulo, con tres familias de señales:
   - **Intentos de autenticación fallidos** (logs de Cloud Run e IAM): fuerza bruta o credenciales rotas.
   - **Tráfico N-S vs E-W** (flow logs): el pulso de la red; los cambios de proporción delatan comportamientos nuevos.
   - **CVEs activos** (Container Analysis): la deuda de seguridad visible y contada.

## Conceptos clave

- **Golden signals de seguridad:** análogo deliberado a las golden signals de SRE (latencia, tráfico, errores, saturación). La seguridad también se monitorea con series de tiempo y umbrales, no solo con auditorías anuales.
- **N-S vs E-W:** norte-sur cruza el perímetro (internet↔sistema); este-oeste es interno (servicio↔servicio, servicio↔base). El E-W es el que los atacantes usan tras el primer acceso y el que casi nadie mira.
- **Postura vs. eventos:** SCC observa el *estado* (¿qué está mal configurado?); los flow logs y logs de auth observan *eventos* (¿qué está pasando?). Un programa de seguridad necesita ambos.
- **Log-based metric:** convertir una búsqueda de logs en una serie de tiempo (ej.: "conexiones rechazadas hacia 5432 por minuto") para poder graficarla y alertarla como cualquier métrica.

## Cómo se ve funcionando

- El dashboard muestra la proporción N-S/E-W estable durante carga normal; el k6 dispara el N-S y el E-W crece en proporción conocida.
- Una conexión simulada "prohibida" (por ejemplo, intentar llegar a la base desde fuera de `subnet-apis`) aparece como denegada en flow logs y dispara la alerta de tráfico anómalo.
- SCC lista sus hallazgos y el registro de imágenes muestra el conteo de CVEs por imagen, con severidades.

## Evidencia que deja

- Configuración como IaC en `deploy/security/`.
- Dashboard de golden signals de seguridad con datos reales.
- Alerta de tráfico anómalo demostrada.
- Reporte de hallazgos de SCC y de CVEs por imagen para el análisis del reporte final.
