using System.Text.Json;
using Npgsql;

namespace ChalonaCsDriver;

public sealed record DriverMeta(int Version, string Entorno, string HashSha256, int Tamano);

/// <summary>
/// Lookup + descarga del driver C# desde data.cs_cliente_driver via Npgsql.
/// Equivalente a PostgresDriverSource del cliente Dart.
/// </summary>
public sealed class PostgresDriverSource : IAsyncDisposable
{
    public string Entorno { get; }
    private readonly string _connStr;
    private NpgsqlConnection? _conn;

    public PostgresDriverSource(
        string host,
        int port,
        string database,
        string username,
        string password,
        string entorno)
    {
        if (entorno != "test" && entorno != "produccion")
            throw new ArgumentException("entorno debe ser 'test' o 'produccion'", nameof(entorno));
        Entorno = entorno;
        _connStr = new NpgsqlConnectionStringBuilder
        {
            Host = host,
            Port = port,
            Database = database,
            Username = username,
            Password = password,
            SslMode = SslMode.Disable,
        }.ConnectionString;
    }

    private async Task<NpgsqlConnection> OpenAsync()
    {
        if (_conn != null) return _conn;
        _conn = new NpgsqlConnection(_connStr);
        await _conn.OpenAsync();
        return _conn;
    }

    public async Task<DriverMeta?> LookupAsync()
    {
        var c = await OpenAsync();
        await using var cmd = new NpgsqlCommand(
            @"SELECT ok, message, data::text
              FROM fn.cs_cliente_driver_lookup(jsonb_build_object(
                'session', jsonb_build_object('trusted', true),
                'entorno', @entorno::text
              ))", c);
        cmd.Parameters.AddWithValue("entorno", Entorno);

        await using var rdr = await cmd.ExecuteReaderAsync();
        await rdr.ReadAsync();
        var ok = rdr.GetBoolean(0);
        var msg = rdr.GetString(1);
        var dataJson = rdr.GetString(2);
        if (!ok)
        {
            if (msg == "cs_cliente_driver.no_disponible") return null;
            throw new InvalidOperationException($"lookup falló: {msg}");
        }
        var data = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(dataJson)!;
        return new DriverMeta(
            Version: data["version"].GetInt32(),
            Entorno: data["entorno"].GetString()!,
            HashSha256: data["hash_sha256"].GetString()!,
            Tamano: data["tamano"].GetInt32());
    }

    public async Task<byte[]> DescargarAsync(int? version = null)
    {
        var c = await OpenAsync();
        await using var cmd = new NpgsqlCommand(
            @"SELECT ok, message, data::text
              FROM fn.cs_cliente_driver_descargar(jsonb_build_object(
                'session', jsonb_build_object('trusted', true),
                'entorno', @entorno::text,
                'version', @version::text
              ))", c);
        cmd.Parameters.AddWithValue("entorno", Entorno);
        cmd.Parameters.AddWithValue("version", (object?)version?.ToString() ?? "");

        await using var rdr = await cmd.ExecuteReaderAsync();
        await rdr.ReadAsync();
        var ok = rdr.GetBoolean(0);
        var msg = rdr.GetString(1);
        var dataJson = rdr.GetString(2);
        if (!ok) throw new InvalidOperationException($"descarga falló: {msg}");
        var data = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(dataJson)!;
        // Postgres encode(..., 'base64') intercala '\n' cada 76 chars; Convert.FromBase64String los tolera
        var b64 = data["bytes_b64"].GetString()!;
        return Convert.FromBase64String(b64);
    }

    public async ValueTask DisposeAsync()
    {
        if (_conn != null)
        {
            await _conn.DisposeAsync();
            _conn = null;
        }
    }
}
