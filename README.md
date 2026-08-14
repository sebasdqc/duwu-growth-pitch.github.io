# Duwu · Product & Lifecycle Growth

Material de candidatura para la vacante de **Product & Lifecycle Growth** en
[Duwu Pet Club](https://duwupetclub.com).

Son dos cosas: una landing corta que resume el análisis y la propuesta, y una
implementación funcional del journey de reposición predictiva por WhatsApp.

---

## Estructura

```
pitch/
  index.html          Landing compilada, autocontenida. Es lo que se comparte.
  src/
    body.html         Fuente editable, con marcadores para fuentes e imágenes
    build.py          Compila src/ → index.html
    fonts/            Poppins y Roboto subconjuntadas a latín
    img/              Imágenes optimizadas a webp

demo-reposicion/
  README.md           Puesta en marcha y guion de la demo
  sql/                Esquema, lógica de cálculo y datos de prueba
  n8n/                Flujo diario y webhook de estados
  docs/               Plantillas de WhatsApp para aprobación de Meta
```

## Editar la landing

No edites `pitch/index.html` a mano: se regenera y perderías los cambios.
Edita `pitch/src/body.html` y recompila:

```bash
python3 pitch/src/build.py
```

El correo de contacto y el enlace al plan largo están arriba de `build.py`.

## Correr el demo

Ver [`demo-reposicion/README.md`](demo-reposicion/README.md). Resumen: se crea
un proyecto en Supabase, se ejecutan los tres archivos de `sql/` en orden, se
importan los flujos en n8n y se conecta la WhatsApp Cloud API.

---

## Estado real de cada pieza

Vale la pena tenerlo claro antes de enseñar cualquier cosa.

| Pieza | Estado |
|---|---|
| Landing | Terminada |
| SQL: esquema, lógica y datos de prueba | **Ejecutado** contra PostgreSQL 18, con diez comprobaciones en verde |
| Flujos de n8n | **Escritos** como JSON importable, nunca ejecutados de punta a punta |
| Plantillas de WhatsApp | **Redactadas**, no enviadas a Meta ni aprobadas |

Las plantillas son el paso con plazo externo: la aprobación de Meta tarda entre
minutos y varios días, así que conviene enviarlas antes que cualquier otra cosa.

## Pendientes antes de presentar

- Revisar si las apps nativas de iOS y Android tienen instrumentación distinta a
  la de la web. Todo el análisis se hizo sobre la web.
- Revalidar el bundle de producción: el hash del archivo cambia con cada deploy.
- Correr el flujo de n8n completo al menos una vez.

---

## Sobre el análisis

Todo sale de revisar el sitio público de Duwu el 13 de agosto de 2026, sin
acceso a sistemas internos. Es lo que puede verificar cualquiera desde afuera, y
por eso tiene límites: no cubre las apps nativas, ni el backend, ni herramientas
internas que no se vean desde el navegador.

## Dónde está publicada

| | |
|---|---|
| **Vercel (recomendado)** | <https://duwu-growth-pitch.vercel.app> — sirve `pitch/` directo, con cabeceras de seguridad y `noindex` |
| GitHub Pages | <https://sebasdqc.github.io/duwu-growth-pitch.github.io/pitch/> — sirve el repo entero, así que la raíz muestra este README y la landing queda bajo `/pitch/` |

El deploy en Vercel se rehace con `vercel deploy --prod` desde la raíz. Para que
se dispare solo con cada push hay que conectar el repositorio desde el panel de
Vercel (Settings → Git).

## Notas de terceros

Este repositorio es **público**. Vale la pena tener presente qué implica:

- `pitch/index.html` incrusta tres imágenes tomadas del sitio de Duwu (una foto
  de categoría, otra de mascota y una de producto).
- Las tipografías incrustadas son Roboto (Apache-2.0) y Poppins (SIL OFL 1.1).
  Ambas licencias permiten redistribuirlas.
- El material describe hallazgos sobre el producto de un tercero. La landing
  lleva `noindex`, pero eso no aplica al repositorio: el código y este README sí
  son indexables y cualquiera puede encontrarlos.
- Los datos de `demo-reposicion/sql/03-seed.sql` son ficticios, y los servicios
  del widget de geolocalización son de ejemplo, no comercios reales.
