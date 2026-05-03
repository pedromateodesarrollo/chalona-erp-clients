#!/usr/bin/env bash
# Compila y publica una nueva versión del driver C# (.dll IL bytes) en
# data.cs_cliente_driver.
#
# Uso:
#   ./publicar.sh                          # entorno=test, fuente default
#   ./publicar.sh --produccion             # entorno=produccion
#   ./publicar.sh --fuente=driver_src/X.cs # otra fuente
#   PG_HOST=db.example.com ./publicar.sh   # override conexión

set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
DRIVER_DIR="$(dirname "$SCRIPT_PATH")"
FUENTE_DEFAULT="$DRIVER_DIR/driver_src/MotorEcfV1.cs"

PG_HOST="${PG_HOST:-localhost}"
PG_PORT="${PG_PORT:-5432}"
PG_DB="${PG_DB:-postgres}"
PG_USER="${PG_USER:-postgres}"
PG_PASS="${PG_PASS:-postgres}"

ENTORNO="test"
FUENTE=""

for arg in "$@"; do
  case "$arg" in
    --produccion) ENTORNO="produccion" ;;
    --test)       ENTORNO="test" ;;
    --fuente=*)   FUENTE="${arg#--fuente=}" ;;
    *) echo "Uso: $0 [--produccion|--test] [--fuente=<archivo.cs>]" >&2; exit 1 ;;
  esac
done

if [ -z "$FUENTE" ]; then
  FUENTE="$FUENTE_DEFAULT"
fi
if [ ! -f "$FUENTE" ] && [ -f "$DRIVER_DIR/$FUENTE" ]; then
  FUENTE="$DRIVER_DIR/$FUENTE"
fi
if [ ! -f "$FUENTE" ]; then
  echo "ERROR: no se encontró $FUENTE" >&2
  exit 1
fi

echo "== Compilando driver C# (Roslyn)..."
DLL_TMP="$(mktemp --suffix=.dll)"
trap 'rm -f "$DLL_TMP"' EXIT

dotnet run --project "$DRIVER_DIR/src/ChalonaCsDriver.Compile" -c Release -- "$FUENTE" "$DLL_TMP" >&2

TAMANO=$(wc -c < "$DLL_TMP")
HASH=$(sha256sum "$DLL_TMP" | awk '{print $1}')
echo "   ensamblado: $TAMANO bytes  sha256=${HASH:0:12}..."

echo "== Publicando → entorno='$ENTORNO' (BD $PG_DB en $PG_HOST:$PG_PORT)"

python3 - "$DLL_TMP" "$HASH" "$PG_HOST" "$PG_PORT" "$PG_DB" "$PG_USER" "$PG_PASS" "$ENTORNO" <<'PYEOF'
import sys, subprocess, os, base64

dll_path, hash_sha256, pg_host, pg_port, pg_db, pg_user, pg_pass, entorno = sys.argv[1:]

with open(dll_path, "rb") as f:
    bytes_b64 = base64.b64encode(f.read()).decode("ascii")

env = {**os.environ, "PGPASSWORD": pg_pass}
conn = ["-h", pg_host, "-p", pg_port, "-U", pg_user, "-d", pg_db, "-v", "ON_ERROR_STOP=1"]

def psql(sql):
    r = subprocess.run(["psql"] + conn + ["-t", "-A"],
                       input=sql, env=env, capture_output=True, text=True)
    if r.returncode != 0:
        print("ERROR psql:", r.stderr, file=sys.stderr)
        sys.exit(1)
    return r.stdout.strip()

sql = f"""
SELECT ok || '|' || message || '|' || (data->>'version')
FROM fn.cs_cliente_driver_publicar(jsonb_build_object(
  'session',     jsonb_build_object('trusted', true),
  'entorno',     '{entorno}',
  'bytes_b64',   $CHALONA_BYTES${bytes_b64}$CHALONA_BYTES$,
  'hash_sha256', '{hash_sha256}'
));
"""
raw = psql(sql)
ok, message, version = raw.split("|", 2)
if ok != "true":
    print(f"   ERROR: {message}", file=sys.stderr)
    sys.exit(1)
print(f"   entorno={entorno!r:<12} → v{version} activo")
PYEOF

echo "== Listo."
