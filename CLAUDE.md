# Las Palomitas de los Abuelos — Mini-POS por WhatsApp

Sistema de pedidos para un negocio casero de palomitas artesanales **sobre pedido**
(zonas Héroes, Tecámac y parte de Ojo de Agua, Estado de México). El cliente llega por
un **QR**, arma su pedido en una página web, y al confirmar se abre **WhatsApp** con el
pedido ya escrito. No hay bot: el handoff es un deep link `wa.me`.

> Documento de contexto para continuar el desarrollo. Léelo completo antes de tocar código.

---

## 1. Decisiones de arquitectura (y por qué)

- **Sin bot. `wa.me` con texto prellenado.** Deliberado: a la escala del negocio, un bot
  (WhatsApp Cloud API) agrega verificación de Meta, webhook y complejidad sin valor
  proporcional. El cliente pica "enviar" manualmente — es una limitación **aceptada** del
  enfoque, no un pendiente.
- **SPAs de un solo archivo, Vue 3 vía CDN, sin build step.** Se despliegan como estáticos
  en cualquier hosting. No introducir bundlers/frameworks salvo que haya una razón fuerte.
- **Supabase (Postgres) como backend.** Catálogo en vivo, stock, pedidos y auth del panel.
- **Validación de costos del lado servidor** vía función RPC `crear_pedido` (ver §8). El
  cliente **nunca** decide precios; solo manda `key` + `qty`.
- **Catálogo data-driven.** Crecer = agregar filas (o entradas en los arrays de fallback).
  La lógica no se toca para sumar sabores, combos o extras.
- **Logo embebido** como data URI WebP (autocontenido; se puede externalizar para aligerar).

## 2. Stack

- **Frontend:** Vue 3 (global build por CDN, Composition API), CSS a mano. Sin build.
- **Cliente Supabase:** `@supabase/supabase-js@2` (UMD por CDN).
- **Backend:** Supabase — Postgres + RLS + Auth + RPC (plpgsql).
- **Hosting objetivo:** estático (Cloudflare Pages / Vercel / Netlify), plan gratis.
- **Pruebas:** Node + `jsdom` (monta las SPAs con un cliente Supabase simulado) y
  `@electric-sql/pglite` (corre el SQL contra un Postgres real en WASM).

## 3. Estructura de archivos

```
pedidos-palomitas.html   # SPA del cliente (menú + comanda + handoff a WhatsApp)
admin.html               # Panel de administración (auth + CRUD + dashboard)
schema.sql               # Esquema Postgres: tablas, RLS, seed del catálogo, función crear_pedido
CLAUDE.md                # Este documento
```

Cada HTML tiene, arriba del `<script>` de la app, un bloque de config con:
```js
const SUPABASE_URL = 'https://TU-PROYECTO.supabase.co';
const SUPABASE_ANON_KEY = 'TU-ANON-KEY';
```
Mientras estén en placeholder: el cliente usa un catálogo local embebido (fallback) y el
panel muestra una pantalla de "falta configurar".

## 4. Modelo de datos (Postgres)

- **config** (una fila, `id=1`): negocio, whatsapp_numero, pedido_minimo, anticipacion_dias,
  tope_por_sabor, costo_envio, anticipo_pct, hora_abre, hora_cierra, horario, zonas (jsonb).
- **tamanos** (`id` PK text: `chica|mediana|grande|extra_grande`, nombre, orden): catálogo de
  tamaños. No trae precio (ver `precios_tamano`).
- **precios_tamano** (`categoria` + `tamano_id` PK compuesta, precio): matriz de precio por
  categoría (`salado|dulce|icee`) × tamaño. Reemplaza a la vieja tabla `gramajes` (un solo precio
  global por peso); ahora el precio depende de la categoría del sabor, no solo del tamaño.
- **sabores** (`id` PK text, nombre, cat `salado|dulce|icee`, icon, img, badge, disponible,
  stock, orden). El precio **no** vive aquí: sale de `precios_tamano` cruzando `cat` del sabor
  con el tamaño elegido.
- **combos** (`id`, nombre, descripcion, precio, icon, badge, combo_hint, envio_incluido,
  disponible, stock, orden).
- **extras** (`id`, nombre, descripcion, precio, icon, cat, disponible, stock, orden).
- **orders** (`id` uuid, creado, cliente, fecha_entrega, entrega, zona, direccion, pago,
  items jsonb, piezas, subtotal, envio, total, anticipo, notas,
  estatus `pendiente|confirmado|entregado|cancelado`). `direccion` es texto libre (sin API de
  mapas/geocoding), solo se llena cuando `entrega = envio`.

**Claves compuestas del carrito:** las palomitas se identifican como `"<saborId>:<tamanoId>"`
(ej. `queso:grande`); combos y extras usan su `id` directo. `items` en `orders` guarda
`[{key, nombre, qty, importe, tipo, comboHint}]`.

