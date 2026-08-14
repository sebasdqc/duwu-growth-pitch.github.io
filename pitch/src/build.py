#!/usr/bin/env python3
"""
Compila la landing en un único HTML autocontenido.

Dos cosas que hace y por qué:

1. Incrusta fuentes e imágenes como data URI. La página también se publica en un
   entorno con CSP estricta que bloquea hosts externos, así que nada puede
   cargarse por URL.

2. Envuelve el contenido en un documento HTML completo, con doctype, charset y
   —sobre todo— la etiqueta viewport. Sin ella los navegadores móviles asumen un
   ancho de 980 px y muestran la versión de escritorio encogida.

    python3 build.py            # escribe ../index.html

Fuentes: Roboto (Apache-2.0) y Poppins (SIL OFL 1.1), las mismas que usa
duwupetclub.com. Ambas licencias permiten incrustarlas. Van subconjuntadas al
alfabeto latino con fonttools, de ~160 KB por archivo a ~8 KB.
"""

import base64
import pathlib
import sys

AQUI = pathlib.Path(__file__).resolve().parent
SALIDA = AQUI.parent / "index.html"

# --- datos que cambian ---------------------------------------------------
SITIO = "https://duwu-growth-pitch.vercel.app"
CORREO = "sebastiancordero08@gmail.com"
URL_PLAN = "https://claude.ai/code/artifact/7a8b9beb-0aa8-4090-821c-5fc7e9378ff4"
DESCRIPCION = (
    "Duwu vende por web, iOS y Android. Análisis y propuesta para estandarizar "
    "la medición entre las tres, con dos herramientas ya construidas."
)

# El contenido se parte aquí: lo de arriba va al <head>, lo de abajo al <body>.
CORTE = "<!-- ==================== HERO ==================== -->"

FUENTES = [
    ("Poppins", 600, "Poppins_SemiBold.woff2"),
    ("Poppins", 700, "Poppins_Bold.woff2"),
    ("Poppins", 800, "Poppins_ExtraBold.woff2"),
    ("Roboto",  400, "Roboto_Regular.woff2"),
    ("Roboto",  500, "Roboto_Medium.woff2"),
    ("Roboto",  700, "Roboto_Bold.woff2"),
]

IMAGENES = {
    "CAT_IMG": "hero-cat.webp",   # retrato del hero
    "DOG_IMG": "pet-dog.webp",    # avatar de Rocky en la calculadora
    "BAG_IMG": "bag.webp",        # saco de alimento
}


def b64(ruta: pathlib.Path) -> str:
    return base64.b64encode(ruta.read_bytes()).decode()


def bloque_fuentes() -> str:
    lineas = [
        "  /* Poppins + Roboto, las tipografías de Duwu, subconjuntadas a latín.",
        "     Incrustadas porque la CSP de publicación bloquea hosts externos.",
        "     Roboto: Apache-2.0 · Poppins: SIL Open Font License 1.1 */",
    ]
    for familia, peso, archivo in FUENTES:
        datos = b64(AQUI / "fonts" / archivo)
        lineas.append(
            f"  @font-face{{font-family:'{familia}';font-style:normal;"
            f"font-weight:{peso};font-display:swap;"
            f"src:url(data:font/woff2;base64,{datos}) format('woff2');}}"
        )
    return "<style>\n" + "\n".join(lineas) + "\n</style>"


def main() -> int:
    html = (AQUI / "body.html").read_text(encoding="utf-8")

    html = html.replace("<!--FONTS-->", bloque_fuentes(), 1)
    for marca, archivo in IMAGENES.items():
        uri = "data:image/webp;base64," + b64(AQUI / "img" / archivo)
        html = html.replace(marca, uri, 1)
    html = html.replace("PLAN_URL", URL_PLAN)
    html = html.replace("TU_EMAIL", CORREO)

    pendientes = [m for m in ("<!--FONTS-->", "PLAN_URL", "TU_EMAIL", *IMAGENES) if m in html]
    if pendientes:
        print("Quedaron marcadores sin sustituir:", ", ".join(pendientes), file=sys.stderr)
        return 1

    if CORTE not in html:
        print(f"No se encontró el separador de head/body: {CORTE}", file=sys.stderr)
        return 1
    cabeza, cuerpo = html.split(CORTE, 1)
    cuerpo = CORTE + cuerpo

    doc = f"""<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="color-scheme" content="light dark">
<meta name="theme-color" content="#00388b">
<meta name="description" content="{DESCRIPCION}">

<meta property="og:type" content="website">
<meta property="og:locale" content="es_VE">
<meta property="og:url" content="{SITIO}">
<meta property="og:title" content="Tres superficies. Una sola forma de medir.">
<meta property="og:description" content="{DESCRIPCION}">
<meta property="og:image" content="{SITIO}/og.jpg">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta name="twitter:card" content="summary_large_image">

{cabeza.strip()}
</head>
<body>
{cuerpo.strip()}
</body>
</html>
"""

    SALIDA.write_text(doc, encoding="utf-8")
    print(f"{SALIDA.relative_to(AQUI.parent.parent)} · {len(doc) / 1024:.0f} KB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
