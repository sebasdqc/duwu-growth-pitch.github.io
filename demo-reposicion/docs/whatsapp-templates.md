# Plantillas de WhatsApp para aprobación

Meta exige que todo mensaje iniciado por el negocio fuera de la ventana de servicio de 24 horas
use una plantilla aprobada previamente. La aprobación tarda entre minutos y algunos días, así que
**estas plantillas se envían a revisión antes de escribir el flujo, no después.**

---

## `duwu_reposicion_v1`

| Campo | Valor |
|---|---|
| Categoría | `MARKETING` |
| Idioma | `es` |
| Encabezado | ninguno |

**Cuerpo**

```
Hola {{1}} 👋 Según lo que compraste, calculamos que a {{2}} le queda {{3}} de {{4}}.

¿Te preparamos el pedido para que no se quede sin comida?
```

**Pie**

```
Duwu Pet Club · Responde BAJA para no recibir más avisos
```

**Botones** — respuesta rápida

| Texto | Uso |
|---|---|
| `Sí, repetir pedido` | Camino feliz: abre la ventana de servicio |
| `Ahora no` | Señal de que el cálculo se adelantó; sirve para calibrar |

**Parámetros**

| # | Origen en `v_reorder_queue` | Ejemplo |
|---|---|---|
| `{{1}}` | `first_name` | Sebastián |
| `{{2}}` | `pet_name` | Rocky |
| `{{3}}` | `remaining_phrase` | una semana |
| `{{4}}` | `product_name` | Dog Chow Adultos Medianos y Grandes |

**Ejemplos para el formulario de Meta** (obligatorios, o la plantilla se rechaza)

```
Hola Sebastián 👋 Según lo que compraste, calculamos que a Rocky le queda una semana de
Dog Chow Adultos Medianos y Grandes.

¿Te preparamos el pedido para que no se quede sin comida?
```

---

### Por qué los botones importan más de lo que parecen

Los botones de respuesta rápida no son un adorno de interfaz. Cuando el usuario pulsa uno,
**envía un mensaje**, y eso abre la ventana de servicio de 24 horas: dentro de ella se puede
conversar en texto libre, sin plantilla y sin el costo de iniciar una conversación nueva.

Es decir: la plantilla se paga una vez y el resto del intercambio —confirmar dirección, ajustar
cantidad, cerrar el pedido— ocurre dentro de esa ventana. Diseñar el primer mensaje para provocar
una respuesta es, además de mejor conversación, más barato.

El botón `Ahora no` cumple una segunda función: es una etiqueta gratuita de que el cálculo se
adelantó. Acumuladas, esas señales corrigen el factor de consumo mejor que cualquier estimación
teórica.

---

## Nota sobre la categoría

La clasifiqué como `MARKETING` porque promueve una recompra. Existe un argumento para pedir
`UTILITY` —es un aviso operativo sobre un consumo en curso, no una promoción— y `UTILITY` tiene
mejor precio por conversación. Merece intentarse, pero conviene enviar la versión `MARKETING`
en paralelo para no bloquear el lanzamiento si Meta rechaza la otra.

No afirmo saber cómo la va a clasificar Meta en este caso concreto: la política cambia y el
criterio del revisor pesa. Lo que sí conviene es no descubrirlo la semana del lanzamiento.

---

## `duwu_confirmacion_v1` (journey J5, no forma parte de esta demo)

Se incluye porque es el mensaje de mayor apertura de todo el ciclo de vida y ya se envía hoy.
Añadirle el progreso del club es el cambio de mejor relación esfuerzo–impacto del plan.

| Campo | Valor |
|---|---|
| Categoría | `UTILITY` |
| Idioma | `es` |

**Cuerpo**

```
¡Gracias {{1}}! Tu pedido {{2}} está confirmado y llega {{3}}.

🏅 Ganaste {{4}} puntos. Te faltan {{5}} para llegar a nivel {{6}}.
```

Esta sí es claramente `UTILITY`: informa sobre una transacción que el cliente acaba de hacer.
El progreso de lealtad viaja gratis dentro de un mensaje que de todos modos se envía.
