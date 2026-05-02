# Arquitectura

## Patrón "version-on-request"

El cliente y el servidor mantienen un acuerdo simple: cada request del cliente
declara qué versión de lógica está corriendo. Si esa versión no coincide con
la activa en el servidor, el servidor rechaza la operación con un código
específico y la metadata de la versión nueva. El cliente baja, intercambia su
runtime, y reintenta.

```
Cliente                                Servidor
--------                               --------
POST /endpoint  doc + ver=7        →
                                       activa = 9
                                       7 ≠ 9
                                   ←   { ok: false,
                                         code: "version_desactualizada",
                                         version_actual: 9 }
GET  /driver/v9                    →
                                   ←   bytes (.evc / .prg)
[swap atómico del runtime]
POST /endpoint  doc + ver=9        →
                                       activa = 9
                                   ←   { ok: true, data: ... }
```

**Por qué este patrón gana**:

- **Sin polling**: el cliente solo se entera de una versión nueva cuando va
  a usar la lógica. Aplicaciones inactivas no consumen ancho de banda.
- **Sin push**: ningún websocket / SSE / mecanismo de notificación. La BD
  manda; el cliente reacciona en su próximo turno.
- **Auto-recuperación**: si un swap falla a mitad, el siguiente request lo
  cura. Sin estado huérfano.

## Almacenamiento

Las dos tablas viven en la misma BD que el resto del backend. La versión
activa se distingue por una columna `activo` con índice único parcial:

```sql
CREATE UNIQUE INDEX ON data.dart_cliente_driver (entorno)
  WHERE activo = true;
```

Esto garantiza que **siempre** hay máximo una versión activa por entorno.
Publicar una nueva = `UPDATE viejas SET activo=false; INSERT nueva (activo=true)`.

Las versiones anteriores quedan en la tabla para rollback (revertir = volver a
poner una vieja como `activo=true`).

## Verificación de integridad

Al publicar bytecode Dart, el servidor recalcula el sha256 sobre los bytes
recibidos y lo compara con el hash declarado por el publisher. Si no
coinciden, rechaza la publicación. Esto detecta corrupción en tránsito o
manipulación.

El cliente, al bajar, vuelve a calcular el hash y lo compara con el que viene
en la metadata. Defensa en profundidad.

## Hot-swap atómico

### Fox

VFP soporta `SET PROCEDURE TO <archivo>.fxp ADDITIVE` que reemplaza el set de
procedimientos vivo sin reiniciar. El loader baja el .prg, lo compila a .fxp
con un nombre único (timestamp), y emite el `SET PROCEDURE`. Las llamadas
siguientes resuelven contra el código nuevo.

### Dart

`dart_eval` permite instanciar un `Runtime` nuevo desde bytes. El cliente
descarta el runtime viejo (queda elegible para GC) y empieza a llamar el nuevo.
Si hay requests en vuelo, el código actual del PoC los deja terminar antes de
soltar la referencia (ver [hot-swap-drain.md](hot-swap-drain.md)).

## Trade-offs por cliente

| | Fox | Dart |
|---|---|---|
| Lenguaje del driver | VFP (`.prg`) | Dart subset (compilado a `.evc`) |
| Tipo de payload | Texto | Binario (bytecode) |
| Tamaño típico | 50-200 KB | 10-15 KB |
| Subset del lenguaje | Toda VFP funciona | Subset de Dart (ver `dart-eval-limitations.md`) |
| Velocidad | Lenta (interpretado) | ~5-20× más lento que AOT, OK para validación |
| Bridge a tipos host | No aplica (todo es VFP) | Manual con `$Bridge` o codegen |
| Audiencia | ERPs legados | Apps Flutter / Dart server / CLI |

## Limitaciones de seguridad

El driver corre **con los mismos permisos del cliente**. Si el atacante
controla la BD, puede sustituir el driver y ejecutar código arbitrario. La
verificación sha256 protege contra MITM en tránsito, pero no contra la fuente.

Para escenarios donde el publisher no es de confianza, agrega:

- Firma RSA/Ed25519 sobre los bytes, verificada por el cliente con clave
  pública embebida en el binario AOT.
- TLS pinning a nivel de transporte.
- Revisión humana antes de marcar `activo=true`.

Para uso interno (devs publican drivers que sus propios clientes consumen),
el sha256 + TLS estándar suele ser suficiente.
