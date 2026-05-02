# Quickstart — Cliente Python

## Pre-requisitos

- Python 3.9+
- Postgres con el [schema](../sql/schema.sql) aplicado
- `psql` en el PATH (loader y publisher lo usan)

## Diferencia respecto a otros clientes

`.pyc` (bytecode CPython) varía por versión de intérprete y plataforma, así
que **se publica el `.py` source UTF-8**. El cliente lo ejecuta con `exec()`
sobre un namespace `dict` aislado:

- El loader **inyecta** la clase base `ComprobanteDriver` al namespace antes
  de `exec()`, para que el driver herede sin necesidad de importar el
  paquete `chalona_driver` (importante: el cliente puede no tenerlo
  instalado en su entorno).
- Hot-swap = descartar el `dict` viejo y dejar que GC libere las clases.
  Funciona porque CPython hace refcounting agresivo.
- Dependencias del runtime: **cero**. Solo `psql` binary + Python stdlib.

## Layout

```
python-driver/
├── pyproject.toml
├── publicar.sh                              # publisher CLI
├── src/chalona_driver/
│   ├── __init__.py
│   ├── contract.py                          # ABC ComprobanteDriver
│   ├── loader.py                            # DriverHandle.cargar() + cache
│   ├── postgres_source.py                   # psql via subprocess
│   └── compiler.py                          # validar AST + retornar bytes
├── bin/
│   ├── compilar.py                          # CLI: .py → bytes
│   └── prueba_comprobantes_driver.py        # demo CLI: 9 casos
└── driver_src/
    └── driver_comprobantes.py               # driver con validación e-CF
```

## 1. Aplicar schema

```bash
psql -h localhost -U postgres -d midb -f ../sql/schema.sql
```

Crea `data.python_cliente_driver` + `fn.python_cliente_driver_lookup/descargar/publicar`.

## 2. (Opcional) Instalar como paquete

```bash
cd python-driver
pip install -e .
```

No es obligatorio — los scripts en `bin/` añaden `src/` al `sys.path` automáticamente.

## 3. Publicar el driver

```bash
PG_HOST=localhost PG_DB=midb PG_USER=postgres PG_PASS=secret \
./publicar.sh
```

Esto:

1. Valida sintaxis del `.py` con `ast.parse` (fail-fast).
2. Lee bytes UTF-8.
3. Calcula sha256.
4. Llama `fn.python_cliente_driver_publicar` (verifica hash server-side).
5. Inserta como versión activa en `entorno='test'`.

Producción: `./publicar.sh --produccion`. Otra fuente: `./publicar.sh --fuente=driver_src/X.py`.

## 4. Correr el cliente de prueba

```bash
PG_HOST=localhost PG_DB=midb PG_USER=postgres PG_PASS=secret ENTORNO=test \
python3 bin/prueba_comprobantes_driver.py
```

Salida esperada:

```
== Lookup driver Python @ test (localhost:5432/midb)
   activo: v1  3618 bytes  sha256=a60df21aa390...
   cargado: instancia.version='v1'

== Casos:
   [OK  ] tipo 31 OK
   [OK  ] tipo 32 OK monto bajo
   [OK  ] tipo inválido errores=['tipo inválido: 99 (debe ser 31, 32, 33 o 34)']
   ...

9 pasaron, 0 fallaron
```

## 5. Hot-reload en acción

Modifica `driver_src/driver_comprobantes.py`. Republica:

```bash
./publicar.sh
```

Re-corre el cliente — baja la versión nueva sin reinstalar.

## Integrar en tu app

```python
from chalona_driver import PostgresDriverSource, PgConn, DriverHandle

source = PostgresDriverSource(
    PgConn("localhost", 5432, "midb", "user", "pass"),
    "produccion",
)

driver: DriverHandle | None = None

def validar_comprobante(doc: dict) -> bool:
    global driver
    meta = source.lookup()
    if meta is None:
        raise RuntimeError("no driver")

    if driver is None or driver.version != f"v{meta.version}":
        bytes_drv = source.descargar()
        driver = DriverHandle.cargar(bytes_drv, f"v{meta.version}")
        if driver.hash_sha256 != meta.hash_sha256:
            raise RuntimeError("hash mismatch")

    ok, _errs = driver.instancia.pre_validar(doc)
    return ok
```

En producción agrega:

- Cache local en disco entre arranques (`DriverCache` en `loader.py`)
- Retry con backoff si lookup falla
- Fallback al último driver cacheado si el server está caído

## Contrato del driver

El driver descargado debe definir una clase que herede de `ComprobanteDriver`
(la clase base se inyecta automáticamente al namespace por el loader — no
hace falta importarla):

```python
class MiDriver(ComprobanteDriver):  # type: ignore[name-defined]
    @property
    def version(self) -> str:
        return "v3"

    def pre_validar(self, c) -> tuple[bool, list[str]]:
        # tu lógica
        return (True, [])
```

El loader busca la primera clase concreta del namespace que sea subclase de
`ComprobanteDriver` (excluyendo la base misma).

## Por qué `exec` y no `importlib`

`importlib.util.spec_from_loader` requiere que el código viva en un módulo
con nombre estable y registrado en `sys.modules`. `exec()` con un `dict`
fresco es más simple para el caso "cargar este código en un sandbox y
descartar":

- No contamina `sys.modules`.
- GC libera el namespace cuando lo descartas.
- Sin side-effects entre versiones.

## Seguridad

`exec()` ejecuta código arbitrario con todos los privilegios del proceso
host. Esto es **por diseño** — el código viene del servidor que ya
controlas. No expongas `data.python_cliente_driver` a usuarios no
confiables y revisa el SQL de `fn.python_cliente_driver_publicar`
(solo `Interno` debería poder publicar).

Para sandboxing real (drivers de terceros), considera `RestrictedPython` o
correr el driver en un subprocess con seccomp/limits — fuera del scope
del patrón loader simple.

## Limitaciones

- **No `.pyc`**: ship source. Visible en la BD si alguien consulta
  `data.python_cliente_driver.bytes`. Considéralo público.
- **No hot-unload "real"**: depende de refcounting + GC. Funciona bien si
  no guardas referencias largas a instancias del driver viejo.
- **Imports estándar OK**: el driver puede `import json`, `import re`, etc.
  Imports de paquetes terceros funcionan si están instalados en el cliente.
