#!/usr/bin/env bash
# Compila y publica una nueva versión del driver TypeScript (JS source UTF-8)
# en data.ts_cliente_driver.
#
# Uso:
#   ./publicar.sh                           # entorno=test, fuente default
#   ./publicar.sh --produccion              # entorno=produccion
#   ./publicar.sh --fuente=driver_src/X.ts  # otra fuente
#   PG_HOST=db.example.com ./publicar.sh    # override conexión

set -euo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
DRIVER_DIR="$(dirname "$SCRIPT_PATH")"
FUENTE_DEFAULT="$DRIVER_DIR/driver_src/driver-comprobantes.ts"

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
    -h|--help)    sed -n '2,15p' "$SCRIPT_PATH"; exit 0 ;;
    *) echo "Uso: $0 [--produccion|--test] [--fuente=<archivo.ts>]" >&2; exit 1 ;;
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

# Asegurar deps (tsc local + @types/node)
if [ ! -x "$DRIVER_DIR/node_modules/.bin/tsc" ]; then
  echo "== Instalando deps TS (primer run)..."
  (cd "$DRIVER_DIR" && npm install --silent)
fi

# Build dist/ (compila tooling propio del driver)
echo "== Compilando tooling TS..."
(cd "$DRIVER_DIR" && ./node_modules/.bin/tsc -p tsconfig.json)

echo "== Compilando driver TS..."
JS_TMP="$(mktemp --suffix=.js)"
trap 'rm -f "$JS_TMP"' EXIT

node "$DRIVER_DIR/dist/bin/compilar.js" "$FUENTE" "$JS_TMP"
TAMANO=$(wc -c < "$JS_TMP")
HASH=$(sha256sum "$JS_TMP" | awk '{print $1}')
echo "   JS source: $TAMANO bytes  sha256=${HASH:0:12}..."

echo "== Publicando → entorno='$ENTORNO' (BD $PG_DB en $PG_HOST:$PG_PORT)"

python3 - "$JS_TMP" "$HASH" "$PG_HOST" "$PG_PORT" "$PG_DB" "$PG_USER" "$PG_PASS" "$ENTORNO" <<'PYEOF'
import sys, subprocess, os, base64

js_path, hash_sha256, pg_host, pg_port, pg_db, pg_user, pg_pass, entorno = sys.argv[1:]

with open(js_path, "rb") as f:
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
SELECT ok || '|' || message || '|' || coalesce(data->>'version', '?')
FROM fn.ts_cliente_driver_publicar(jsonb_build_object(
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
