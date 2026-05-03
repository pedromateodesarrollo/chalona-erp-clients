// Compilador one-shot: lee un archivo .cs, lo compila con Roslyn,
// escribe el .dll resultante.
//
// Uso: dotnet run --project ChalonaCsDriver.Compile -- <fuente.cs> <salida.dll>

using ChalonaCsDriver;

if (args.Length != 2)
{
    Console.Error.WriteLine("Uso: ChalonaCsDriver.Compile <fuente.cs> <salida.dll>");
    Environment.Exit(2);
}

var fuente = File.ReadAllText(args[0]);
var bytes = DriverCompiler.Compilar(fuente);
File.WriteAllBytes(args[1], bytes);
Console.Error.WriteLine($"   {bytes.Length} bytes → {args[1]}");
