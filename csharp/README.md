# ecf-client (C#)

Cliente C# para el API **ecf-service** (comprobantes fiscales electrónicos e-CF, DGII República Dominicana). Equivalente al cliente Python en `ecf/client-python`.

## Requisitos

- .NET 6.0 o superior (probado con .NET 8.0)

## Instalación

Desde NuGet (cuando esté publicado):

```bash
dotnet add package EcfClient
```

O referenciar el proyecto desde tu solución:

```xml
<ProjectReference Include="path/to/ecf/client-csharp/src/EcfClient/EcfClient.csproj" />
```

## Uso rápido

### Cliente HTTP (API directa)

```csharp
using EcfClient;

var client = new EcfClient(); // baseUrl por defecto: https://ecf-service.vicortiz.com
await client.LoginAsync("mi_correo@ejemplo.com", "mi_clave");
// Token queda guardado en el cliente
var result = await client.EnviaEcfAsync("114001607", "testecf", jsonPayload);
var estados = await client.ConsultaEstadoAsync(new[] { "E310000000001", "E310000000002" });
```

### Con clases por tipo de comprobante

```csharp
using EcfClient;
using EcfClient.Comprobantes;
using EcfClient.Comprobantes.Datos; // EmisorData, CompradorData, DetalleItem

var client = new EcfClient();
await client.LoginAsync("usuario@ejemplo.com", "clave");

var comprobante = new FacturaCreditoFiscal31
{
    ENcf = "E310000000001",
    FechaEmision = "01-04-2020",
    FechaVencimientoSecuencia = "31-12-2025",
    Emisor = { Rnc = "114001607", RazonSocial = "Mi Empresa", Direccion = "Calle 1", FechaEmision = "01-04-2020" },
    Comprador = { Rnc = "101000001", RazonSocial = "Cliente SRL" },
    MontoGravadoTotal = 1000,
    MontoGravadoI1 = 1000,
    TotalItbis = 180,
    TotalItbis1 = 180,
    MontoTotal = 1180
};
comprobante.Items.Add(new DetalleItem
{
    NumeroLinea = 1,
    NombreItem = "Servicio",
    IndicadorFacturacion = 1,
    IndicadorBienServicio = 1,
    Cantidad = 1,
    PrecioUnitario = 1000,
    MontoItem = 1000
});

var resultado = await comprobante.EnviarAsync(client, "114001607", "testecf");
```

Portales: `ecf` (producción), `testecf` (pruebas).

## Tipos de comprobante

- **31** – FacturaCreditoFiscal31  
- **32** – FacturaConsumo32 (RFCE si MontoTotal &lt; 250 000)  
- **33** – NotaDebito33 (requiere InformacionReferencia)  
- **34** – NotaCredito34 (requiere InformacionReferencia)  
- **41** – Compras41  
- **43** – GastosMenores43  
- **44** – RegimenEspecial44  
- **45** – Gubernamental45  
- **46** – Exportacion46  
- **47** – PagosExterior47  

## Errores

- **EcfApiException**: respuesta del API con `ok: false` (propiedades `ErrorCode`, `Data`).
- **EcfValidationException**: validación local del comprobante antes de enviar (propiedades `Message`, `Errors`).

## Tests

```bash
cd ecf/client-csharp
dotnet test EcfClient.sln
```

Los tests de integración (contra API real) se pueden añadir y marcar con un trait `integration` para excluirlos en CI.

## Publicar en NuGet

Subir la versión en `src/EcfClient/EcfClient.csproj` (elemento `<Version>`), luego:

```bash
export NUGET_API_KEY=tu_api_key_de_nuget_org
./publish-nuget.sh
```

O manualmente: `dotnet pack src/EcfClient/EcfClient.csproj -c Release` y `dotnet nuget push <ruta>.nupkg --api-key $NUGET_API_KEY --source https://api.nuget.org/v3/index.json`
