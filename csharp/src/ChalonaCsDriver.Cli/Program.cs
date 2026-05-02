// Programa cliente que demuestra:
//   1. Lookup del driver activo en BD
//   2. Descarga de bytes (.dll)
//   3. Verificación de hash SHA256
//   4. Carga vía AssemblyLoadContext
//   5. Ejecución de PreValidar sobre comprobantes mock
//   6. Resumen de aceptados/rechazados
//
// Uso:
//   dotnet run [test|produccion] [RNC]
//
// Default: test, RNC 133084503

using ChalonaCsDriver;

var entorno = args.Length > 0 ? args[0] : "test";
var rnc = args.Length > 1 ? args[1] : "133084503";

var (host, port, db, user, pass) = entorno == "produccion"
    ? ("localhost", 5432, "produccion", "pedro", "chalona@1844")
    : ("localhost", 5433, "test", "pedro", "camila");

Console.WriteLine($"=== prueba-comprobantes-driver C# — entorno=\"{entorno}\" (BD {db} en {host}:{port}) ===");

await using var source = new PostgresDriverSource(host, port, db, user, pass, entorno);

var meta = await source.LookupAsync();
if (meta is null)
{
    Console.Error.WriteLine($"✗ no hay driver C# activo en entorno={entorno}. Publica uno con publicar.sh");
    Environment.Exit(1);
}

Console.WriteLine($"Driver activo: v{meta.Version} entorno={meta.Entorno} tam={meta.Tamano} sha={meta.HashSha256[..12]}...\n");

var bytes = await source.DescargarAsync();
if (bytes.Length != meta.Tamano)
    throw new InvalidOperationException($"tamaño no coincide: {bytes.Length} vs {meta.Tamano}");

using var driver = DriverHandle.Cargar(bytes, $"v{meta.Version}");
if (driver.HashSha256 != meta.HashSha256)
    throw new InvalidOperationException($"hash mismatch: local {driver.HashSha256[..12]} vs servidor {meta.HashSha256[..12]}");

Console.WriteLine($"✓ hash verificado: {driver.HashSha256[..12]}...");
Console.WriteLine($"✓ instancia: {driver.Instancia.GetType().FullName} (driver.Version={driver.Instancia.Version})\n");

// Casos de prueba
var casos = new[]
{
    ("Factura crédito fiscal OK", new Dictionary<string, object?> {
        ["tipo"] = "31", ["fecha_emision"] = "15-04-2026",
        ["rnc_emisor"] = rnc, ["rnc_comprador"] = "101000001",
        ["monto_total"] = 5000.00m,
    }),
    ("Factura crédito fiscal sin RNC comprador", new Dictionary<string, object?> {
        ["tipo"] = "31", ["fecha_emision"] = "15-04-2026",
        ["rnc_emisor"] = rnc, ["monto_total"] = 5000.00m,
    }),
    ("Factura consumo (32) chiquita OK", new Dictionary<string, object?> {
        ["tipo"] = "32", ["fecha_emision"] = "15-04-2026",
        ["rnc_emisor"] = rnc, ["monto_total"] = 1500.00m,
    }),
    ("Factura consumo (32) >= 250k sin comprador", new Dictionary<string, object?> {
        ["tipo"] = "32", ["fecha_emision"] = "15-04-2026",
        ["rnc_emisor"] = rnc, ["monto_total"] = 350000.00m,
    }),
    ("Nota crédito (34) dentro de tope", new Dictionary<string, object?> {
        ["tipo"] = "34", ["fecha_emision"] = "15-04-2026",
        ["rnc_emisor"] = rnc, ["rnc_comprador"] = "101000001",
        ["monto_total"] = 500.00m,
        ["total_factura_referenciada"] = 400.00m,
        ["suma_nd_referenciadas"] = 200.00m,
    }),
    ("Nota crédito (34) excede tope", new Dictionary<string, object?> {
        ["tipo"] = "34", ["fecha_emision"] = "15-04-2026",
        ["rnc_emisor"] = rnc, ["rnc_comprador"] = "101000001",
        ["monto_total"] = 700.00m,
        ["total_factura_referenciada"] = 400.00m,
        ["suma_nd_referenciadas"] = 200.00m,
    }),
    ("Tipo inválido (40)", new Dictionary<string, object?> {
        ["tipo"] = "40", ["fecha_emision"] = "15-04-2026",
        ["rnc_emisor"] = rnc, ["monto_total"] = 100.00m,
    }),
    ("Fecha mal formateada", new Dictionary<string, object?> {
        ["tipo"] = "31", ["fecha_emision"] = "2026/04/15",
        ["rnc_emisor"] = rnc, ["rnc_comprador"] = "101000001",
        ["monto_total"] = 100.00m,
    }),
    ("RNC emisor con letras", new Dictionary<string, object?> {
        ["tipo"] = "31", ["fecha_emision"] = "15-04-2026",
        ["rnc_emisor"] = "ABC1933X2", ["rnc_comprador"] = "101000001",
        ["monto_total"] = 100.00m,
    }),
};

int aceptados = 0, rechazados = 0;
for (int i = 0; i < casos.Length; i++)
{
    var (label, data) = casos[i];
    var (ok, errores) = driver.Instancia.PreValidar(data);
    if (ok)
    {
        aceptados++;
        Console.WriteLine($"[{i + 1}] ✓ {label}");
    }
    else
    {
        rechazados++;
        Console.WriteLine($"[{i + 1}] ✗ {label}");
        foreach (var e in errores) Console.WriteLine($"       · {e}");
    }
}

Console.WriteLine($"\n--- Resumen ---");
Console.WriteLine($"Driver:     {meta.Entorno} v{meta.Version}");
Console.WriteLine($"Aceptados:  {aceptados}");
Console.WriteLine($"Rechazados: {rechazados}");
Console.WriteLine($"Total:      {casos.Length}");
