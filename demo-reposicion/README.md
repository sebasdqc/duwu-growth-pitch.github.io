# Demo · Reposición predictiva por WhatsApp

Implementación funcional del journey **J6** y del experimento **X7** del plan de Growth para
Duwu Pet Club.

Calcula cuándo se le acaba el alimento a cada mascota a partir de su peso y de la presentación
comprada, y envía un aviso por WhatsApp unos días antes — reservando un 20 % de control que no
recibe nada, para poder medir si el mensaje aporta algo por encima de lo que habría pasado igual.

```
peso de la mascota ─┐
                    ├─► gramos/día ─► días de cobertura ─► fecha de aviso ─► cola ─► WhatsApp
presentación ───────┘                        ▲                                 │
                                             │                                 ├─► 80 % tratamiento
                          intervalo real de recompra                           └─► 20 % control
                          (le gana al modelo desde la 2.ª compra)                   (registrado,
                                                                                     no enviado)
```

---

## Qué hay aquí

| Archivo | Qué es |
|---|---|
| `sql/01-schema.sql` | Tablas: clientes, mascotas, presentaciones, pedidos, factores de consumo, bitácora |
| `sql/02-logic.sql` | Las funciones y vistas del cálculo, más la consulta de resultados del experimento |
| `sql/03-seed.sql` | Seis clientes de prueba con casos que vencen hoy, uno que aún no toca y uno dado de baja |
| `n8n/reorder-daily.json` | Flujo diario: consulta la cola, separa control, envía y registra |
| `n8n/whatsapp-webhook.json` | Recibe estados de entrega y respuestas del usuario |
| `docs/whatsapp-templates.md` | Las plantillas listas para enviar a aprobación de Meta |

---

## Antes de empezar: lo que más tarda

**Envía las plantillas a aprobación primero.** Está todo en `docs/whatsapp-templates.md`. Meta
tarda entre unos minutos y varios días, y sin plantilla aprobada no sale ningún mensaje. Es el
único paso que no depende de ti.

**No hace falta verificar la empresa para la demo.** La WhatsApp Cloud API da un número de prueba
gratuito que puede enviar a **hasta 5 destinatarios verificados** sin verificación de negocio ni
método de pago. Para una demostración es exactamente lo que se necesita: agrega tu propio número
como destinatario de prueba y listo.

---

## Puesta en marcha

### 1 · Base de datos (5 min)

Crea un proyecto en Supabase y ejecuta en el SQL Editor, en este orden:

```bash
sql/01-schema.sql
sql/02-logic.sql
sql/03-seed.sql
```

Antes de correr el seed, **cambia el teléfono de `demo-001` por el tuyo** en formato E.164
(`+58414...`). Es el único número que recibirá un mensaje real.

Comprueba que la cola tiene lo que debe:

```sql
select pet_name, product_name, coverage_days, days_remaining,
       confidence, variant, remaining_phrase
  from v_reorder_queue;
```

Deben salir **cuatro filas**:

| Mascota | Cobertura | Confianza | Variante | Por qué está |
|---|---|---|---|---|
| Rocky | 20,0 días | `model` | `treatment` | 20 kg × 2 % = 400 g/día · saco de 8 kg |
| Luna | 18,8 días | `model` | `treatment` | 4 kg × 2 % = 80 g/día · bolsa de 1,5 kg |
| Canela | 16,7 días | `model` | `holdout` | Cachorro: factor 3 %, no 2 % |
| Simón | 28,0 días | `observed` | `treatment` | Tres compras previas: el dato real gana al modelo |

Y deben faltar dos: **Miel**, porque su aviso cae dentro de 8 días y todavía no le toca, y
**Toby**, cuyo aviso sí está vencido pero su dueño se dio de baja del canal. Si alguno aparece,
algo está mal en los filtros.

Las variantes de esa tabla son fijas: los uuid de los clientes de demostración están escritos a
mano en el seed precisamente para que `fn_bucket` devuelva siempre lo mismo y la demo sea
repetible.

> El caso de Simón es el que conviene enseñar. El modelo predice 33 días de cobertura; sus compras
> reales dicen 28. Desde el segundo intervalo el sistema deja de creerle al modelo y le cree al
> cliente.

### 2 · WhatsApp Cloud API (10 min)