## 5. Catálogo y configuración de negocio (valores actuales)

- **Marca:** "Las Palomitas de los Abuelos" — *Sabor artesanal sobre pedido · Por gramo y con amor*.
- **WhatsApp:** `525566707620` (52 + 10 dígitos). Si no llegan mensajes, probar `5215566707620`.
- **Zonas de envío:** Zona Héroes 1–6, Tecámac, Ojo de Agua (cobertura parcial). **Envío $30**;
  pickup con indicaciones por WhatsApp.
- **Reglas:** pedido mínimo **5 paquetes de palomitas o un combo**; anticipación mínima **1 día**;
  tope **10 por sabor y tamaño** (más = pedido especial); **anticipo 50%**; horario **10–22 h**.
- **Pago:** efectivo o transferencia.

**Precios por tamaño y categoría** (decisión del negocio; el margen queda por debajo del ~70%
histórico en tamaños chicos — se avisó y se dejó así a propósito):

| Tamaño | Saladas | Dulces | Icees |
|---|---|---|---|
| Chica | $15 | $25 | $25 |
| Mediana | $25 | $35 | $35 |
| Grande | $45 | $55 | $55 |
| Extra grande | $60 | $80 | $80 |

Icees usa la misma tabla que dulces. No se muestra el peso en gramos en la UI (solo el nombre
del tamaño), aunque cada tamaño puede llevar un peso de referencia interno para control de costos.

**Combos:** Pack Degustación $299 (4×150 g, envío incluido) · Pack Fiesta $549 (6×200 g, envío
incluido) · Combo Cine $175 (2×100 g + 2 refrescos).
**Extras:** Refresco lata 355 ml $28 · Agua 600 ml $18 · Dulces surtidos $35.
**Sabores (20):** salados (Naturales/saladas, Queso, Rufles, Mantequilla, Doritos rojos, Takis,
Cremas y especias, Chile y limón, Esquites), dulces (Caramelo, Chocolate, Galleta Oreo,
Queso-caramelo, Mora azul, Uva, Sandía, Picafresa) e icees (Azul, Rojo, Combinada).

## 6. Flujo del pedido

1. Cliente arma la comanda (sabor + tamaño, combos, extras), fecha (selector bloquea antes del
   mínimo de anticipación), entrega (pickup/envío + zona + dirección si es envío), pago, notas.
2. Validaciones de UI: mínimo, tope por línea, nombre y fecha obligatorios.
3. Al confirmar, **si hay Supabase**: `sb.rpc('crear_pedido', { p_items:[{key,qty}], ... })`.
   La función recalcula todo desde el catálogo, valida y **registra** el pedido en `orders`.
4. El mensaje de WhatsApp se arma con los **totales que devuelve el servidor** y se abre `wa.me`.
5. **Sin Supabase** (llaves en placeholder): modo local, calcula en el cliente y abre `wa.me`
   igual (para pruebas/preview).

## 7. Seguridad / RLS

- Lectura del catálogo: pública (`anon`). Escritura del catálogo: solo `authenticated` (panel).
- `orders`: **no** hay insert directo. La única vía de alta es la función `crear_pedido`
  (`SECURITY DEFINER`), que salta RLS de forma controlada. Lectura/edición de pedidos: solo admin.
- La `anon key` es segura en el frontend (es su propósito); la protección real está en RLS + la función.
- El panel se protege con Supabase Auth (email/password). Servir `admin.html` en una ruta poco obvia.

## 8. Función `crear_pedido` (validación de costos)

`crear_pedido(p_cliente, p_fecha, p_entrega, p_zona, p_pago, p_items jsonb, p_notas, p_direccion default null) → jsonb`

- Recorre `p_items` (solo `key`+`qty`; **ignora cualquier precio del cliente**).
- Resuelve cada `key`: `sabor:tamano` → toma la `cat` del sabor y busca el precio en
  `precios_tamano` cruzando `categoria` + `tamano_id`; si no, busca en combos y luego en extras.
- `p_direccion` solo se guarda cuando `p_entrega = 'envio'`.
- Valida: producto existe, `disponible`, `stock` suficiente, y **pedido mínimo** (5 palomitas o combo).
- Calcula subtotal, envío (0 si combo con `envio_incluido`), total y anticipo desde `config`.
- Inserta en `orders` y devuelve `{order_id, items, piezas, subtotal, envio, envio_gratis, total, anticipo, es_envio}`.

## 9. Estado actual (hecho y probado)

- ✅ SPA del cliente: catálogo en vivo desde Supabase con fallback local; oculta agotados/no
  disponibles; comanda tipo ticket; selector de tamaño por sabor (precio según categoría);
  dirección de entrega cuando es envío; combos y extras; pill de estatus por horario; branding
  del logo; handoff a WhatsApp.
