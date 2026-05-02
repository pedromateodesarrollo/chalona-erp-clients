# Quickstart — Cliente C# (.NET)

## Audiencia

Esta guía es para un **integrador** que quiere consumir el motor C#
hot-reload publicado por Chalona desde una app .NET. Tú no hospedás
Postgres ni publicás nada — Chalona ya lo hizo. Tu app solo se
conecta a la BD de Chalona y baja el driver.

Si querés hospedar tu propio motor (forkear el patrón hot-reload para
tu producto), saltá al final: [Self-hosting (avanzado)](#self-hosting-avanzado).

## Pre-requisitos

- .NET SDK 8.0+
- Acceso de red a la BD Postgres de Chalona (host, port, db, user, pass —
  provistos por Chalona)

**No necesitás aplicar schema ni publicar nada.** El motor vive en la BD
de Chalona y se baja a tu app via lookup.

## Por qué C# y no Dart

C# tiene mejor soporte para carga dinámica:

- **Roslyn** compila C# completo a IL bytes (no subset).
- **AssemblyLoadContext** soporta `Unload()` real → libera memoria del
  driver viejo en hot-swap. Dart con `dart_eval` no puede.
- Driver puede usar tipos host directamente (interfaz compartida vía
  proyecto referenciado), sin bridges.
- Performance JIT, no interpretado.

Trade-off: ensamblados son más grandes (~6-30 KB vs ~10-15 KB de
`dart_eval`).

## 1. Build

```bash
cd csharp
dotnet build
```

## 2. Configurar conexión y usar

```csharp
using ChalonaCsDriver;

await using var source = new PostgresDriverSource(
    host:     "<host_provisto_por_chalona>",
    port:     5432,
    database: "<db_provista>",
    username: "<usuario_provisto>",
    password: "<clave_provista>",
    entorno:  "test");   // o "produccion"

DriverHandle? driver = null;

async Task<bool> ValidarComprobante(IReadOnlyDictionary<string, object?> doc)
{
    var meta = await source.LookupAsync()
        ?? throw new Exception("no driver activo");

    if (driver?.Version != $"v{meta.Version}")
    {
        driver?.Unload();   // libera memoria del viejo
        var bytes = await source.DescargarAsync();
        driver = DriverHandle.Cargar(bytes, $"v{meta.Version}");
        if (driver.HashSha256 != meta.HashSha256)
            throw new Exception("hash mismatch");
    }

    var (ok, _) = driver.Instancia.PreValidar(doc);
    return ok;
}
```

En producción agregá: cache local en disco entre arranques, retry con
backoff si lookup falla, fallback al driver cacheado si el server está
caído.

## 3. Demo CLI

```bash
dotnet run --project src/ChalonaCsDriver.Cli -- test 133084503
```

Argumentos: `[test|produccion] [RNC]`. Salida esperada:

```
=== prueba-comprobantes-driver C# — entorno="test" ===
Driver activo: v1 tam=6144 sha=5ffde15c43f9...
✓ hash verificado
✓ instancia: ChalonaCsDriver.DriverDinamico.DriverV2

[1] ✓ Factura crédito fiscal OK
[2] ✗ Factura crédito fiscal sin RNC comprador
       · rnc_comprador requerido para tipo 31 (Crédito Fiscal)
...
--- Resumen ---
Aceptados:  3 / Rechazados: 6 / Total: 9
```

## Contrato del driver

El driver descargado declara una clase pública que implementa
`IComprobanteDriver`:

```csharp
namespace ChalonaCsDriver.DriverDinamico;

public sealed class MiDriver : IComprobanteDriver
{
    public string Version => "v3";

    public (bool Ok, IReadOnlyList<string> Errores) PreValidar(
        IReadOnlyDictionary<string, object?> comprobante)
    {
        // logica
        return (true, Array.Empty<string>());
    }
}
```

El loader busca el primer tipo público no abstracto que implementa la
interfaz.

## Sin limitaciones tipo `dart_eval`

Todo C# funciona: LINQ, async/await, records, pattern matching, generics
avanzados, `decimal`, nullable refs, `dynamic`, `System.Text.Json`, etc.

## AOT / Native AOT

`AssemblyLoadContext` requiere JIT. En **.NET Native AOT** (PublishAot)
el patrón no funciona — igual que con Dart AOT. Para iOS / Mac Catalyst
con AOT obligado, no hay solución limpia.

Si tu target es .NET runtime estándar (server, desktop, WPF, WinForms,
Blazor server, MAUI Android), funciona perfecto.

## Layout del cliente

```
csharp/
├── ChalonaCsDriver.sln
├── publicar.sh                            # solo si self-hosting
├── src/
│   ├── ChalonaCsDriver/                   # libreria: Loader, PostgresSource, IComprobanteDriver
│   ├── ChalonaCsDriver.Compile/           # compila .cs → .dll (solo self-hosting)
│   └── ChalonaCsDriver.Cli/               # demo CLI
└── driver_src/                            # solo relevante si self-hosting
    ├── DriverComprobantes.cs
    └── DriverComprobantesV1.cs
```

---

## Self-hosting (avanzado)

Solo si querés hospedar tu propio motor.

### Pre-requisitos extra

- Postgres con el [schema](../sql/schema.sql) aplicado
- `psql` y `python3` en el PATH

### 1. Aplicar schema

```bash
psql -h localhost -U postgres -d midb -f ../sql/schema.sql
```

Crea `data.cs_cliente_driver` + `fn.cs_cliente_driver_lookup/descargar/publicar`.

### 2. Publicar

```bash
PG_HOST=localhost PG_DB=midb PG_USER=postgres PG_PASS=secret \
  ./publicar.sh
```

Compila `driver_src/DriverComprobantes.cs` con Roslyn → `.dll`, calcula
sha256, llama `fn.cs_cliente_driver_publicar`, inserta como activa en
`entorno='test'`.

Producción: `./publicar.sh --produccion`. Otra fuente:
`./publicar.sh --fuente=driver_src/X.cs`.

### 3. Hot-reload

Modificá el driver fuente. Republicá. Próxima llamada del cliente baja
versión nueva — sin recompilar el binario.
