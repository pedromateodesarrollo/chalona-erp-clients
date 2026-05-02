# Quickstart — Cliente Python

## Audiencia

Esta guía es para un **integrador** que quiere consumir el motor Python
hot-reload publicado por Chalona desde una app Python. Tú no hospedás
Postgres ni publicás nada — Chalona ya lo hizo. Tu app solo se conecta
a la BD de Chalona y baja el driver.

Si querés hospedar tu propio motor (forkear el patrón hot-reload para
tu producto), saltá al final: [Self-hosting (avanzado)](#self-hosting-avanzado).

## Pre-requisitos

- Python 3.9+
- `psql` en el PATH (loader lo usa para hablar Postgres sin deps)
- Acceso de red a la BD Postgres de Chalona (host, port, db, user, pass —
  provistos por Chalona)

**No necesitás aplicar schema ni publicar nada.** El motor vive en la BD
de Chalona y se baja a tu app via lookup.

## Mecanismo

`.pyc` (bytecode CPython) varía por versión de intérprete y plataforma,
así que **se publica el `.py` source UTF-8**. El cliente lo ejecuta con
`exec()` sobre un namespace `dict` aislado:

- El loader inyecta la clase base `ComprobanteDriver` al namespace antes
  de `exec()` para que el driver herede sin importar `chalona_driver`.
- Hot-swap = descartar el `dict` viejo y dejar que GC libere las clases.
- Dependencias del runtime: **cero**. Solo `psql` binary + Python stdlib.

## 1. Instalar (opcional)

```bash
cd python-driver
pip install -e .
```

No es obligatorio — los scripts en `bin/` añaden `src/` al `sys.path`
automáticamente.

## 2. Configurar conexión y usar

```python
from chalona_driver import PostgresDriverSource, PgConn, DriverHandle

source = PostgresDriverSource(
    PgConn(
        host="<host_provisto_por_chalona>",
        port=5432,
        database="<db_provista>",
        user="<usuario_provisto>",
        password="<clave_provista>",
    ),
    "test",   # o "produccion"
)

driver: DriverHandle | None = None

def validar_comprobante(doc: dict) -> bool:
    global driver
    meta = source.lookup()
    if meta is None:
        raise RuntimeError("no driver activo")

    if driver is None or driver.version != f"v{meta.version}":
        bytes_drv = source.descargar()
        driver = DriverHandle.cargar(bytes_drv, f"v{meta.version}")
        if driver.hash_sha256 != meta.hash_sha256:
            raise RuntimeError("hash mismatch")

    ok, _errs = driver.instancia.pre_validar(doc)
    return ok
```

En producción agregá: cache local en disco entre arranques (`DriverCache`
en `loader.py`), retry con backoff, fallback al driver cacheado.

## 3. Demo CLI

```bash
PG_HOST=<host> PG_DB=<db> PG_USER=<u> PG_PASS=<p> ENTORNO=test \
  python3 bin/prueba_comprobantes_driver.py
```

Salida esperada:

```
== Lookup driver Python @ test
   activo: v1  3618 bytes  sha256=a60df21aa390...
   cargado: instancia.version='v1'

== Casos:
   [OK  ] tipo 31 OK
   [OK  ] tipo 32 OK monto bajo
   [OK  ] tipo invalido errores=['tipo invalido: 99 ...']
   ...

9 pasaron, 0 fallaron
```

## Contrato del driver

El driver descargado define una clase que hereda de `ComprobanteDriver`
(la clase base se inyecta al namespace por el loader — no hace falta
importarla):

```python
class MiDriver(ComprobanteDriver):  # type: ignore[name-defined]
    @property
    def version(self) -> str:
        return "v3"

    def pre_validar(self, c) -> tuple[bool, list[str]]:
        # logica
        return (True, [])
```

El loader busca la primera clase concreta del namespace que sea subclase
de `ComprobanteDriver`.

## Por qué `exec` y no `importlib`

`importlib.util.spec_from_loader` requiere módulo con nombre estable en
`sys.modules`. `exec()` con `dict` fresco es más simple para "cargar y
descartar":

- No contamina `sys.modules`.
- GC libera el namespace cuando lo descartás.
- Sin side-effects entre versiones.

## Seguridad

`exec()` ejecuta código arbitrario con privilegios del proceso host.
Esto es **por diseño** — el código viene del servidor de Chalona que
controla la publicación. Para drivers de terceros no confiables,
considerar `RestrictedPython` o subprocess con seccomp/limits.

## Limitaciones

- **No `.pyc`**: ship source. Visible en BD si alguien consulta
  `data.python_cliente_driver.bytes`. Considéralo público.
- **No hot-unload "real"**: depende de refcounting + GC. Funciona si no
  guardás referencias largas a instancias del driver viejo.
- **Imports estándar OK**: el driver puede `import json`, `import re`,
  etc. Imports de terceros funcionan si están instalados en el cliente.

## Layout del cliente

```
python-driver/
├── pyproject.toml
├── publicar.sh                              # solo si self-hosting
├── src/chalona_driver/
│   ├── __init__.py
│   ├── contract.py                          # ABC ComprobanteDriver
│   ├── loader.py                            # DriverHandle.cargar() + cache
│   ├── postgres_source.py                   # psql via subprocess
│   └── compiler.py                          # validar AST + retornar bytes
├── bin/
│   ├── compilar.py                          # CLI: .py → bytes
│   └── prueba_comprobantes_driver.py
└── driver_src/                              # solo si self-hosting
    └── driver_comprobantes.py
```

---

## Self-hosting (avanzado)

Solo si querés hospedar tu propio motor.

### Pre-requisitos extra

- Postgres con el [schema](../sql/schema.sql) aplicado

### 1. Aplicar schema

```bash
psql -h localhost -U postgres -d midb -f ../sql/schema.sql
```

Crea `data.python_cliente_driver` + `fn.python_cliente_driver_lookup/descargar/publicar`.

### 2. Publicar

```bash
PG_HOST=localhost PG_DB=midb PG_USER=postgres PG_PASS=secret \
  ./publicar.sh
```

Valida sintaxis con `ast.parse`, lee bytes UTF-8, calcula sha256, llama
`fn.python_cliente_driver_publicar`, inserta activo en `entorno='test'`.

Producción: `./publicar.sh --produccion`. Otra fuente:
`./publicar.sh --fuente=driver_src/X.py`.

### 3. Hot-reload

Modificá el driver fuente. Republicá. Próxima llamada del cliente baja
versión nueva.
