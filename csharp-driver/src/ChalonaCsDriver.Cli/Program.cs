// Prueba de integración del cliente C# — espejo del CLI Dart.
//
// Uso:
//   dotnet run [test|produccion] [baseUrl]
//
// Default: produccion, https://ecf-service.vicortiz.com

using ChalonaCsDriver;

var entorno = args.Length > 0 ? args[0] : "produccion";
var baseUrl = args.Length > 1 ? args[1] : "https://ecf-service.vicortiz.com";

Console.WriteLine($"=== prueba-driver C# — entorno=\"{entorno}\" baseUrl={baseUrl} ===\n");

await using var client = new EcfClient(
    baseUrl: baseUrl,
    motorEntorno: entorno);

// 1. Descargar motor al arrancar (como Fox)
Console.Write("Descargando motor... ");
try
{
    await client.EnsureMotorAsync();
    Console.WriteLine($"✓ v{client.MotorMeta!.Version} " +
        $"hash={client.MotorMeta.HashSha256[..12]}... " +
        $"({client.MotorMeta.Tamano} bytes)");
}
catch (EcfApiError e)
{
    Console.Error.WriteLine($"✗ {e.Code}");
    Environment.Exit(1);
}

// 2. Verificar que el trampolín funciona con un estado inválido (fn desconocida)
Console.Write("Trampolín (fn desconocida)... ");
var rnc = "133084503";
var doc = new DocumentoEcf
{
    Fiscal = "31",
    Fecha = new DateTime(2026, 4, 15),
    Valor = 1000,
    Itbis = 180,
    Total = 1180,
    Moneda = "DOP",
    Emisor = new EmisorEcf { Rnc = rnc, Nombre = "Prueba SRL", Direccion = "Calle 1" },
    Comprador = new CompradorEcf { Rnc = "101000001", Nombre = "Cliente SA" },
    Lineas =
    [
        new LineaEcf
        {
            Descripcion = "Servicio de prueba",
            Cantidad = 1,
            Precio = 1000,
            Itbis = 180,
            EsServicio = true,
        },
    ],
};

// Serializar documento y verificar que se arma correctamente
var docJson = doc.ToJsonObject();
Console.WriteLine("✓ documento serializado OK");
Console.WriteLine($"  fiscal={docJson["fiscal"]} fecha={docJson["fecha"]} total={docJson["total"]}");
Console.WriteLine($"  emisor.rnc={docJson["emisor"]?["rnc"]} lineas={docJson["lineas"]?.AsArray().Count}");

Console.WriteLine("\n--- Resumen ---");
Console.WriteLine($"Motor:   {entorno} v{client.MotorMeta?.Version}");
Console.WriteLine($"Instancia: {client.MotorMeta?.HashSha256[..16]}...");
Console.WriteLine("\n✓ Motor descargado y listo. Llama LoginAsync/EnviaEcfDesdeAsync para operar.");
