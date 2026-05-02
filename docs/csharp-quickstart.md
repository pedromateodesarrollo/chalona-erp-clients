# Quickstart — Cliente C# (.NET)

## Pre-requisitos

- .NET SDK 8.0+
- Postgres con el [schema](../sql/schema.sql) aplicado
- `psql` y `python3` en el PATH (publisher los usa)

## Diferencia respecto al cliente Dart

C# tiene mejor soporte que Dart para carga dinámica de código:

- **Roslyn** compila C# completo a IL bytes (no subset, no warts).
- **AssemblyLoadContext** soporta `Unload()` real → libera memoria del driver
  viejo cuando haces hot-swap. Dart con `dart_eval` no puede hacer esto —
  solo descarta la referencia.
- Driver puede usar tipos host directamente (interfaz compartida vía proyecto
  referenciado), sin bridges.
- Performance JIT, no interpretado — sin overhead 5-20×.

Trade-off: ensamblados son más grandes (~6-30 KB vs ~10-15 KB de `dart_eval`).

## Layout

```
csharp/
├── ChalonaCsDriver.sln
├── publicar.sh                            # publisher CLI
├── src/
│   ├── ChalonaCsDriver/                   # librería: Loader, PostgresSource, IComprobanteDriver
│   ├── ChalonaCsDriver.Compile/           # helper: compila .cs → .dll
│   └── ChalonaCsDriver.Cli/               # demo CLI: 9 casos de prueba
└── driver_src/
    ├── DriverComprobantes.cs              # driver "estricto" (validación e-CF completa)
    └── DriverComprobantesV1.cs            # driver "laxo" (solo tipo + fecha)
```

## 1. Aplicar schema

```bash
psql -h localhost -U postgres -d midb -f ../sql/schema.sql
```

Crea `data.cs_cliente_driver` + `fn.cs_cliente_driver_lookup/descargar/publicar`.

## 2. Build

```bash
cd csharp
dotnet build
```

## 3. Publicar el driver

```bash
PG_HOST=localhost PG_DB=midb PG_USER=postgres PG_PASS=secret \
./publicar.sh
```

Esto:

1. Compila `driver_src/DriverComprobantes.cs` con Roslyn → `.dll` IL bytes.
2. Calcula sha256.
3. Llama `fn.cs_cliente_driver_publicar` (verifica hash server-side).
4. Inserta como versión activa en `entorno='test'`.

Producción: `./publicar.sh --produccion`. Otra fuente: `./publicar.sh --fuente=driver_src/X.cs`.

## 4. Correr el cliente

```bash
dotnet run --project src/ChalonaCsDriver.Cli
# argumentos: [test|produccion] [RNC]
dotnet run --project src/ChalonaCsDriver.Cli -- test 133084503
dotnet run --project src/ChalonaCsDriver.Cli -- produccion 133084503
```

Salida esperada:

```
=== prueba-comprobantes-driver C# — entorno="test" (BD test en localhost:5433) ===
Driver activo: v1 entorno=test tam=6144 sha=5ffde15c43f9...

✓ hash verificado: 5ffde15c43f9...
✓ instancia: ChalonaCsDriver.DriverDinamico.DriverV2 (driver.Version=v2)

[1] ✓ Factura crédito fiscal OK
[2] ✗ Factura crédito fiscal sin RNC comprador
       · rnc_comprador requerido para tipo 31 (Crédito Fiscal)
...

--- Resumen ---
Driver:     test v1
Aceptados:  3
Rechazados: 6
Total:      9
```

## 5. Hot-reload en acción

Modifica `driver_src/DriverComprobantes.cs` (cambia una regla, agrega validación).
Republica:

```bash
./publicar.sh
```

Re-corre el cliente — baja la versión nueva sin recompilar el binario.

## Integrar en tu app

```csharp
using ChalonaCsDriver;

await using var source = new PostgresDriverSource(
    "localhost", 5432, "midb", "user", "pass", "produccion");

DriverHandle? driver = null;

async Task<bool> ValidarComprobante(IReadOnlyDictionary<string, object?> doc)
{
    var meta = await source.LookupAsync()
        ?? throw new Exception("no driver");

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

En producción agrega:

- Cache local en disco entre arranques
- Retry con backoff si lookup falla por red
- Fallback a último driver cacheado si el server está caído

## Contrato del driver

El driver descargado debe declarar una clase pública que implemente
`IComprobanteDriver`:

```csharp
namespace ChalonaCsDriver.DriverDinamico;

public sealed class MiDriver : IComprobanteDriver
{
    public string Version => "v3";

    public (bool Ok, IReadOnlyList<string> Errores) PreValidar(
        IReadOnlyDictionary<string, object?> comprobante)
    {
        // tu lógica
        return (true, Array.Empty<string>());
    }
}
```

El loader busca el primer tipo público no abstracto que implemente la interfaz.

## Sin limitaciones tipo `dart_eval`

A diferencia del cliente Dart, **todo C# funciona**:

- LINQ, async/await, records, pattern matching, generics avanzados
- `decimal` para montos (en Dart usábamos `double` por restricciones)
- Nullable reference types
- `dynamic` (si lo necesitas)
- `System.Text.Json`, `System.Globalization`, todo `dart:io`-equivalent

## AOT / Native AOT

`AssemblyLoadContext` requiere JIT. En **.NET Native AOT** (PublishAot) el
patrón no funciona — igual que con Dart AOT. Para iOS / Mac Catalyst con
AOT obligado, no hay solución limpia.

Si tu target es .NET runtime estándar (server, desktop, WPF, WinForms,
Blazor server, MAUI Android), funciona perfecto.
