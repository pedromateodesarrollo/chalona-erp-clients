using System.Reflection;
using System.Runtime.Loader;
using System.Security.Cryptography;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.CSharp;

namespace ChalonaCsDriver;

/// <summary>
/// Compila código C# fuente a bytes IL (.dll en memoria) usando Roslyn.
/// Equivalente a <c>dart_eval Compiler().compile()</c> en el cliente Dart.
/// </summary>
public static class DriverCompiler
{
    public static byte[] Compilar(string fuente, string nombreEnsamblado = "ChalonaCsDriverDinamico")
    {
        var syntaxTree = CSharpSyntaxTree.ParseText(fuente);

        // Referencias mínimas: System.Runtime + Linq + Collections + interfaz host
        var trustedAssemblies = (string)AppContext.GetData("TRUSTED_PLATFORM_ASSEMBLIES")!;
        var refs = trustedAssemblies
            .Split(Path.PathSeparator)
            .Select(p => MetadataReference.CreateFromFile(p))
            .Cast<MetadataReference>()
            .ToList();

        // Agregar el ensamblado de la interfaz IMotorEcf
        refs.Add(MetadataReference.CreateFromFile(typeof(IMotorEcf).Assembly.Location));

        var compilation = CSharpCompilation.Create(
            assemblyName: nombreEnsamblado,
            syntaxTrees: new[] { syntaxTree },
            references: refs,
            options: new CSharpCompilationOptions(OutputKind.DynamicallyLinkedLibrary, optimizationLevel: OptimizationLevel.Release));

        using var ms = new MemoryStream();
        var result = compilation.Emit(ms);
        if (!result.Success)
        {
            var errs = result.Diagnostics
                .Where(d => d.Severity == DiagnosticSeverity.Error)
                .Select(d => d.ToString());
            throw new InvalidOperationException(
                "Compilación falló:\n" + string.Join("\n", errs));
        }
        return ms.ToArray();
    }
}

/// <summary>
/// Handle a un motor cargado en runtime. Permite invocar Procesar (trampolín).
/// El AssemblyLoadContext es <c>collectible: true</c>, así que <see cref="Unload"/>
/// libera memoria de verdad (esto es lo que dart_eval no puede hacer).
/// </summary>
public sealed class DriverHandle : IDisposable
{
    public string Version { get; }
    public string HashSha256 { get; }
    public IMotorEcf Instancia { get; }
    private readonly AssemblyLoadContext _ctx;

    private DriverHandle(string version, string hash, IMotorEcf instancia, AssemblyLoadContext ctx)
    {
        Version = version;
        HashSha256 = hash;
        Instancia = instancia;
        _ctx = ctx;
    }

    public static DriverHandle Cargar(byte[] bytes, string version)
    {
        var hash = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
        var ctx = new AssemblyLoadContext($"chalona-driver-{version}", isCollectible: true);
        Assembly asm;
        using (var ms = new MemoryStream(bytes))
        {
            asm = ctx.LoadFromStream(ms);
        }

        var tipoDriver = asm.GetTypes()
            .FirstOrDefault(t => typeof(IMotorEcf).IsAssignableFrom(t) && !t.IsInterface && !t.IsAbstract)
            ?? throw new InvalidOperationException(
                $"No se encontró clase pública que implemente IMotorEcf en el ensamblado {asm.FullName}");

        var inst = (IMotorEcf)Activator.CreateInstance(tipoDriver)!;
        return new DriverHandle(version, hash, inst, ctx);
    }

    /// <summary>
    /// Descarga el ensamblado dinámico. Después de esto, las referencias a
    /// tipos del driver fallan — guarda los resultados antes de llamar.
    /// </summary>
    public void Unload() => _ctx.Unload();

    public void Dispose() => Unload();
}

/// <summary>
/// Cache local en disco de drivers descargados. Permite reusar bytes entre
/// arranques sin volver a bajarlos.
/// </summary>
public sealed class DriverCache
{
    public string Directorio { get; }

    public DriverCache(string directorio)
    {
        Directorio = directorio;
        Directory.CreateDirectory(directorio);
    }

    private string Archivo(string version) => Path.Combine(Directorio, $"driver-{version}.dll");

    public bool Tiene(string version) => File.Exists(Archivo(version));
    public byte[] Leer(string version) => File.ReadAllBytes(Archivo(version));
    public void Guardar(string version, byte[] bytes) => File.WriteAllBytes(Archivo(version), bytes);
}