1. En [developers.facebook.com](https://developers.facebook.com) crea una app de tipo *Business*
   y añade el producto **WhatsApp**.
2. Copia el **Phone Number ID** del número de prueba y el **token de acceso temporal** (dura 24 h;
   para algo estable, genera un token de usuario del sistema).
3. En *API Setup*, agrega tu número personal como destinatario de prueba y confirma el código.
4. Envía las plantillas de `docs/whatsapp-templates.md` desde *Message Templates*.

### 3 · n8n (5 min)

Importa los dos flujos y configura:

- **Credencial de Postgres** apuntando a Supabase. Usa la *service role*: estas tablas tienen RLS
  activo y contienen teléfonos y asignación de experimento.
- **Variables de entorno**:
  ```
  WA_PHONE_NUMBER_ID=...
  WA_ACCESS_TOKEN=...
  ```
- **Zona horaria** del workflow en `America/Caracas`.

Para el webhook: publica el flujo, copia la URL de producción y regístrala en la app de Meta
suscribiéndote al campo `messages`.

### 4 · Ejecutar

Pulsa *Execute Workflow* en `reorder-daily`. Deberías ver el mensaje llegar a tu teléfono en
segundos, y esta consulta contarlo:

```sql
select variant, status, count(*)
  from message_log
 where journey = 'J6_reorder'
 group by variant, status;
```

El control aparece como `holdout / suppressed`: registrado, nunca enviado. Esa fila es la que
después permite comparar.

### 5 · Leer el experimento

```sql
select * from v_x7_results;
```

Con datos de demostración el resultado no significa nada — hacen falta semanas y volumen real.
La consulta está para mostrar que la medición se diseñó junto con el envío, y no después.

---

## Qué enseñar, y en qué orden

Cuatro minutos bastan:

1. **La cola.** `select * from v_reorder_queue`. Cuatro filas con cadencias de 17 a 28 días.
   Aquí se ve por qué un umbral fijo de «60 días sin comprar» se equivoca con todos.
2. **Simón.** El modelo dice 33 días, sus compras dicen 28. El sistema aprende del dato que él
   mismo genera.
3. **El mensaje.** Que llegue al teléfono, en vivo.
4. **El control.** `select variant, status, count(*) from message_log group by 1,2`. Este es el
   punto que separa esto de un envío masivo: hay un grupo que no recibe nada a propósito, porque
   sin él se estaría atribuyendo al mensaje compras que iban a ocurrir de todas formas.

El cuarto punto es el importante. Los tres primeros demuestran que sabes construir; el cuarto,
que sabes medir.

---

## Decisiones que conviene poder defender

**El colchón de 5 días es la única constante arbitraria.** Se avisa antes de que se acabe, no
cuando ya se acabó: para entonces el cliente ya fue a la tienda de la esquina. Los factores de
consumo también son generosos a propósito — es preferible avisar unos días temprano que un día
tarde.

**El intervalo observado le gana al modelo desde la segunda compra.** El modelo es solo arranque
en frío. El consumo real de una casa incluye las sobras, los premios y el gato que come del plato
del perro; nada de eso está en una fórmula, pero sí en la fecha del siguiente pedido.

**El holdout es determinista, no aleatorio en cada corrida.** `fn_bucket` calcula un hash estable
del id del cliente, así que alguien asignado al control sigue en el control mañana y después de
un reinicio. Cambiar la sal equivale a re-aleatorizar el experimento, y hacerlo a mitad de camino
lo invalida.

**El tope de frecuencia vive en SQL, no en el flujo.** Máximo dos mensajes no transaccionales por
semana y sin repetir el mismo aviso en 21 días, aplicado en `v_reorder_queue`. Si esa regla
estuviera en n8n, cada journey nuevo tendría que reimplementarla y alguno se olvidaría.

**`force_variant` es solo para QA.** Existe para que la demo sea reproducible. En producción debe
estar en `null` para todo el mundo, y valdría la pena una alerta si deja de estarlo.

---

## Qué está verificado y qué no

**El SQL se ejecutó completo contra PostgreSQL 18** en una base limpia, y se comprobó cada
comportamiento que este README afirma:

| Comprobación | Resultado |
|---|---|
| Los tres archivos corren sin error sobre una base vacía | ✅ |
| La cola devuelve exactamente Rocky, Luna, Canela y Simón | ✅ |
| Simón usa el intervalo observado (28,0) y no el modelo (33,3) | ✅ |
| Miel queda fuera por fecha; Toby, vencido pero dado de baja, por opt-out | ✅ |
| El holdout reparte 19,9 % sobre 5.000 uuid, y `fn_bucket` es estable y nunca negativo | ✅ |
| Dos corridas seguidas del seed dan la misma asignación de variantes | ✅ |
| Tras registrar los envíos, la cola se vacía (sin repetir en 21 días) | ✅ |
| Dos mensajes no transaccionales en la semana sacan a Rocky de la cola | ✅ |
| Cuatro transaccionales **no** lo sacan | ✅ |
| `v_x7_results` compara tratamiento contra control correctamente | ✅ |

Durante esa prueba apareció y se corrigió un error real: `percentile_cont` devuelve
`double precision` y `round(double precision, integer)` no existe en Postgres. Está resuelto en
`v_observed_interval`.

**Los flujos de n8n no están ejecutados.** Dependen de versiones de nodo que cambian entre
releases: al importar es posible que haya que reajustar algún `typeVersion` o volver a
seleccionar la credencial. Prueba el recorrido completo antes de enseñarlo.

**El modelo de datos es el mínimo del journey**, no el catálogo de Duwu. Un producto real necesita
inventario, precios por zona, sustituciones cuando el SKU está agotado y varias mascotas
compartiendo un mismo saco.

**No hay carrito precargado.** El mensaje enlaza al producto; el paso natural siguiente es un
enlace que arme el pedido de un toque, que es donde está la mayor parte de la conversión.

**Los factores de consumo son referencias razonables, no una recomendación veterinaria.** Sirven
para estimar cuándo se acaba una bolsa. La ración correcta de un animal la indica la tabla del
fabricante o su veterinario, y conviene que el mensaje nunca sugiera lo contrario.