- ✅ Validación de costos server-side (`crear_pedido`) + registro de pedidos.
- ✅ Panel admin: login, CRUD de config/tamaños (matriz de precio por categoría)/sabores/combos/
  extras (con disponible + stock), lista de pedidos con cambio de estatus (incluye dirección), y
  **dashboard "Resumen"** (pedidos de hoy y monto,
  anticipos por cobrar, ventas confirmadas, total, conteo por estatus, top de productos).
- ✅ `schema.sql` idempotente con tablas, RLS, seed del catálogo y la función.

### Pruebas (correr antes de dar por bueno)

Enfoque: lógica pura en Node; SQL contra Postgres real (pglite); SPAs montadas en jsdom con
Supabase simulado. Los archivos de prueba usan `vue`, `jsdom` y `@electric-sql/pglite` (npm) y
no están incluidos en este repo (se recrean/exportan aparte).

> ⚠️ **Desactualizado tras el cambio de gramajes → tamaños (2026-08-19).** La última corrida
> verde (schema 12/12, función 10/10, cliente 14/14, panel 13/13) fue contra el modelo viejo de
> `gramajes`. Con `tamanos` + `precios_tamano` y el campo `direccion`, hay que rehacer/actualizar
> esas suites antes de confiar en "probado" otra vez — no se han vuelto a correr.

## 10. Backlog (priorizado por valor real)

1. **Deploy + validación end-to-end con un pedido real.** Todo está probado con mocks/pglite,
   pero la conexión viva al proyecto Supabase aún no se ejerce. Es lo siguiente.
2. **Descuento automático de stock al confirmar.** Hoy el stock es editable a mano y oculta
   agotados; el descuento **no** es automático. Punto veraz de descuento = cuando el admin marca
   el pedido `confirmado` (no al picar el botón, porque `wa.me` puede no enviarse). Implementar con
   una función Postgres atómica para no dejar stock negativo. *No urgente a baja escala.*
3. **Subida de imágenes** a Supabase Storage (hoy `img` es una URL manual).
4. **Dominio propio** (opcional, ~$200 MXN/año un `.com`).

## 11. Limitaciones y tradeoffs aceptados

- `wa.me` **prellena**, no auto-envía: el cliente pica "enviar". No hay forma de evitarlo sin bot.
- Descuento de stock manual por ahora (ver backlog #2).
- Logo embebido (~125 KB) en el HTML: autocontenido pero pesa; se puede externalizar a `logo.webp`.
- Los arrays de catálogo embebidos en la SPA son **fallback/semilla**: si se editan, mantenerlos
  en sync con la base (la fuente de verdad en producción es Supabase).
- El seed de `schema.sql` solo aplica a instalaciones nuevas; cambios posteriores van por el panel.
- Un solo admin (email/password). Sin otra ofuscación más que servir el panel en ruta discreta.

## 12. Fuera de alcance (no construir salvo que el negocio lo pida)

- Pasarela de pago, app nativa, bot/WhatsApp Cloud API.
- Notificaciones: **no hacen falta** — el pedido llega por WhatsApp. `orders` es bitácora/dashboard,
  no canal de aviso.

## 13. Cómo trabajar en este repo

- **Sin build step.** Mantener Vue por CDN y archivos únicos salvo razón fuerte.
- **Ediciones mínimas, sin duplicar lógica.** Las funciones puras (parseo de `key`, cálculo de
  totales, armado del mensaje) comparten forma entre cliente y SQL; mantener esa correspondencia.
- **Catálogo = datos.** Para agregar productos: panel (producción) o los arrays de fallback.
- **Config al inicio** de cada HTML (`SUPABASE_URL`, `SUPABASE_ANON_KEY`).
- **Probar antes de cerrar** cualquier cambio: correr las suites (o replicarlas si se recrean).
- Verificar que los HTML queden **UTF-8** y sin caracteres de reemplazo (los emojis importan).

## 14. Despliegue (una sola vez)

1. Crear proyecto en supabase.com (plan gratis).
2. **SQL Editor → New query →** pegar `schema.sql` completo → **Run** (idempotente).
3. **Authentication → Users → Add user**: correo + contraseña (marcar correo confirmado). Ese es el acceso al panel.
4. **Project Settings → API**: copiar *Project URL* y *anon public key*.
5. Pegar ambos en el bloque de config de **los dos** HTML (mismos valores).
6. Subir los dos HTML a hosting estático (Cloudflare Pages / Vercel / Netlify). El QR apunta a
   `pedidos-palomitas.html`; `admin.html` en ruta discreta.
7. Prueba de humo: hacer un pedido real, verificar que llegue el WhatsApp, que aparezca en `orders`
   y que un cambio de precio/disponible en el panel se refleje al recargar el sitio.
