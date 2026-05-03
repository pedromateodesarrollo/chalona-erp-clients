#!/usr/bin/env bash
# Publica EcfClient en NuGet. Requiere NUGET_API_KEY en el entorno.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/src/EcfClient"

if [[ -z "${NUGET_API_KEY:-}" ]]; then
  echo "Define NUGET_API_KEY con tu API key de nuget.org antes de ejecutar."
  echo "  export NUGET_API_KEY=tu_token"
  exit 1
fi

dotnet pack "$PROJECT_DIR/EcfClient.csproj" -c Release -o "$SCRIPT_DIR/out"
NUPKG=$(ls "$SCRIPT_DIR/out"/EcfClient.*.nupkg 2>/dev/null | head -1)
if [[ -z "$NUPKG" ]]; then
  echo "No se generó el .nupkg"
  exit 1
fi
dotnet nuget push "$NUPKG" --api-key "$NUGET_API_KEY" --source https://api.nuget.org/v3/index.json
echo "Publicado: $NUPKG"
