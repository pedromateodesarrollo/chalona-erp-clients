namespace EcfClient.Exceptions;

/// <summary>Error devuelto por el API (ok: false).</summary>
public class EcfApiException : Exception
{
    public string ErrorCode { get; }
    public new IReadOnlyDictionary<string, object?> Data { get; private set; }

    public EcfApiException(string message, IReadOnlyDictionary<string, object?>? data = null)
        : base(message)
    {
        ErrorCode = message;
        Data = data ?? new Dictionary<string, object?>();
    }
}

/// <summary>Error de validación local antes de enviar (comprobantes).</summary>
public class EcfValidationException : Exception
{
    public IReadOnlyList<ValidationError> Errors { get; }

    public EcfValidationException(string message, IReadOnlyList<ValidationError>? errors = null)
        : base(message)
    {
        Errors = errors ?? new List<ValidationError>();
    }
}

/// <summary>Un error de validación con path y código.</summary>
public record ValidationError(string Path, string Code, IReadOnlyDictionary<string, object?>? Params = null);
